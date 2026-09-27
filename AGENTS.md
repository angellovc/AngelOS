# Project scope

Follow `LEARNING_RULES.md` for main-project lessons and implementation work.
These lesson rules do not apply to `assembly-lab/`.

## Separate assembly learning space

`assembly-lab/` is outside the main agent's working scope. During main-project
work, never read, use as context, edit, scan, index, synchronize, or draw project
requirements from that folder, including its local instructions and notes.
Exclude it from broad searches (`rg -g '!assembly-lab/**'`), code discovery,
reviews, builds, lesson planning, and progress tracking.

Only enter that folder when the user explicitly requests work on the assembly
lab itself. That is a separate learning context governed by its local
`AGENTS.md`, independent of `LEARNING_RULES.md`, the main lesson sequence, and
milestone constraints. Do not synchronize its explanations with main lessons.
Lab work may consult implementation source to explain it, but must not change
main-project files unless the user requests that separately.

This is an agent instruction, not a filesystem access restriction.

## CodeGraph

If `.codegraph/` exists at the repository root, use `codegraph_explore` or
`codegraph explore "<symbol names or question>"` before searching or reading
code to locate or understand it. Otherwise, skip CodeGraph; do not create an
index unless requested.
