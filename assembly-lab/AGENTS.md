# Free exploration of assembly

This folder is the user's independent space for understanding assembly and the
machine. It is not a course milestone or part of the main lesson sequence.
`../LEARNING_RULES.md` does not apply here. Follow the user's curiosity: jump
between concepts, revisit basics, explore alternatives, or go deeper as useful.
No mandatory prerequisites, exercises, lesson format, or end-of-lesson summary.

## Hardware → assembly → C, in this project

Use actual snippets from `boot/boot.asm` and `boot/stage2.asm` as the primary
teaching examples. For each concept, explain the hardware state/problem, the
actual assembly that manipulates it, and a C representation of the behavior.
C is a bridge, not assumed prior knowledge. Explain its relevant syntax too.
Distinguish conceptual C from runnable code and actual compiler output. Make
mode, segment, width, and calling-convention assumptions explicit where needed.
For rejected operands, explain supported instruction forms and register classes;
do not present x86 as a uniform language in which every operation accepts every
register. Keep hardware configuration distinct from portable C constructs.

## Teaching approach

Use the user's provided bootloader explanation as the style reference:

- Assume no prior assembly knowledge. Explain names and notation as they arise.
- Start with a mental model: the loader progressively removes uncertainty about
  the CPU and hardware so later instructions can rely on known conditions.
- Explain why the instruction exists before describing its mechanics. Show what
  could go wrong without it, then what becomes reliable after it executes.
- Use small actual code snippets, concrete numbers, address calculations,
  before/after register values, and simple text diagrams when helpful.
- Show overlapping register views visually (EAX/AX/AH/AL), and trace how a
  write changes the shared value. Separate hardware capabilities from meanings
  assigned by a BIOS interface. Use CPU-versus-RAM diagrams when helpful.
- Connect decisions across the file: DS=0 supports string reads, ES=0 supports
  disk reads, and a valid stack supports calls and BIOS services.
- Explain odd-looking expressions and common idioms instead of merely naming
  them. Distinguish assembler-time decisions from CPU actions at runtime.
- Be direct and concise within each explanation. Do not compress away the
  reasoning just to keep the entire topic short. Depth follows the question.
- Do not assume knowledge of C, operating-system terminology, or prior lessons.
- Preserve technical accuracy; use the example's teaching approach without
  copying oversimplifications or errors.

Read implementation files when needed to explain them accurately. Keep notes
and experiments here; changing the main implementation requires a separate
user request. The main project must never depend on this folder.
