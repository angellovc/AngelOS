; boot.asm — Lesson 1: taking control from a legacy BIOS
; Code guide: lessons/01-bios-boot-sector.md explains initialization and output;
; lessons/02-stage2-loader.md explains the disk request and stage-2 handoff.
;
; Goal:
;   Establish a known CPU environment, preserve the BIOS boot-drive number,
;   load our larger second-stage program from disk, and transfer control to it.
;
; Build:
;   nasm -f bin -Wall -Werror boot/boot.asm -o build/boot.bin
;
; Why `-f bin`?
;   Many program files contain extra information for an operating system that
;   loads them. No operating system exists beneath our boot sector. BIOS expects
;   the sector's instruction bytes directly, so NASM must emit only those bytes.
;
; Simplified legacy-BIOS boot sequence:
;   1. Firmware performs its power-on initialization and selects a boot device.
;   2. It reads that device's first 512-byte sector into physical address 07C00h.
;   3. It verifies that the sector's final bytes are 55h AAh.
;   4. It enters our sector in 16-bit real mode.
;
; Important limitation:
;   BIOS implementations commonly enter at 0000:7C00, but 07C0:0000 names the
;   same physical address and some register state is unspecified. We immediately
;   establish our own segment registers and stack instead of trusting leftovers.

bits 16                        ; Encode instructions for 16-bit real mode.
org 0x7c00                     ; Labels represent their runtime addresses because
                               ; the BIOS placed this binary at physical 07C00h.

start:
    cli                        ; Clear IF, temporarily blocking maskable hardware
                               ; interrupts while SS:SP is only half configured.

    xor ax, ax                 ; AX = 0. XOR is a compact way to zero a register.
    mov ds, ax                 ; DS:SI will address our message as 0000:xxxx.
    mov es, ax                 ; Establish ES too, even though this lesson does
                               ; not use it. Later string/disk code will.

    ; Updating SS and SP is logically one operation: together they select the
    ; stack. An interrupt between them could push state through an invalid stack,
    ; hence CLI above. The stack begins immediately below our boot sector and
    ; grows toward lower addresses. This is adequate only for the tiny loader.
    mov ss, ax
    mov sp, 0x7c00

    cld                        ; Clear the Direction Flag so LODSB advances SI.
                               ; Never depend on firmware leaving DF clear.
    sti                        ; Our stack is valid, so interrupts may resume.

    ; Before BIOS jumps to this bootloader, it writes a device-identification
    ; number into the 8-bit DL register. That number identifies the disk from
    ; which BIOS read this boot sector. Typical values are 00h for the first
    ; floppy and 80h for the first hard disk. We save the exact number. Later,
    ; `int 13h` will enter a BIOS routine that can read disk sectors. Before that
    ; instruction, we put the saved number back in DL so BIOS knows which disk
    ; it should read. This matters when the computer has more than one disk.
    mov [0x7c00 + (boot_drive - $$)], dl

    mov si, 0x7c00 + (loading_message - $$)
    call print_string

    ; INT 13h/AH=02h reads sectors using legacy CHS coordinates:
    ;   CH = cylinder, CL = sector (numbering starts at 1), DH = head,
    ;   DL = BIOS drive, AL = number of sectors, ES:BX = destination buffer.
    ; Sector 1 is this boot sector, so stage 2 begins at sector 2. The Makefile
    ; pads stage 2 to exactly STAGE2_SECTORS sectors and builds that disk layout.
    mov ah, 0x02
    mov al, STAGE2_SECTORS
    mov ch, 0x00
    mov cl, 0x02
    mov dh, 0x00
    mov dl, [0x7c00 + (boot_drive - $$)]
    mov bx, STAGE2_LOAD_ADDRESS ; ES is already zero: destination = 0000:8000.
    int 0x13

    ; BIOS reports disk errors through the Carry Flag. AL is not a portable way
    ; to validate the number of sectors transferred, despite some BIOSes setting
    ; it. A production loader will retry and use extended LBA reads; this first
    ; version deliberately uses the simplest complete disk-read transaction.
    jc disk_error

    ; A far jump explicitly establishes both CS and IP. Stage 2 was assembled
    ; with ORG 8000h and expects zero-based segments, so enter it as 0000:8000.
    jmp 0x0000:STAGE2_LOAD_ADDRESS

disk_error:
    mov si, 0x7c00 + (disk_error_message - $$)
    call print_string
    jmp halt_forever

; Input: DS:SI points to a null-terminated string.
; Output: characters have been emitted; SI points just after the null byte.
; Clobbers: AX and BIOS-defined flags. BX is assigned for each BIOS call.
print_string:

.print_character:
    lodsb                      ; Load byte at DS:SI into AL, then increment SI
                               ; because CLD established forward traversal.

    test al, al                ; Compute AL AND AL only to update status flags;
                               ; AL itself remains unchanged. A zero byte marks
                               ; the end of our C-style string.
    jz .done                   ; Jump when TEST set the Zero Flag (AL was zero).

    ; INT does not mean a Unix signal or a hardware interrupt here. `int 10h`
    ; deliberately indexes entry 10h in the real-mode Interrupt Vector Table and
    ; transfers control to a BIOS video routine. AH selects service 0Eh; AL holds
    ; the character. BH is display page 0 and BL is color 7 where applicable.
    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10

    ; `OUT` writes AL to an I/O port rather than memory. QEMU's debug device can
    ; listen on port E9h, letting automated tests see text without a display.
    ; This is a QEMU debugging convention, not a BIOS service or PC guarantee.
    out 0xe9, al
    jmp .print_character       ; Repeat for the following byte.

.done:
    ret

halt_forever:
    ; HLT sleeps only until an interrupt arrives. If IF remained set, timer or
    ; keyboard interrupts could wake the CPU repeatedly. CLI makes this terminal
    ; state permanent for maskable interrupts. The loop is defensive because an
    ; NMI, SMI, reset, or unusual virtual-machine event can still resume execution.
    cli
.forever:
    hlt
    jmp .forever

; EQU means "equate this name with this constant." These lines create readable
; names for NASM to use while assembling; they emit no bytes and create no RAM
; variables. NASM replaces STAGE2_SECTORS with 4 in instructions that use it.
STAGE2_LOAD_ADDRESS equ 0x8000
STAGE2_SECTORS      equ 4

loading_message    db 'Stage 1: loading stage 2...', 13, 10, 0
disk_error_message db 'Disk read failed.', 13, 10, 0
boot_drive         db 0

; `$` is NASM's current position and `$$` is the beginning of this section.
; Their difference is our current binary size. Fill with zeros through byte 509,
; leaving exactly two bytes for the boot signature. A negative TIMES value makes
; assembly fail if our code grows beyond the sector instead of silently truncating.
times 510 - ($ - $$) db 0

; x86 stores a 16-bit word least-significant byte first, so DW 0AA55h produces
; bytes 55 AA in the file. This signature marks the sector as bootable to BIOS.
dw 0xaa55
