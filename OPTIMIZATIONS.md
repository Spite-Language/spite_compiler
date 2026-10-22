# Optimisations

What this compiler does to a program to make it faster or smaller, worked out while compiling. None of them
changes what a program prints, answers or crashes with: only its time and its memory. A program that does not
need one carries nothing of it. The language's optimisations are specified in
`../SpiteLanguage/docs/optimizations.md`; this page is how this compiler builds them, and the specification a port
to another backend rebuilds from.

They run in this order on the low representation, then in the x64 generator:

1. [inlining](#small-leaf-functions-are-inlined) (`low_optimization_passes/inlining`), over the whole program;
2. per function: [constant folding](#maths-on-constants-is-worked-out-while-compiling) (`constant_folding`),
   [jump threading](#jumps-to-jumps-go-straight-to-the-end) (`jump_threading`),
   [copy propagation](#a-copy-of-a-value-that-never-changes-is-the-value) (`copy_propagation`),
   [dead code](#a-value-nobody-reads-is-not-computed) (`dead_code`),
   [copy coalescing](#a-value-computed-only-to-be-copied-is-computed-in-place) (`copy_coalescing`), and dead code
   again;
3. in `generators/windows_x64`: [block layout](#blocks-are-laid-out-along-the-likely-path),
   [register allocation](#values-live-in-registers) (`allocation.spite`), and instruction selection: the
   [immediates and compares](#constants-are-immediates-and-a-compare-is-the-branch),
   [addressing modes](#an-address-sum-is-the-addressing-mode),
   [division by a constant](#dividing-by-a-constant-is-a-multiplication), the
   [arithmetic checks](#arithmetic-checks-cost-one-jump-on-the-hot-path).

A function that waits (a resumable function, whose values live in a heap frame across a suspension) is left as
the lowering wrote it by every pass, and its values stay in its frame: the frame is sized from its registers
before these passes run, and a value must be in the frame when the function resumes.

## Small leaf functions are inlined

A call to a function that calls nothing, waits for nothing and holds at most 24 instructions (an accessor, a
list's `get_at` and `set_at`, a tiny helper) is replaced by a copy of the function's body. Its parameters become
the caller's argument registers when the body never writes them, and a copy otherwise; its answers are copied
into the call's answer registers; its blocks are added at the end of the caller and the call becomes a jump into
them.

It applies when the callee calls nothing (no `Call`, foreign call, allocation, free, thread or library call), has
a place, takes and answers no decimal in a register, and the caller is not resumable, is under 4000
instructions and has inlined fewer than 64 calls.

What a user can observe: nothing in a program's output. A crash in inlined arithmetic names the function it was
written in (each copied instruction keeps its owner); a native fault in inlined code reports the inlined
function's place, because each copied block carries that place and the place table gets an entry where the code
changes place. The executable holds the callee's body once per call site, and the callee itself too.

```spite
func Lists() {
    var marks = List<Integer>()
    marks.append(0)
    marks[0] = 1
}
```

`marks[0] = 1` is `set_at`'s bounds check and store, written in `Lists` with no call.

## Maths on constants is worked out while compiling

An arithmetic instruction or a comparison whose two operands are constants (a register written once, by a
constant) becomes a constant; a branch on a constant becomes a jump; a block nothing reaches is emptied.

It applies to `+`, `-` (operands below 2^62), `*` (below 2^31), `/` and `%` (by a divisor that is neither 0 nor
-1), and the bit operations, signed and unsigned, when the exact answer fits the instruction's width. When it does
not fit, the instruction is kept, so the program still halts at run time with the same report.

## Jumps to jumps go straight to the end

A jump or branch to a block that only jumps on goes to where that block jumps (through at most 16 such blocks),
and a branch whose two targets are the same block is a jump.

## A copy of a value that never changes is the value

A copy `t = s`, where `t` is written only by that copy and `s` is a parameter never written or a register written
once earlier in the same block (with no read of `t` in between), is removed by reading `s` wherever `t` is read.

## A value nobody reads is not computed

A constant, copy, comparison, unchecked arithmetic, decimal arithmetic or address whose answer no instruction
reads is removed, repeatedly until none is left. Checked arithmetic, division, loads, stores and calls are never
removed: each of them can halt the program or change memory.

## A value computed only to be copied is computed in place

`t = a + b` followed in the same block by `x = t`, where `t` is written and read only there and `x` is neither
read nor written in between, becomes `x = a + b`. This is what turns `index = index + 1` into one `add`.

## Blocks are laid out along the likely path

The generator writes a function's blocks in the order of their likely path rather than in the order the lowering
made them: after a block comes the block it jumps to, or the true side of its branch, and the false side is written
once the path that went the other way ends. A loop's exit comes after its body, and the body of an inlined call
right after its call. A jump to the block written next costs nothing, and a branch whose true side comes next is
inverted.

## Values live in registers

Every value of a function that does not wait lives in a machine register when one is free, and in its frame slot
otherwise. Liveness is found over the blocks (a value live into a block is live at the end of every block that
leads there, up to the blocks that write it), and each value lives in one interval, from its first point to its
last in the layout order; a linear scan gives each interval a register.

- The registers given are the seven the Windows x64 calling convention keeps across calls (`rbx`, `rsi`, `rdi`,
  `r12` to `r15`), saved in the frame by a function that uses them and restored at each return, and `r10` for a
  value whose interval holds no call nor any instruction that may call (an allocation, a checked or dividing
  arithmetic, whose crash report calls the console). `rax`, `rcx`, `rdx`, `r8`, `r9` and `r11` stay the scratch
  registers instructions work in.
- When no register is free, the value whose uses weigh least is spilled: each use or write weighs 8 to the power of
  how many loops hold it (at most 4).
- A spilled value lives in its frame slot for its whole life.

What a user can observe: nothing but time; a crash report reads its numbers from wherever the values live.

## Constants are immediates, and a compare is the branch

A register written once by a constant (and that is not a parameter) is never written: each use is the constant
itself, as an immediate operand (`add r, 7`, `cmp r, 300000000`, `mov dword [r + 4], 1`) or loaded into the
register that needs it. A comparison read only by the branch right after it is no value at all: the compare sets
the flags and the branch jumps on them; a branch on a comparison made just before it (with only plain copies in
between) also jumps on the flags. A comparison with zero is a `test`.

## An address sum is the addressing mode

A load or store whose address is a sum written only for it in the same block (`base + constant`,
`base + index`, or `base + index * 1, 2, 4 or 8` with the product written only for the sum) uses the x64
addressing mode instead: `movsxd r, dword [base + index*4 + 16]`, and the sum and the product are not computed.

## Dividing by a constant is a multiplication

A division or remainder by a constant that is neither 0 nor -1 drops the checks for both, which cannot fail. By a
power of two up to 2^30 it is a shift (signed: with the rounding toward zero that `/` has) or a mask; signed, by any
other divisor from 3 to 2^31 - 1, it is a multiplication by a magic number worked out while compiling, a shift and a
sign correction. A multiplication by a power of two that is not checked is a shift.

```spite
func Sums(): Long {
    var total: Long = 0
    var index: Long = 0
    while index < 1000 {
        total = total + index % 7
        index = index + 1
    }
    return total
}
```

`index % 7` is no `idiv`: a multiplication, two shifts, two additions and a subtraction.

## Arithmetic checks cost one jump on the hot path

Checked `+`, `-` and `*` jump on the overflow (or carry, unsigned) flag to the code that writes the report, which
is written after the function's blocks, out of the path that runs. A 64-bit operation works in its target's
register directly, undoing itself in the report's path when it overwrote an operand the report prints; a 32-bit one
works in 32 bits and its overflow flag is the check. A division's zero check jumps out the same way.
