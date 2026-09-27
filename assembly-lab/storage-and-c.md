# Storage: hardware → assembly → C

The hardware gives us registers and addressable bytes. C gives us named, typed
objects and operations on them. Assembly makes the storage decisions explicit.

Examples here use 16-bit NASM with DS=0 and data below address 0x10000, as in our
initial boot code. C snippets describe meaning; they are not literal compiled
translations or a hosted C program that accesses real-mode memory. `uint8_t`
and `uint16_t` denote unsigned 8-bit and 16-bit integer types.

## 1. A variable: storage we choose to interpret as a value

Hardware: two adjacent RAM bytes can hold a 16-bit number.

Assembly:

```asm
count: dw 7
```

This names an address `count` and emits two bytes initially representing 7.
x86 stores the lower byte first:

```text
Address       Stored byte
count         0x07
count + 1     0x00
```

A corresponding C object is:

```c
uint16_t count = 7;
```

To change that stored value:

```asm
mov word [count], 9
```

C meaning:

```c
count = 9;
```

The label is not the variable's value. It identifies where the value lives.
The `dw` declaration emits initial bytes while assembling; it is not a runtime
assignment instruction. If execution falls into those bytes, the CPU tries to
decode them as instructions, so data must be kept out of the execution path.

C variables do not always require RAM: a compiler may keep one in a register,
replace it with a constant, or remove it if it has no observable effect.

## 2. A pointer: a value used to locate other storage

Suppose `count` is located at `0x8100`:

```asm
mov si, count
mov ax, [si]
```

Hardware state:

```text
SI = 0x8100 ───────► RAM at 0x8100: 07 00
AX = 7              after the second instruction
```

The first instruction copies an address. The second follows that address.
C expresses these as:

```c
uint16_t *p = &count;  // & obtains the object's address
uint16_t value = *p;  // * accesses the object through the pointer
```

In assembly, `SI` does not carry a “pointer to uint16_t” type. We choose a
16-bit load by using AX. A load into AL would read only one byte:

```asm
mov al, [si]
```

C pointer types tell the compiler how much data an access uses and how far
pointer arithmetic advances. Assembly requires you to express those choices.
Real-mode SI alone is an offset; DS supplies the segment. This is why the
assembly/C pointer analogy needs an explicit addressing assumption.

## 3. An array: adjacent elements plus an address calculation

Hardware sees a sequence of bytes:

```asm
values: dw 10, 20, 30
```

C meaning:

```c
uint16_t values[3] = {10, 20, 30};
```

Each element occupies two bytes:

```text
values + 0 → element 0 → 10
values + 2 → element 1 → 20
values + 4 → element 2 → 30
```

So C's `values[2]` corresponds to this load:

```asm
mov ax, [values + 4]
```

For an index supplied at runtime in BX:

```asm
shl bx, 1                  ; multiply BX by two for these small indices
mov ax, [values + bx]
```

`shl` shifts bits left; shifting once inserts a zero at the low end. For our
indices 0, 1, and 2, this converts an element index into a byte displacement.
It modifies BX, so preserve the original index if it is still needed.

The address rule is:

```text
element address = array beginning + index × bytes per element
```

There is no bounds check in these instructions. A bad index accesses a different
location. Ordinary C array indexing does not promise a runtime bounds check
either; out-of-bounds use is not a valid way to access a C object.

## 4. A string: a byte array with an agreed end marker

```asm
message: db 'Hi', 0
```

```text
message + 0: 0x48    'H'
message + 1: 0x69    'i'
message + 2: 0x00    end marker
```

C representation:

```c
char message[] = "Hi";
```

The zero marker lets a printing routine find the end without a separate length.
The CPU does not recognize a string type. Our loop gives these bytes that meaning.
This is exactly the convention used by `print_string` in both boot files.

## 5. Constants: three different ideas

An assembly-time number:

```asm
SECTORS equ 4
mov al, SECTORS
```

NASM uses 4 while encoding the instruction. `SECTORS` has no storage to read.
A close C analogy is:

```c
enum { SECTORS = 4 };
```

An initialized object is different:

```asm
sectors: db 4
```

Now a byte exists in the binary and, when loaded, in RAM. Code can write it.

C's `const` adds a language-level restriction:

```c
const uint8_t sectors = 4;
```

This describes an object that must not be modified through ordinary C code.
It is not the same as NASM `equ`, and it does not itself specify hardware memory
protection. A compiler and linker may put constants in read-only memory; actual
write protection depends on how the execution environment configures memory.
Our flat boot image has no C-style const enforcement for its declared bytes.

## 6. Local, global, and lifetime are separate questions

A **scope** controls where a name can be used. **Lifetime** describes how long
an object exists. **Linkage** connects names between separately compiled files.
Do not collapse all three into “global.”

In NASM:

```asm
print_string:
.next:
    ; ...
```

`.next` is a naming convenience for `print_string.next`. It does not allocate
local storage, create a stack frame, or make the location inaccessible.

In an object-file build, `global print_string` exports the symbol for a
**linker**, the program that combines separately assembled/compiled files.
That is different from simply writing a non-local label. Our `-f bin` boot files
are raw binaries and do not use this object-file linking mechanism.

A C local variable can live in a register or in stack storage established for a
function call. An assembly data label such as `boot_drive db 0` creates a fixed
location; it is not recreated each time a routine uses it.

## 7. Connect this directly to our bootloader

| Boot code | Hardware meaning | Higher-level idea |
| --- | --- | --- |
| `boot_drive db 0` | One stored byte with an address | Variable |
| `STAGE2_SECTORS equ 4` | Assembly-time number, no storage | Constant expression |
| `mov si, ...message address...` | Register receives an address | Form a pointer |
| `lodsb` | Read through DS:SI, then adjust SI | Read a byte and advance a pointer |
| `hex_digits db '0123456789ABCDEF'` | Sixteen adjacent bytes | Lookup array |
| `mov al, [si]` in `print_hex32` | Read selected lookup byte | Array element access |
| `times 24 db 0` | Twenty-four initialized bytes | Buffer |

The naming/data notation is documented in the
[NASM language reference](https://www.nasm.us/doc/nasm03.html).
For the other half of the picture, continue with
[execution and functions](control-flow-and-c.md).
