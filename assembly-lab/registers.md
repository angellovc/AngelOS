# Registers: the CPU state we manage directly

The bootloader works by putting values where the CPU or BIOS expects them.
Registers are the first part of that idea to understand.

## What is a register?

A **register** is a small storage location inside the CPU. **RAM** is the memory
outside that register state, where our program's bytes and data live.

```text
CPU
┌───────────────────────────────────┐
│ Working values: AX BX CX DX        │
│ Positions:      SI DI SP BP        │
│ Segments:       CS DS ES SS FS GS  │
│ Next instruction: IP              │
│ Result/control bits: FLAGS        │
│                                   │
│ Hardware executing instructions   │
└──────────────────┬────────────────┘
                   │ reads and writes
                   ▼
                  RAM
```

These are names for CPU state, not variables our program creates in RAM.

```asm
mov ax, 5
```

means “copy the number 5 into AX.” Afterward:

```text
AX = 5
RAM has not been written by this instruction.
```

The instruction's name is short for “move,” but its source is not erased.

## Why do the names matter?

`AX`, `BX`, `CX`, and `DX` can hold ordinary working values. Some instructions
and BIOS services also assign particular jobs to particular registers.

For example, nothing prevents this:

```asm
mov bx, 5
add bx, 10
```

`BX` becomes 15. But when we request a BIOS disk read, `BX` supplies part of
the destination address because that is how the BIOS interface was defined.

Separate these two ideas: **what a register can store** and **what the current
instruction or service expects it to mean**.

## AX, AH, and AL are overlapping views

A **bit** stores zero or one. Eight bits make a **byte**. `AX` holds 16 bits,
which we can also access as two eight-bit pieces:

```text
                AX — 16 bits
        ┌─────────────┬─────────────┐
        │ AH — upper 8│ AL — lower 8│
        └─────────────┴─────────────┘
```

The prefix `0x` means hexadecimal, a number system using `0–9` and `A–F`.
Each hexadecimal digit represents four bits. Thus four digits fill `AX`:

```text
AX = 0x1234
     ┌──────┬──────┐
     │  12  │  34  │
     │  AH  │  AL  │
     └──────┴──────┘
```

`AH` and `AL` are not separate copies. Changing either changes that part of `AX`:

```asm
mov ax, 0x1234
mov al, 0x56
```

```text
Initially: AX = 0x1234, AH = 0x12, AL = 0x34
Afterward: AX = 0x1256, AH = 0x12, AL = 0x56
```

Likewise, `xor ax, ax` zeros the whole 16-bit register, so both halves become zero.
This matters whenever one instruction sets a whole register and another depends
on a value previously stored in just one half.

## Why BIOS uses AH and AL separately

BIOS is firmware: software available before our operating system exists.
Its video service expects a request in specific registers:

```asm
mov ah, 0x0e
mov al, 'A'
mov bx, 0x0007
int 0x10
```

`'A'` becomes character code `0x41`. Just before the BIOS call:

```text
                  AX = 0x0e41
          ┌──────────────┬──────────────┐
          │ AH = 0x0e    │ AL = 0x41    │
          │ operation   │ character A  │
          └──────────────┴──────────────┘
```

`int 0x10` transfers control to the BIOS video service. BIOS reads `AH` to choose
character output and `AL` to find the character. `BX` supplies page zero and
color seven where that service uses color.

The CPU does not permanently consider `AH` an “operation register.” This meaning
belongs to the BIOS service we are calling. Another service can interpret it
differently.

## BX, CX, and DX have the same kind of halves

| Whole register: 16 bits | Upper eight bits | Lower eight bits |
| --- | --- | --- |
| `AX` | `AH` | `AL` |
| `BX` | `BH` | `BL` |
| `CX` | `CH` | `CL` |
| `DX` | `DH` | `DL` |

For example, BIOS supplies the boot-device number in `DL`:

```text
                  DX
          ┌──────────────┬──────────────┐
          │ DH = unknown │ DL = 0x80    │
          └──────────────┴──────────────┘
```

Traditionally `0x80` identifies the first hard disk. We only need the lower
byte; knowing `DL` does not mean we know all of `DX`.

Our bootloader saves that byte in RAM:

```asm
mov [0x7c00 + (boot_drive - $$)], dl
```

The brackets mean “write to memory at the calculated address.” The expression
locates `boot_drive` inside the loaded program. Saving the value there preserves
it while registers are reused for other operations.

## SI and DI: numbers used as positions

`SI` and `DI` are 16-bit registers often used to locate data. Their contents
are still just numbers; the instruction determines how those numbers are used.

```asm
mov si, 0x8000
```

sets `SI` to a number. It does not read the byte at that address.

```asm
mov al, [si]
```

reads a byte from memory using `DS:SI`. That introduces another dependency:
we must know what `DS` contains before we know which byte is being read.

## Segment registers: the other part of the address

At startup our CPU uses **real mode**, where an address is formed as:

```text
physical address = segment × 16 + offset
```

Common pairs in this loader are:

| Pair | What uses it here |
| --- | --- |
| `CS:IP` | Fetching the next instruction |
| `DS:SI` | Reading message bytes |
| `ES:BX` | BIOS disk-read destination |
| `SS:SP` | Stack storage |

If `DS = 0` and `SI = 0x8000`, the address is `0x8000`.
If `DS = 0x1000`, the same `SI` instead identifies `0x18000`.
That is why the loader initializes segments instead of just setting offsets.

## SP: why calls need memory too

The **stack** is a region of RAM used to save values temporarily. `SP` tracks
its top, while `SS` supplies its segment.

With `SS = 0` and `SP = 0x7c00`:

```asm
push ax
```

has this effect:

```text
SP: 0x7c00 → 0x7bfe
RAM at 0x7bfe and 0x7bff receives AX's two bytes.
AX itself is unchanged.
```

`pop ax` reads the saved value back and increases `SP` by two.
A normal 16-bit near `call` also uses the stack: it saves where to return.
`ret` retrieves that address. Without a valid stack, calling a printing routine
can corrupt memory before anything appears on screen.

## IP and FLAGS: where to go and what just happened

`IP` tracks the instruction position within the code segment. Instructions such
as `jmp`, `call`, and `ret` change the execution path.

`FLAGS` contains individual bits describing results or controlling behavior.
For example:

```asm
test al, al
jz .done
```

`test` leaves `AL` unchanged but sets the **Zero Flag** if it is zero.
`jz` consults that flag to decide whether to jump.

Two other flags explain the loader's initialization:

```text
Interrupt Flag: CLI clears it; STI sets it.
  Controls ordinary maskable hardware interrupts.

Direction Flag: CLD clears it.
  Makes LODSB advance SI after reading a byte.
```

These are dependencies too: a jump depends on a result flag, and a string read
can depend on a direction flag.

## EAX: the larger view used by stage 2

Stage 2 also uses 32-bit registers. `EAX` contains `AX` as its lower 16 bits:

```text
                     EAX — 32 bits
┌──────────────────────┬───────────┬───────────┐
│ upper 16 bits        │ AH        │ AL        │
└──────────────────────┴───────────┴───────────┘
                       └──── AX ──────────────┘
```

For example:

```text
EAX = 0x12345678
 AX =     0x5678
 AH =       0x56
 AL =       0x78
```

Writing `AX` changes those lower 16 bits and preserves the upper 16 bits of
`EAX`. `EBX`, `ECX`, and `EDX` overlap `BX`, `CX`, and `DX` similarly;
`ESI`, `EDI`, `ESP`, and `EBP` are the corresponding larger registers for
`SI`, `DI`, `SP`, and `BP`.

Using a 32-bit register does not itself switch the processor out of real mode.
On the processor this project targets, NASM can encode a 32-bit operation inside
16-bit code. Stage 2's actual mode switch changes a control register and loads
a new code segment, as explained in [the stage 2 guide](03-stage2-asm.md).
