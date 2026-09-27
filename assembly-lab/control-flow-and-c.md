# Execution: hardware → assembly → C

Storage explains where values live. Control flow explains which instruction runs
next. The CPU's instruction position changes as instructions execute; jumps and
calls deliberately redirect it.

## 1. A label does not create a function

```asm
first:
    mov ax, 5
second:
    add ax, 2
```

The labels emit no instructions. If the CPU starts at `first`, it executes both
instructions and AX becomes 7. There is no boundary at `second` that stops it.

A C-like description of that flow is:

```c
value = 5;
value += 2;
```

In our boot image, BIOS loads the first sector and transfers control to its
first byte at physical address `0x7c00`. NASM places `cli` there. The label
`start` happens to name that position; it does not cause BIOS to select it.

```text
Build places CLI first → BIOS loads those bytes → BIOS enters their address
```

Neither a label named `start` nor an exported symbol automatically makes a raw
binary's entry point. The loader and binary format determine where execution
starts. Our loader is BIOS for stage 1, and stage 1 itself for stage 2.

## 2. A function: code plus an agreement

Hardware provides `call` and `ret`. For a normal 16-bit near call in our real-mode
code, CALL saves the return instruction offset on the stack and redirects IP.
RET retrieves that saved offset.

Here is an illustrative routine, not a C compiler's calling convention:

```asm
    mov ax, 5
    call add_two
    jmp finished

add_two:
    add ax, 2
    ret

finished:
    cli
.stop:
    hlt
    jmp .stop
```

Its agreement is:

```text
Input:  AX contains the number
Output: AX contains the result, wrapping to 16 bits
Changes: AX and arithmetic flags
Needs:  a valid stack
```

C meaning:

```c
uint16_t add_two(uint16_t value) {
    return (uint16_t)(value + 2);
}
```

The C compiler chooses how to pass arguments and return values according to a
**calling convention**: an agreement about registers, stack layout, and which
values a routine must preserve. Our hand-written assembly chooses its own
convention. CALL does not automatically identify parameters or preserve AX.

Why jump to `finished` after the call? Because after returning, sequential
execution would otherwise enter `add_two` again. That second entry would have
no matching CALL; its RET would consume unrelated stack contents.

## 3. The return address is actual data

Suppose SP is `0x7c00` just before `call add_two`:

```text
CALL:
  SP becomes 0x7bfe
  save address of instruction after CALL at SS:SP
  set instruction position to add_two

RET:
  read saved instruction position at SS:SP
  SP becomes 0x7c00
  continue after CALL
```

This explains why the stack must be configured before calling print routines.
It also explains why a routine must balance its pushes and pops before RET.
If an extra value remains on the stack, RET takes that value as its destination.

A near JMP only redirects execution. It does not save a return address. Stage 1
uses a far JMP to enter stage 2, setting both the code segment and offset; stage
2 does not return to stage 1.

## 4. If statements: comparison, flags, branch

C:

```c
if (value == 0) {
    /* zero case */
} else {
    /* nonzero case */
}
```

A corresponding assembly structure, with the value in AX:

```asm
    cmp ax, 0
    je .zero
    ; nonzero case
    jmp .after
.zero:
    ; zero case
.after:
```

CMP sets result flags as though subtracting, but does not replace AX with the
subtraction result. JE checks the Zero Flag. It does not directly inspect AX.
A flag-changing instruction inserted between CMP and JE could change the decision.

Our code often uses `test ax, ax` and `jz` instead. TEST computes bitwise AND
only for flags; a value AND itself is zero exactly when that value is zero.
JE and JZ name the same condition.

Signed and unsigned comparisons use different conditions. For example, after
CMP, JB means “below” for unsigned values, while JL means “less” for signed
values. C's operand types help the compiler choose; in assembly you choose.

## 5. A loop: repeat by changing the next instruction

Our stage 2 string loop is:

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

With DS=0 and the Direction Flag cleared, its behavior is:

```text
read byte at SI into AL
increase SI by one
if byte is zero, return
otherwise print it and repeat
```

C-like meaning, where `print_character` represents our output helper:

```c
void print_string(const unsigned char *p) {
    for (;;) {
        unsigned char c = *p++;
        if (c == 0) return;
        print_character(c);
    }
}
```

The C pointer is advanced after each read. Assembly advances SI, including for
the terminating zero. The analogy explains the algorithm; the C local pointer
and assembly's caller-visible SI are not identical interfaces.

The backward JMP is not recursion. It saves no new return address. The outer
CALL's return address remains available for the eventual RET.

## 6. BIOS calls: arguments supplied to an existing interface

For a BIOS disk read, the bootloader places the operation number in AH, the
sector count in AL, the disk number in DL, and the destination in ES:BX.

This resembles passing arguments to a function, except the interface specifies
particular registers and `int 0x13` invokes it through the real-mode interrupt
mechanism. INT has its own saved state and return mechanism; it is not just an
alternate spelling of CALL.

A conceptual request is:

```text
BIOS: read four sectors from this drive into memory at 0000:8000
```

Then `jc disk_error` tests BIOS's reported failure in the Carry Flag. This is
another agreement: the service defines how arguments and results are represented.

## 7. Where the C analogy stops

Operations such as loading segment registers, disabling hardware interrupts,
writing an I/O port, and changing CR0 configure the machine itself. Standard C
has no portable expression for each of them. Kernels use assembly routines,
compiler extensions, or special built-ins to request those operations.

For these lines, the most useful question is directly about hardware:
“Which CPU state changes, and what later operation depends on it?”

Use that question while reading [boot.asm](02-boot-asm.md) and
[stage2.asm](03-stage2-asm.md). They combine familiar storage/control-flow patterns
with a smaller set of explicit machine-configuration operations.
