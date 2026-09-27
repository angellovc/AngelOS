# Read instructions as changes in state

Prerequisite: a **register** is a small storage location inside the CPU.
`AX` is a 16-bit register. A **segment register**, such as `DS`, helps the CPU
locate memory.

**Problem:** BIOS starts our boot code, but we cannot assume `DS` has the value
our code needs. From `boot/boot.asm`, under `start`:

```asm
xor ax, ax
mov ds, ax
```

`xor` compares corresponding bits: equal bits produce zero. A value compared
with itself therefore produces all zeros. After the first instruction, `AX = 0`.

`mov destination, source` copies a value. After the second instruction, `DS = 0`;
`AX` is still zero. We use `AX` because x86 cannot directly encode `mov ds, 0`.

In the initial CPU mode, called **real mode**, a memory address is calculated as
`segment × 16 + offset`. With `DS = 0`, an offset of `0x7c00` refers to physical
address `0x7c00`. The prefix `0x` means hexadecimal, a base-16 way to write numbers.

**Check:** Does `mov ds, ax` erase `AX`? No. It copies the value.

You can now trace these two instructions. This does not yet explain the other
segment registers or the stack; those are separate next steps.
