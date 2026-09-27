# Our bootloader: hardware → assembly → C

Assembly has a structure we can learn. The useful starting point is the actual
problem each instruction solves, rather than a list of instruction names.

All assembly snippets below come from [`boot.asm`](../boot/boot.asm) or
[`stage2.asm`](../boot/stage2.asm). We examine small parts at a time.
The C examples explain those parts' behavior; they are not runnable replacements
for the bootloader. Names such as `bios_enable_a20()` represent hardware services
that ordinary portable C cannot directly implement.

`uint8_t`, `uint16_t`, `uint32_t`, and `uint64_t` mean unsigned integer types
occupying 8, 16, 32, and 64 bits. Eight bits make one byte.

## 1. Entry point: somebody gives the CPU an address

**Hardware.** The CPU needs an instruction address. In our BIOS boot path,
firmware loads the first disk sector into memory at `0x7c00` and enters it.
The build places our stage 1 instructions at the beginning of that sector.

**Assembly — boot.asm:**

```asm
bits 16
org 0x7c00

start:
    cli
```

`bits` and `org` instruct NASM, the assembler. `start` names the following
location. Only `cli` becomes the first executed instruction.

**C connection.** In a typical hosted C program, startup code eventually calls
`main`. The CPU does not recognize the word `main` either: the toolchain and
startup environment arrange that transfer. Our raw boot sector has no such C
startup machinery. BIOS supplies the first transfer directly.

A label is an address name, not a function declaration or an entry-point marker.
If we renamed `start`, the same first byte would still execute.

## 2. Register classes: why zeroing DS takes two instructions

**Hardware.** AX is working storage for arithmetic and bit operations. DS is
segment state used to calculate memory addresses. They are different register
classes even though both visible values here are 16 bits.

**Assembly — both files:**

```asm
xor ax, ax
mov ds, ax
```

XOR produces zero when each bit is combined with itself. MOV then copies that
zero into DS. The instruction set provides these forms:

```text
XOR general register with general register → supported
MOV general register into DS             → supported
XOR using DS as an operand                → no encoding
MOV an immediate number directly into DS → no encoding
```

So `xor ax, bx` is valid, but `xor ax, ds` is not. The spelling is `xor`, not
`xord`; AX versus EAX selects 16-bit versus 32-bit operation size.

**C connection.** At the level of intent this means “set the data segment to
zero,” but standard C has no `DS` variable you can assign to. A conceptual model
could say `cpu.ds = 0`; implementing that action on real hardware still requires
supported machine instructions.

Think of each instruction as having accepted operand signatures. NASM does not
automatically expand an unsupported register combination into multiple operations
as a higher-level compiler might.

## 3. A variable: boot_drive is one byte in memory

**Hardware.** BIOS puts the boot disk's number into DL, the lower eight bits of
DX. We need that number later, even while registers are used for other work.

**Assembly — boot.asm:**

```asm
mov [0x7c00 + (boot_drive - $$)], dl
```

The storage is declared later:

```asm
boot_drive db 0
```

`db 0` emits one initial zero byte. `boot_drive` names its location. The bracketed
expression calculates that location in RAM and writes DL there.

```text
CPU: DL contains boot disk number
                │ copy one byte
                ▼
RAM: boot_drive now contains that number
```

`$$` is the beginning of the assembly section. Subtracting it gives the label's
position within the binary; adding `0x7c00` gives the loaded address.

**C model:**

```c
uint8_t boot_drive = 0;       // storage initialized before use

/* On entry, after BIOS supplies its register value: */
boot_drive = bios_drive_number;
```

The C declaration corresponds to the data byte; the assignment corresponds to
MOV. NASM's `db` is not an assignment instruction executed at that point.

## 4. A constant: STAGE2_SECTORS has no memory location

**Hardware.** The disk request needs the number four in AL. We do not need to
read that number from a variable.

**Assembly — boot.asm:**

```asm
STAGE2_SECTORS equ 4
```

Used earlier in the request:

```asm
mov al, STAGE2_SECTORS
```

NASM puts the value directly into the instruction encoding. `equ` names a
number; it does not emit a storage byte like `db` does.

**C model:**

```c
enum { STAGE2_SECTORS = 4 };
```

This resembles a constant expression more closely than a stored variable.
C's `const uint8_t sectors = 4` declares an object with a restriction against
modification; that is a different concept. `equ` does not configure hardware
write protection.

## 5. A pointer: DS:SI locates the message

**Hardware.** RAM is a collection of numbered bytes. To read a message, we need
its beginning address and a changing position as we move through its characters.

**Assembly — boot.asm:**

```asm
mov si, 0x7c00 + (loading_message - $$)
call print_string
```

The message storage is:

```asm
loading_message db 'Stage 1: loading stage 2...', 13, 10, 0
```

MOV puts the address in SI, not the message bytes. With DS=0, real-mode address
calculation gives:

```text
physical address = DS × 16 + SI = SI
```

**C model:**

```c
char loading_message[] = "Stage 1: loading stage 2...\r\n";
const char *p = loading_message;
print_string(p);
```

The C string includes a final zero automatically. `\r` and `\n` represent the
same carriage-return and line-feed bytes as 13 and 10.

The pointer analogy assumes our known zero segment. SI alone is a 16-bit
offset, not a general C pointer capable of naming all memory.

## 6. A loop and dereference: reading one character

**Hardware.** Read the byte at the current address, move forward, test whether
it marks the end, and repeat if there is another character.

**Assembly — stage2.asm:**

```asm
print_string:
    lodsb
    test al, al
    jz .done

    call print_character
    jmp print_string

.done:
    ret
```

With the Direction Flag cleared by `cld`, LODSB does two things:

```text
AL receives memory[DS:SI]
SI increases by one
```

TEST sets the Zero Flag when AL is zero; JZ uses that flag to choose the return
path. The backward JMP repeats without saving another return address.

**C model:**

```c
void print_string(const uint8_t *p) {
    for (;;) {
        uint8_t character = *p++;
        if (character == 0) return;
        print_character(character);
    }
}
```

`*p` reads through the pointer; `p++` advances it. The assembly interface also
leaves the caller's SI advanced past the zero. C's local pointer advancement
would not itself update a caller's pointer variable.

## 7. An array: hex_digits is a lookup table

**Hardware.** A four-bit number has 16 possible values. To display it, we select
one of 16 adjacent character bytes.

**Assembly — stage2.asm:**

```asm
hex_digits db '0123456789ABCDEF'
```

Inside `print_hex32`:

```asm
mov ebx, edx
and ebx, 0x0f
mov si, stage2_address(hex_digits)
add si, bx
mov al, [si]
call print_character
```

AND keeps only the lowest four bits, producing an index from 0 to 15. Adding
that index to the array address chooses a character. Brackets load that byte.

```text
index = 10
hex_digits + 10 → byte 'A' → AL → print_character
```

**C model:**

```c
static const char hex_digits[16] = {
    '0','1','2','3','4','5','6','7',
    '8','9','A','B','C','D','E','F'
};
uint32_t index = number & 0x0f;
char character = hex_digits[index];
print_character(character);
```

Each element is one byte, so the index equals the byte displacement. Larger
elements require multiplying the index by their size. The hardware does not
know this is an array; the instructions implement the indexing rule.

The C `const` describes our intention not to modify the lookup table. The
assembly's bytes remain writable in our current memory setup.

## 8. A function contract: ensure_a20 returns its answer in AX

**Hardware.** A20 controls whether certain addresses one MiB apart remain
distinct. We need an operation that answers “is it enabled now?”

**Assembly — stage2.asm, caller:**

```asm
call ensure_a20
test ax, ax
jz a20_failure
```

The routine uses AX=1 for success and AX=0 for failure. CALL saves the return
address on the stack; RET returns there. Neither instruction chooses AX as the
result register. That is an agreement made by our code.

**C model of the routine:**

```c
bool ensure_a20(void) {
    if (check_a20()) return true;
    if (!bios_enable_a20()) return false;
    return check_a20();
}
```

**C model of the caller:**

```c
if (!ensure_a20()) {
    goto a20_failure;
}
```

The BIOS request is made through `int 0x15` with AX=`0x2401`, and failure is
reported in Carry. `bios_enable_a20()` here is a descriptive placeholder for
that interface, not a standard C library function.

This explains what a function really needs: an entry address, input/output
agreements, rules about changed registers, and a way to return. A label alone
provides only the entry address.

## 9. Saving registers: temporarily borrowing the caller's storage

**Hardware.** Printing needs AX and BX, but the caller may still need their
values. The stack gives us temporary storage and a last-in-first-out order.

**Assembly — stage2.asm:**

```asm
print_character:
    push ax
    push bx

    out 0xe9, al

    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10

    pop bx
    pop ax
    ret
```

PUSH saves values; POP restores them in reverse order. The saved return address
must be back at the top before RET.

**C connection.** When a C function calls another, the compiler follows rules
about which registers the caller may expect to survive. Here we write those
preservation instructions ourselves. OUT and INT still require hardware-specific
implementations; a normal C function call does not reproduce them automatically.

## 10. A record: e820_buffer contains fields at fixed offsets

**Hardware.** BIOS writes a memory-region description into 24 bytes of RAM.
Both sides must agree where each field begins.

**Assembly — stage2.asm:**

```asm
e820_buffer:
    times 24 db 0
```

The code accesses fields using displacements:

```asm
mov eax, [stage2_address(e820_buffer) + 16]
```

That reads the four-byte region type starting 16 bytes into the buffer.

**C model of the record's fields:**

```c
struct MemoryRegion {
    uint64_t base;        // required byte offset 0
    uint64_t length;      // required byte offset 8
    uint32_t type;        // required byte offset 16
    uint32_t attributes;  // required byte offset 20
};
```

The corresponding access is `region.type`. Actual C interoperability must verify
field offsets, total size, and byte order; a C declaration is not by itself a
portable promise of a firmware layout. BIOS may return only the first 20 bytes,
which is why our code checks the returned size before inspecting attributes.

## 11. Direct memory output: a pointer to a device buffer

**Hardware.** In our VGA text setup, memory beginning at `0xb8000` controls
screen cells. Each cell has a character byte and an attribute byte for color.

**Assembly — stage2.asm, in protected mode:**

```asm
mov edi, 0x000b8000
mov ah, 0x07
```

Then for each character already in AL:

```asm
mov [edi], al
mov [edi + 1], ah
add edi, 2
```

**C model for this specific machine environment:**

```c
volatile uint8_t *screen = (volatile uint8_t *)0xb8000;
screen[0] = character;
screen[1] = 0x07;
screen += 2;
```

`volatile` tells the C compiler these accesses are observable and must not be
removed as unused ordinary memory writes. It does not create the device, map
its address, or provide general synchronization. Our hardware environment makes
that address meaningful. The assembly MOV instructions already request explicit
writes, one byte at a time.

## 12. Local and global: names are not storage lifetimes

**Assembly — stage2.asm contains both:**

```asm
print_string:
    lodsb
    test al, al
    jz .done
```

and, elsewhere:

```asm
pm_print_string:
    mov edi, 0x000b8000
```

Both routines define `.done` later. NASM distinguishes them as
`print_string.done` and `pm_print_string.done`. The dot organizes names relative
to the preceding non-local label. It does not allocate local variables.

**C connection.** A C function's local variables and a NASM local label are
different concepts. `boot_drive` is fixed storage shared by code that accesses
its address. `.done` is a named instruction position.

NASM also has a `global` directive for exporting symbols in object-file builds
for a linker to connect. Our raw boot binaries do not use that process. A label
without a dot is not automatically an exported symbol or an entry point.

## Keep one question in mind

For every line, ask: **is this naming something, allocating bytes, operating on
values, accessing memory, changing execution, or configuring the CPU?**

Those categories explain most of the apparent randomness. The remaining details
come from the exact instruction forms supported by x86 and the conventions
chosen by BIOS or our routines.
