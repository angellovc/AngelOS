# Understand our bootloader: hardware → assembly → C

Start with [the code mappings](code-mappings.md). Every example comes from
`boot/boot.asm` or `boot/stage2.asm`: first understand the hardware need, then
read the actual assembly, then express its behavior in C.

This is a free exploration space. It follows your questions, independently of
the main project's lesson rules or milestone order.

## Follow a question

- [What do variables, pointers, arrays, constants, functions, and globals look like in our code?](code-mappings.md)
- [Why are some instruction operands allowed and others rejected?](hardware-assembly-c.md)
- [Where do values live?](storage-and-c.md)
- [How do labels, calls, returns, conditions, and loops work?](control-flow-and-c.md)
- [How do AX, AH, AL, and EAX overlap?](registers.md)

## Follow execution

- [boot.asm, from BIOS entry to the stage 2 jump](02-boot-asm.md)
- [stage2.asm, from arrival to 32-bit execution](03-stage2-asm.md)

C examples explain behavior and data layout. They are not a replacement
implementation or a claim about the exact assembly a C compiler will generate.
