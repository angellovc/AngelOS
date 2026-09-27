# boot.asm: get the next program into memory

For hardware → assembly → C examples from this file, see [the contextual mappings](code-mappings.md).

No assembly knowledge is assumed. Read straight through or jump to a question.
Source: [`boot/boot.asm`](../boot/boot.asm). Sections below follow its execution.

The useful mental model is **a sequence of uncertainties being removed**.
BIOS has started our code, but that does not mean every register contains a value
we can trust. Each initialization creates a condition the next operation needs.

```text
BIOS hands over control
  → make memory addresses predictable
  → establish a stack and forward string reads
  → remember the boot disk
  → load more code
  → transfer control to a known address
```

## 1. What is starting this program?

The **CPU** executes instructions. **RAM** holds the instructions and data currently
in use. A disk keeps bytes even when power is off.

A **bit** is a zero or one. Eight bits make a **byte**. A memory **address** is a
number identifying a byte's location. `0x` introduces hexadecimal: base 16,
using digits `0–9` and `A–F`. `0x10` means decimal 16.

**BIOS** is firmware: startup software already installed on the machine. In our
boot path, it loads the disk's first **sector** (512 bytes) into RAM at `0x7c00`,
then starts executing it. Those bytes come from `boot.asm`.

The CPU does not read this text file. **NASM**, our assembler, translates the
assembly text into machine-code bytes before the system boots.

The first sector has little space. Its main job is to load the larger second
program, `stage2.asm`, and jump to it.

## 2. How to read the notation

For a visual explanation of the register names and their overlapping parts,
see [Registers](registers.md).

A **register** is a small storage location inside the CPU. These names identify
registers, not variables we invented:

| Name | Meaning in this program |
| --- | --- |
| `AX`, `BX`, `CX`, `DX` | 16-bit working registers |
| `AH` / `AL` | Upper / lower 8 bits of `AX` |
| `BH` / `BL`, `CH` / `CL`, `DH` / `DL` | Corresponding halves of `BX`, `CX`, `DX` |
| `SI`, `DI` | Registers often used for memory positions |
| `CS`, `DS`, `ES`, `SS` | Segment registers: part of a memory address |
| `IP` | Position of the next instruction within the code segment |
| `SP` | Position of the top of the stack, explained below |

```asm
mov bx, 0x8000
```

`mov destination, source` copies a value: now `BX = 0x8000`.
Square brackets mean **access memory at this address**:

```asm
mov dl, [0x7c00 + (boot_drive - $$)]
```

This reads a byte from RAM into `DL`. Without brackets, it would refer to the
address value itself. NASM calculates the arithmetic before execution.

A name followed by `:`, such as `start:`, is a **label**: a name for a position in
the program. It does not execute anything. A label starting with `.` belongs to
the preceding ordinary label. Text after `;` is a comment for humans.

## 3. Tell NASM how to assemble the file

```asm
bits 16
org 0x7c00
```

These are **directives**, instructions to NASM, not to the CPU.

- `bits 16`: encode instructions with 16-bit defaults.
- `org 0x7c00`: calculate addresses assuming the binary begins at `0x7c00`.

`org` does not load the program. BIOS performs the load.
`bits 16` does not switch CPU modes. BIOS enters our code in **real mode**, the
initial operating mode used here.

In real mode, a `segment:offset` pair identifies a physical memory address:

```text
address = segment × 16 + offset
0000:7c00 → 0 × 16 + 0x7c00 → 0x7c00
07c0:0000 → 0x07c0 × 16 + 0 → 0x7c00
```

Two different pairs name the same byte. Knowing where BIOS put the code does
not tell us what every segment register contains. Our code chooses zero for
its data and stack segments so their offsets directly identify low-memory bytes.

Suppose a message starts 200 bytes into the file. Its address is
`0x7c00 + 200 = 0x7cc8`. `org` lets NASM calculate that address; it cannot make
`DS` point to the right segment. That still requires a CPU instruction.

## 4. Establish known registers and a stack

```asm
cli
xor ax, ax
mov ds, ax
mov es, ax
mov ss, ax
mov sp, 0x7c00
cld
sti
```

An **interrupt** temporarily redirects execution to a handler. Hardware can
request interrupts, for example when a timer fires. `cli` blocks ordinary
maskable hardware interrupts while we configure the stack; `sti` enables them.
It does not block every possible processor event.

`xor ax, ax` sets `AX` to zero: XOR produces zero for each pair of identical bits.
The next three instructions copy zero into `DS`, `ES`, and `SS`. We use `AX`
because x86 cannot encode a direct `mov ds, 0` instruction.

The **stack** is RAM used for temporary saved values and return addresses.
`SS:SP` identifies its top. Here it starts at `0000:7c00`; putting a 16-bit value
on it decreases `SP` by two and writes below that address. It grows toward lower
addresses, away from the boot code.

The CPU also stores **flags**, individual bits describing results or controlling
behavior. `cld` clears the Direction Flag so the byte-reading instruction used
later advances through memory instead of moving backward.

### Why DS and ES both need initialization

`lodsb`, the instruction that reads a message byte, uses `DS:SI` automatically.
Suppose `SI = 0x7cc8` but BIOS left `DS = 0x1234`:

```text
0x1234 × 16 + 0x7cc8 = 0x1a008    ← a completely different byte
```

With `DS = 0`, that same `SI` reads the intended byte at `0x7cc8`.
Setting `SI` alone would not be enough.

`ES` serves another dependency. The BIOS disk service writes to `ES:BX`.
We will put `0x8000` in `BX`; setting `ES = 0` now makes the destination exactly
`0x8000`. These assignments prepare different later operations.

### Why put the stack immediately before the code?

With `SS = 0` and `SP = 0x7c00`, a 16-bit `push` behaves like:

```text
SP becomes 0x7bfe
write the saved value into bytes 0x7bfe and 0x7bff
```

The memory layout explains the choice:

```text
lower addresses
    ...
0x7bfe   first two-byte stack item; further items go toward lower addresses
0x7c00   initial SP; first byte of boot code
    ...  512 bytes of boot code and data
0x7dff   last byte of boot sector
0x7e00   beginning of a 512-byte gap
0x8000   first byte of stage 2
    ...  2048 bytes
0x87ff   last byte of stage 2
higher addresses
```

Ordinary stack use grows away from our code. There is no automatic boundary
check here; it is suitable for this tiny loader, not unlimited nesting of calls.

### Why clear the Direction Flag explicitly?

Imagine the message bytes are `H`, `i`, and zero, in consecutive locations.
After reading `H`, we need the next read to reach `i`.

```text
DF = 0 → SI increases → move to the next character
DF = 1 → SI decreases → read the byte before the message
```

`cld` makes the first behavior certain. Initialization means establishing what
our code depends on, rather than hoping firmware left it that way.

## 5. Remember the disk and print a message

```asm
mov [0x7c00 + (boot_drive - $$)], dl
mov si, 0x7c00 + (loading_message - $$)
call print_string
```

BIOS supplied the boot device's number in `DL`. We save it in a byte named
`boot_drive` so we can identify that device when reading more sectors.

`$$` means the beginning of this assembly section. Thus `loading_message - $$`
is the message's position relative to the file's beginning. Adding `0x7c00`
gives its RAM address. `SI` receives that address, not the message's contents.

For a label 430 bytes into the file, the calculation is `0x7c00 + 430`.
The general idea is **load address + position within the file**. With this file's
`org`, `[boot_drive]` would normally express the same address. The longer form
makes the load-address reasoning visible.

Saving `DL` keeps the original disk identity available even when subsequent
code uses registers for other jobs. Otherwise a later disk request could use
the wrong device number.

`call print_string` saves the address of the following instruction on the stack,
then jumps to `print_string`. Its `ret` instruction takes that saved address off
the stack and resumes the caller.

## 6. How print_string works

A **string** is a sequence of character bytes. These strings end with a zero byte,
which marks the end and is not printed.

```asm
lodsb
test al, al
jz .done
```

`lodsb` reads the byte at `DS:SI` into `AL`, then increments `SI` because we used
`cld`. `test al, al` checks whether the byte is zero without changing it.
It sets the **Zero Flag** if so; `jz` jumps when that flag is set.

For a nonzero byte:

```asm
mov ah, 0x0e
mov bx, 0x0007
int 0x10
out 0xe9, al
jmp .print_character
```

`int 0x10` deliberately calls a BIOS video service. Its input registers form a
request: `AH = 0x0e` selects character output, `AL` holds the character, and
`BX = 0x0007` selects display page zero and color seven where applicable.

`out` sends a byte to an **I/O port**, a numbered device interface separate from
RAM addresses. Our QEMU emulator exposes port `0xe9` as debug text output.
This is why text can also appear in the host terminal.

`jmp` always jumps. Here it repeats the reading step. At the zero terminator,
`.done` executes `ret`, returning to the instruction after the original `call`.

## 7. Ask BIOS to load stage 2

The code fills registers, then executes `int 0x13`, the BIOS disk-service entry.
These values are that service's calling convention: agreed locations for inputs.

| Register | Value | Request meaning |
| --- | --- | --- |
| `AH` | `0x02` | Read disk sectors |
| `AL` | `4` | Read four sectors: 2048 bytes |
| `CH` | `0` | Cylinder zero |
| `CL` | `2` | Start at sector two |
| `DH` | `0` | Head zero |
| `DL` | Saved device number | Read the disk we booted from |
| `ES:BX` | `0000:8000` | Write the bytes into RAM at `0x8000` |

Cylinder, head, and sector are coordinates in this older BIOS disk interface.
For this image, `0, 0, 2` selects the sector immediately after our boot sector.
The Makefile places the stage 2 binary there.

```asm
jc disk_error
jmp 0x0000:STAGE2_LOAD_ADDRESS
```

BIOS sets the **Carry Flag** on a read error. `jc` jumps if that flag is set.
The error path prints a message and stops.

Otherwise the **far jump** sets both `CS` and `IP`, making execution continue at
`0000:8000`. Loading bytes did not execute them; this jump starts stage 2.
Unlike `call`, this jump does not save a return address.

## 8. Data and padding at the end

```asm
STAGE2_LOAD_ADDRESS equ 0x8000
STAGE2_SECTORS      equ 4
boot_drive         db 0
```

`equ` names a constant; it reserves no memory. `db` emits bytes into the binary.
`boot_drive db 0` creates one byte initially containing zero, later overwritten.
Message declarations emit character bytes, then `13, 10` for carriage return
and line feed, then the zero terminator.

```asm
times 510 - ($ - $$) db 0
dw 0xaa55
```

`$` is the current assembly position, so `$ - $$` is the bytes emitted so far.
`times` repeats the zero-byte declaration until the file contains 510 bytes.
`dw` emits a 16-bit value, adding two bytes.

x86 stores the least significant byte first: `0xaa55` becomes `55 aa`.
That is the BIOS boot signature. The complete file is exactly 512 bytes.

On failure, `cli`, `hlt`, and a backward `jmp` form a stopping loop: disable
ordinary hardware interrupts, halt execution, and halt again if execution resumes.

**Check:** Why must we both read stage 2 and jump to it?
Reading puts bytes in RAM; jumping tells the CPU to execute them.

You can now follow stage 1 from BIOS entry to stage 2. It has not discovered
available RAM or changed processor mode; those jobs belong to stage 2.
