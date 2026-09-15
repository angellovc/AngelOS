# Learning operating systems by building one

We are building an **x86-64 (64-bit) operating system** from first principles.
The project begins with legacy BIOS because it exposes the early boot process in
small, visible steps. The BIOS path begins in 16-bit mode; our kernel will
eventually run in the processor's 64-bit mode.

This repository is both working software and a book. No previous operating-system
or assembly-language knowledge is assumed. New concepts are defined before they
are used, following the rules in [`LEARNING_RULES.md`](LEARNING_RULES.md).

## Lessons

0. [`00-cpu-assembly-foundations.md`](lessons/00-cpu-assembly-foundations.md) —
   How bits, the ALU, registers, memory, instructions, flags, jumps, and the stack
   work from the processor's perspective.
1. [`01-bios-boot-sector.md`](lessons/01-bios-boot-sector.md) — How BIOS finds our
   first 512 bytes, how the CPU addresses memory, and how we print text.
2. [`02-stage2-loader.md`](lessons/02-stage2-loader.md) — How stage 1 reads more
   sectors into memory and starts stage 2.
3. [`03-physical-memory-map.md`](lessons/03-physical-memory-map.md) — How stage 2
   asks BIOS which physical-address ranges are usable RAM and prints the result.
4. [`04-a20-line.md`](lessons/04-a20-line.md) — Why addresses one MiB apart can
   alias during early boot and how stage 2 verifies and enables address bit 20.

Worked lesson exercises are stored in [`exercise-results`](exercise-results/).
The [`CODE_READING_MAP.md`](CODE_READING_MAP.md) index connects every implemented
concept to its source file and stable assembly label.

## Build the current milestone

The current code includes everything implemented through Lesson 4.

```sh
make clean
make
make run
```

Use `make run-headless` to send the output to the terminal instead of opening a
QEMU display window. Press `Ctrl-C` after the messages appear.

## Long-term direction

We will continue from the bootloader to a 64-bit kernel and gradually add the
ability to run programs, protect their memory, perform multiple tasks, use
multiple processor cores, access devices, store files, and communicate over a
network. Each problem and its terminology will receive its own lesson before its
solution appears in the code.
