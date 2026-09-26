; stage2.asm — Lesson 2: code loaded from disk by our boot sector
; Code guide: lessons/02-stage2-loader.md explains the stage handoff;
; lessons/03-physical-memory-map.md explains E820 and hexadecimal output;
; lessons/04-a20-line.md explains access beyond the first MiB;
; lessons/05-protected-mode.md explains the GDT and the 32-bit transition.
;
; Stage 1 loads this flat binary at physical address 0000:8000 and performs a
; far jump there. We are still in 16-bit real mode, so BIOS interrupts remain
; available. Unlike the boot sector, stage 2 is not loaded by BIOS automatically
; and does not require a 55 AA signature.

bits 16
org 0x8000

STAGE2_SIZE equ 4 * 512

; Convert a label's offset within this flat binary to its RAM address. BIOS does
; not load stage 2; stage 1 places its first byte at address 8000h.
%define stage2_address(label) (0x8000 + (label - $$))

stage2_start:
    ; LODSB will read from DS:SI, so stage 2 must establish both parts of that
    ; address. x86 cannot copy an immediate number directly into DS. We first put
    ; zero in AX, then copy AX into DS. DS remains zero until code changes it, so
    ; it needs to be initialized once here rather than before every LODSB.
    xor ax, ax                  ; AX = 0.
    mov ds, ax                 ; DS = AX = 0.
    mov es, ax                 ; ES = 0 for other data operations used later.
    cld                        ; Make LODSB increment SI after reading each byte.

    ; SI supplies the changing offset. With DS=0 and SI set to the message's
    ; address, DS:SI identifies the first message byte.
    mov si, 0x8000 + (message - $$)
    call print_string

    call ensure_a20
    test ax, ax
    jz a20_failure

    mov si, stage2_address(a20_ready_message)
    call print_string

    call print_memory_map

    call enter_protected_mode

    cli
.halt:
    hlt
    jmp .halt

a20_failure:
    mov si, stage2_address(a20_error_message)
    call print_string
    cli
.halt:
    hlt
    jmp .halt

; Return AX=1 when address line A20 is enabled. If it is initially disabled, ask
; BIOS to enable it and then test again. Returning AX=0 means both paths failed.
ensure_a20:
    call check_a20
    test ax, ax
    jnz .ready

    ; INT 15h, AX=2401h is the BIOS request to enable A20. Preserve our data
    ; segment registers around firmware code, then verify the hardware state.
    push ds
    push es
    mov ax, 0x2401
    int 0x15
    pop es
    pop ds
    jc .failed

    call check_a20
    ret

.ready:
    mov ax, 1
    ret

.failed:
    xor ax, ax
    ret

; Enter 32-bit protected mode. This routine does not return: the far jump below
; transfers execution to protected_mode_entry, which is assembled as 32-bit code.
enter_protected_mode:
    cli
    lgdt [stage2_address(gdt_descriptor)]

    mov eax, cr0
    or eax, 0x00000001          ; Set CR0.PE: enable protected mode.
    mov cr0, eax

    ; A far jump reloads CS from the GDT. Selector 0x08 chooses descriptor 1,
    ; our flat 32-bit code descriptor. The jump is required after setting PE so
    ; the processor begins fetching instructions under the new rules.
    jmp dword 0x08:stage2_address(protected_mode_entry)

; The first descriptor is required to be unusable. Selectors 0x08 and 0x10 then
; refer to the code and data descriptors below (each descriptor is 8 bytes).
gdt_start:
    dq 0x0000000000000000       ; Selector 0x00: null descriptor.

    dw 0xffff                    ; Selector 0x08: code limit, low 16 bits.
    dw 0x0000                    ; Code base, low 16 bits.
    db 0x00                      ; Code base, next 8 bits.
    db 10011010b                 ; Present, ring 0, executable, readable.
    db 11001111b                 ; 4 KiB granularity, 32-bit default, limit high.
    db 0x00                      ; Code base, high 8 bits.

    dw 0xffff                    ; Selector 0x10: data limit, low 16 bits.
    dw 0x0000                    ; Data base, low 16 bits.
    db 0x00                      ; Data base, next 8 bits.
    db 10010010b                 ; Present, ring 0, writable data.
    db 11001111b                 ; 4 KiB granularity, 32-bit default, limit high.
    db 0x00                      ; Data base, high 8 bits.
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; Size is last byte offset, not byte count.
    dd stage2_address(gdt_start) ; Physical address of the first descriptor.

; From this point onward NASM encodes ordinary instructions with 32-bit defaults.
bits 32

protected_mode_entry:
    mov ax, 0x10                 ; Data-segment selector from the GDT.
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x00090000          ; Stack in the low usable-RAM range.

    mov esi, stage2_address(pm_message)
    call pm_print_string

.halt:
    cli
    hlt
    jmp .halt

; Print a null-terminated string without BIOS. BIOS INT instructions are real-mode
; services; in protected mode we write directly to the VGA text buffer and mirror
; characters to QEMU's debug port.
pm_print_string:
    mov edi, 0x000b8000         ; VGA text memory: character/attribute pairs.
    mov ah, 0x07                ; Light gray on black.

.next:
    mov al, [esi]
    inc esi
    test al, al
    jz .done

    mov [edi], al               ; Character byte.
    mov [edi + 1], ah           ; Attribute byte.
    add edi, 2
    out 0xe9, al                ; QEMU debug output still accepts port E9h.
    jmp .next

.done:
    ret

bits 16

; Determine whether addresses separated by exactly 1 MiB refer to different RAM
; bytes. When A20 is disabled, 0000:0500 and FFFF:0510 alias the same physical
; byte. Save both original values, perform the test, and restore them afterward.
;
; Return: AX=1 when A20 is enabled; AX=0 when it is disabled.
check_a20:
    pushf
    cli
    push bx
    push ds
    push es
    push si
    push di

    xor ax, ax
    mov es, ax
    mov di, 0x0500              ; ES:DI = 0000:0500 -> address 00000500h.

    mov ax, 0xffff
    mov ds, ax
    mov si, 0x0510              ; DS:SI = FFFF:0510 -> address 00100500h.

    mov bl, [es:di]             ; Preserve the original low-address byte.
    mov bh, [ds:si]             ; Preserve the original high-address byte.

    mov byte [es:di], 0x00
    mov byte [ds:si], 0xff

    xor ax, ax                  ; Default result: disabled.
    cmp byte [es:di], 0xff      ; Did the high write change the low address?
    je .restore                 ; Yes: the two addresses alias, so A20 is disabled.
    mov ax, 1                   ; No: the addresses are distinct, so A20 is enabled.

.restore:
    mov [ds:si], bh
    mov [es:di], bl

    pop di
    pop si
    pop es
    pop ds
    pop bx
    popf
    ret

; Ask BIOS for the physical-memory map and print every returned region.
;
; BIOS INT 15h, operation E820h, returns one region per call. EBX is a
; continuation value: zero begins the enumeration, and BIOS returns zero after
; the last successful entry. ES:DI points to the buffer BIOS will fill.
print_memory_map:
    mov si, stage2_address(memory_map_heading)
    call print_string

    xor ebx, ebx                ; Zero means "request the first map entry."

.next_entry:
    mov eax, 0xe820             ; BIOS operation: return one memory-map entry.
    mov edx, 0x534d4150         ; Input signature: ASCII letters "SMAP".
    mov ecx, 24                 ; Buffer capacity in bytes.
    mov di, stage2_address(e820_buffer)
    mov dword [stage2_address(e820_buffer) + 20], 1
    int 0x15

    jc .failed                  ; Carry Flag set means BIOS rejected the request.
    cmp eax, 0x534d4150         ; A valid response returns the "SMAP" signature.
    jne .failed

    ; Every usable E820 response must contain at least the original 20-byte
    ; record. A 24-byte response also contains extended attributes. In that
    ; newer form, bit 0 clear means BIOS says to ignore this entry.
    cmp ecx, 20
    jb .failed
    cmp ecx, 24
    jb .check_length
    test dword [stage2_address(e820_buffer) + 20], 1
    jz .continue

    ; BIOS may return a zero-length entry. Such an entry describes no addresses,
    ; so omit it from the displayed list.
.check_length:
    mov eax, [stage2_address(e820_buffer) + 8]
    or eax, [stage2_address(e820_buffer) + 12]
    jz .continue

    ; Preserve EBX because it contains the continuation value required by the
    ; next BIOS call. The printing helpers also preserve it, but keeping this
    ; pair here makes the lifetime of this BIOS-provided value explicit.
    push ebx

    mov si, stage2_address(region_prefix)
    call print_string
    mov eax, [stage2_address(e820_buffer) + 4] ; High 32 bits of base.
    call print_hex32
    mov eax, [stage2_address(e820_buffer)]     ; Low 32 bits of base.
    call print_hex32

    mov si, stage2_address(length_prefix)
    call print_string
    mov eax, [stage2_address(e820_buffer) + 12] ; High 32 bits of length.
    call print_hex32
    mov eax, [stage2_address(e820_buffer) + 8]  ; Low 32 bits of length.
    call print_hex32

    mov si, stage2_address(type_prefix)
    call print_string
    mov eax, [stage2_address(e820_buffer) + 16] ; BIOS region-type number.
    call print_hex32

    mov si, stage2_address(newline)
    call print_string

    pop ebx

.continue:
    test ebx, ebx               ; Zero after success means that was the last entry.
    jnz .next_entry
    ret

.failed:
    mov si, stage2_address(memory_map_error)
    call print_string
    ret

; Input: DS:SI points to a null-terminated byte string.
; The implementation is intentionally local to stage 2: an ordinary near CALL
; cannot safely reuse stage 1 forever once memory is reclaimed or modes change.
print_string:
    lodsb
    test al, al
    jz .done

    call print_character
    jmp print_string

.done:
    ret

; Print the character in AL to both QEMU's debug console and the BIOS display.
; Preserve AX and BX so callers do not lose values they are still using.
print_character:
    push ax
    push bx

    out 0xe9, al               ; QEMU-only debug output.

    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10

    pop bx
    pop ax
    ret

; Print the 32-bit value in EAX as exactly eight hexadecimal digits.
; Example: the value 4096 is printed as 00001000.
print_hex32:
    push eax
    push ebx
    push ecx
    push edx
    push si

    mov edx, eax                ; Keep the rotating number separate from AL,
                                ; which print_character uses for text output.
    mov ecx, 8                  ; A 32-bit number contains eight hexadecimal digits.

.next_digit:
    rol edx, 4                  ; Move the next highest digit into DL's low 4 bits.
    mov ebx, edx
    and ebx, 0x0f               ; Keep only that 4-bit value (0 through 15).
    mov si, stage2_address(hex_digits)
    add si, bx
    mov al, [si]                ; Convert the value to its display character.
    call print_character
    loop .next_digit

    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

message db 'Stage 2: loaded successfully!', 13, 10, 0
a20_ready_message db 'A20: addresses above 1 MiB are accessible.', 13, 10, 0
a20_error_message db 'A20: BIOS could not enable the address line.', 13, 10, 0
memory_map_heading db 'Physical memory map:', 13, 10, 0
region_prefix      db '  base=0x', 0
length_prefix      db ' length=0x', 0
type_prefix        db ' type=0x', 0
newline            db 13, 10, 0
memory_map_error   db 'BIOS memory-map request failed.', 13, 10, 0
hex_digits         db '0123456789ABCDEF'
pm_message         db 'Protected mode: 32-bit code is running!', 13, 10, 0

; BIOS writes one E820 record here. Its maximum form occupies 24 bytes:
; base address (8), length (8), type (4), and extended attributes (4).
e820_buffer:
    times 24 db 0

; Fixed-size padding makes the disk-image contract unambiguous. Stage 1 always
; reads four sectors, so this file must occupy exactly four sectors even though
; most bytes are currently unused.
times STAGE2_SIZE - ($ - $$) db 0
