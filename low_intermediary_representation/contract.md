# low_intermediary_representation

The program as a flat list of instructions over virtual registers, ready for a machine.

## What it takes and answers

It takes a high representation and answers a `LowProgram`: one `LowInstruction` list per function, a list
of `LowFrame`s telling where each virtual register lives, and the entry point.

## The change it makes

Control flow stops being a tree. A `while` becomes a test, a jump forward, a body and a jump back. Every
value becomes an instruction that leaves its answer in a virtual register. There is no nesting left, so a
low pass is a pass over a list and never has to rebuild a shape.

A virtual register is a place the machine code decides later: a stack slot, a real register, or a value
folded away entirely. Nothing above this step may assume where one lives.

## What is built

A subset: integers, addition, subtraction, multiplication, division, remainder, negation, comparisons,
`while`, calls between the program's own functions, and `return`. Enough to compile a program that
computes a whole number and answers it.

## The shapes

- `LowProgram` — the functions, in the order they are written out, and the entry.
- `LowFunction` — a name, how many slots it needs, and its instructions.
- `Instruction` — one record with a `kind`, read here as one of:

| kind | reads | means |
| --- | --- | --- |
| `number` | `first`, `text` | put a whole number into register `first` |
| `read` | `first`, `second` | read place `first` into register `second` |
| `write` | `first`, `second` | write register `second` into place `first` |
| `copy` | `first`, `second` | register `second` becomes register `first` |
| `operation` | `first`, `second`, `third`, `text` | `third = first text second` |
| `jump` | `to` | go to instruction `to` |
| `jump_if_false` | `first`, `to` | go to instruction `to` when register `first` is zero |
| `call` | `first`, `callee`, `places` | register `first` answers the call |
| `return` | `first` | answer register `first` |

`to` is an index into the function's own instruction list, not a name. The lowering records the index
when it emits, and a jump to the instruction after a jump is a real jump, so a pass that removes an
instruction has to renumber every target that lands after it. `peephole_jumps` does this in
`note_where_each_lands`: it walks the list once, recording where each instruction will land, then
retargets.

## Why one record and not a union

A union of nine classes is the shape this will end in, and `high_intermediary_representation` uses one
throughout. It is not used here because the lowering and the passes only ever build a record by calling
`InstructionBuild`, and a union member cannot be built by calling a function of the class: the old
compiler's C code emits an undeclared `__init_constructed` when two union members share a shape. Splitting
`Instruction` into a union is the first change to make when the emitter lands and starts switching on the
kind, because by then there will be enough kinds for the shared shape to be worth avoiding.
