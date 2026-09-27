# Hardware → assembly → C

Assembly becomes easier when you stop treating register names as interchangeable
variables. The CPU offers particular storage locations and particular operations.
Assembly names those operations. C builds abstractions from them.

```text
Hardware: storage, arithmetic, address calculation, instruction sequencing
    ↓ named by
Assembly: registers, instructions, memory operands, labels
    ↓ organized into
C: variables, pointers, arrays, expressions, functions
```

The CPU does not have a “C array” component. An array works because software
places values next to each other and computes their addresses.

This guide uses our x86 CPU and NASM syntax. Other CPUs have different instruction
sets; other assemblers can spell the same x86 operations differently.

## 1. Start with the machine, not the keywords

```text
CPU
┌───────────────────────────────────────────┐
│ General registers: AX BX CX DX SI DI ...   │
│   hold working values                     │
│                                           │
│ Arithmetic/logic machinery                │
│   adds, compares, combines bits            │
│                                           │
│ Address state: CS DS ES SS ...             │
│   helps determine memory locations         │
│                                           │
│ Instruction position and flags             │
│   determine what executes next             │
└─────────────────────┬─────────────────────┘
                      │ accesses
                      ▼
RAM: numbered bytes containing instructions and data
```

This is a model of visible CPU behavior, not a diagram of its exact internal
wiring. A processor's **instruction set** specifies which operations software
may request. The assembler must select a supported machine-code encoding for
every instruction you write.

C's compiler can turn one expression into several operations. NASM generally
expects you to choose the individual instructions yourself.

## 2. Syntax versus semantics

**Syntax** is how you write something. **Semantics** is what it means.

```asm
mov ax, 5
```

Syntax: instruction name, destination operand, comma, source operand.
An **operand** is a value or location an instruction acts on.

Semantics: put the 16-bit value 5 in AX. The source is not erased.

For common instructions here, operands fall into three useful categories:

| Category | Example | Meaning |
| --- | --- | --- |
| Register | `ax` | CPU storage |
| Immediate | `5` | A value encoded in the instruction |
| Memory | `[count]` | Storage at a calculated address |

Compare:

```asm
mov ax, count       ; AX receives the address named count
mov ax, [count]     ; AX receives the 16-bit value stored there
```

If `count` is at address `0x8100` and contains 7, the first puts `0x8100` into
AX; the second puts 7 into AX. Brackets change the operation from using an
address value to accessing memory there.

## 3. Why xor ax, bx works but xor ax, ds does not

The instruction is spelled **`xor`**, not `xord`. Its size comes from its operands:
`xor ax, bx` works on 16 bits; `xor eax, ebx` works on 32 bits.

XOR compares corresponding bits: different bits produce 1; equal bits produce 0.

```text
AX:     0101   (5)
BX:     0011   (3)
XOR:    0110   (6)
```

For the register form, x86 XOR accepts **general-purpose registers**.
`AX` and `BX` belong to that class. `DS` is a **segment register** used in
memory addressing. There is no `XOR general-register, segment-register` encoding.

NASM therefore cannot translate `xor ax, ds` into an x86 instruction.
This is an instruction-set restriction, not an arbitrary NASM punctuation rule.

If you really wanted to combine AX with the visible value in DS, use two
supported operations:

```asm
mov bx, ds          ; copy DS's value into a general-purpose register
xor ax, bx          ; combine the two general-purpose values
```

This changes BX too. It leaves DS unchanged.

The general principle is **each instruction has specific accepted operand forms**.
Register size alone does not decide compatibility.

For example, MOV has special forms for segment-register transfers, while XOR
does not. Conversely, MOV does not allow an immediate value directly into DS:

```asm
mov ax, 0           ; supported: immediate → general-purpose register
mov ds, ax          ; supported: general-purpose register → segment register
```

This explains our real boot code:

```asm
xor ax, ax          ; produce zero in ordinary working storage
mov ds, ax          ; transfer that zero into address-related state
```

`xor ax, ax` and `mov ax, 0` both zero AX, but their complete effects differ:
XOR also changes arithmetic flags; MOV does not.

Some instruction-set choices are historical design decisions. A hardware model
organizes them; it cannot make every x86 exception logically inevitable.

## 4. An instruction has a contract, like a function signature

Imagine XOR documented with these conceptual signatures for 16-bit values:

```text
xor(general_register_16 destination, general_register_16 source)
xor(general_register_16 destination, memory_16 source)
xor(memory_16 destination, general_register_16 source)
xor(general_register_16_or_memory_16 destination, immediate source)
```

These are descriptions, not actual NASM syntax. They explain why these differ:

| NASM example | Result | Reason |
| --- | --- | --- |
| `xor ax, bx` | Valid | Two general registers of the same width |
| `xor ax, ds` | Invalid | Segment register is not an accepted XOR operand |
| `xor ax, bl` | Invalid | 16-bit destination and 8-bit source do not match |
| `xor ax, [si]` | Valid | AX determines a 16-bit memory read |
| `xor word [si], 1` | Valid | Explicit 16-bit memory operation |
| `xor [si], [di]` | Invalid | XOR has no form with two memory operands |
| `mov ds, ax` | Valid | MOV has a segment-register form |
| `mov ds, 0` | Invalid | MOV has no immediate-to-segment form |

Memory contains bytes, not a declaration NASM automatically uses as a C type.
`word` says to access two bytes; `byte` means one and `dword` means four.

```asm
mov [si], 1         ; no width written explicitly; avoid relying on inference
mov byte [si], 1    ; one byte
mov word [si], 1    ; two bytes
```

The installed NASM 3.01 accepts the unsized `mov [si], 1` and encodes a byte
write. Do not infer that it knows the type of the object pointed to by SI.
Write `byte` or `word` to make the intended access unambiguous to the reader.

## 5. Addresses also have supported forms

Brackets do not permit every arithmetic expression using every register.
Our boot code uses 16-bit addressing, whose ordinary register-based forms use
BX, BP, SI, or DI, individually or in certain pairs such as BX+SI and BP+DI.

```asm
mov al, [si]        ; valid 16-bit addressing form
mov al, [bx + si]   ; valid
mov al, [ax]        ; no 16-bit addressing encoding using AX this way
```

This does not mean AX cannot contain an address number. It means that particular
memory instruction cannot use AX as its address register in that addressing form.
Copying AX to SI would let us access the address using `[si]`.

Memory access also uses a segment. With the bootloader's `DS = 0`, `[si]` reads
physical address `0 × 16 + SI`. BP-based addressing normally uses SS instead.
The examples in the next guide use DS=0 and low-memory addresses to keep this
extra part of the calculation visible but simple.

## 6. Use a repeatable reading method

For any assembly line, ask:

1. Is this a CPU instruction, a label, or a request to NASM?
2. What are its explicit operands: registers, immediates, or memory?
3. What widths and register classes does this instruction accept?
4. Does it use implicit state, such as DS, the stack, or flags?
5. What changes after execution, and what remains unchanged?

For example, `lodsb` has no written operands, but reads memory at DS:SI into AL
and adjusts SI according to the Direction Flag. An empty operand list does not
mean an instruction has no inputs.

You can now map higher-level ideas without treating them as magic:
[Variables, pointers, arrays, constants, and scope](storage-and-c.md), then
[Functions, branches, and the entry point](control-flow-and-c.md).

For NASM's source-line and operand notation, see the
[official language reference](https://www.nasm.us/doc/nasm03.html).
The acceptance examples above can be reproduced with the lab's
[operand check script](examples/check_operands.py).
