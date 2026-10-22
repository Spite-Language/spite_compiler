# Optimisations

What the compiler does on its own to make a program faster or smaller, worked out while compiling. Each section
says what the optimisation does, when it applies, when it does not, what a program can observe of it, and shows a
small program. None of them changes what a program prints, returns or crashes with: only its time and its memory.

## A function does not count its own parameters

A function's parameters are held by its caller for the whole call, so the function does not count them: it reads
them as they are and lets nothing go when it returns. The caller holds what it passes: a name of its own (a local
or a parameter), `this`, a singleton, or an object it has just made and lets go after the call.

**When it applies:** to every parameter the function never assigns. A function that writes `parameter = other`
counts that parameter, since the assignment lets go of what it held. A function that runs as a step of a
`Concurrent` work (one that can wait) counts its parameters too, since its frame outlives the call that started it.

**What the caller counts instead:** an argument or a receiver read from a place the call may assign (an attribute
the callee, or anything it calls, writes; a list slot; a back reference; the answer of a wait) is counted by the
caller before the call and let go after it, so the call cannot free it under the callee
([An attribute a call cannot assign is passed without counting](#an-attribute-a-call-cannot-assign-is-passed-without-counting)).

**What a program can observe:** nothing but time. `drop()` runs at the same moment as before, since the count a
call made was never the last one.

```spite
func Naive() {
    var rows = List<Integer>()
    rows.append(3)
    var total = first_of(rows, 0)
}

func first_of(rows: List<Integer>, at: Integer): Integer {
    return second_of(rows, at)
}

func second_of(rows: List<Integer>, at: Integer): Integer {
    var found = rows[at]
    crash found
    return found
}
```

Neither `first_of` nor `second_of` counts `rows`: `Naive` holds it in a local for both calls.

## An attribute a call cannot assign is passed without counting

An argument or a receiver that is an attribute, or a path of attributes (`settings.limits`), is passed as it is
when nothing the call can run assigns any attribute along the path: the object that holds it holds it for the whole
call. The compiler works out, for every function, the attributes it assigns and the functions it calls, and follows
the calls to the end, so the question is answered for everything the call can reach.

**When it does not apply:** when the call, or anything it reaches, assigns an attribute on the path, assigns one
of that name through a shape, calls a function value whose function may (any function the program takes as a value
counts), runs a `drop()` that may (a `drop()` can run wherever a count is let go, so every `drop()` counts), waits
(`Program.sleep`, a join, a blocking read, where other work runs), or hands a function to C that may call it back.
Then the caller counts the argument for the call. A path through a back reference is always counted.

**What a program can observe:** nothing but time.

```spite
var readings = List<Integer>()
var settings = Settings()

func measure(at: Integer): Integer {
    return reading_at(readings, at) + offset_of(settings.limits)
}
```

`reading_at` and `offset_of` assign neither `readings`, `settings` nor `Settings.limits`, so both are passed
uncounted. Ten million calls of `measure` went from 0.35 s to 0.22 s.

## A name holding an item or an attribute is not counted

`var held = this.part`, or a list's own `var held = _read_value(index)`, does not count `held` when nothing after
it in its block can write the slot it came from: no assignment of an attribute on its path and no call that may
write one, no write into a list of that class (`_write_value`, `_forget_value`) and no call that may make one. The
name is then read as it is and let go of nothing when its block ends. This is what makes a list's templates
(`contains`, `index_of`, `join`, `copy`, and the others handed a function that cannot write the list) read their
items without counting them.

**When it does not apply:** when the name is assigned again anywhere in the function, when what it came from is
itself a name that is assigned again, when anything after it in the block may write the slot (by the same rules as
the [attribute passed to a call](#an-attribute-a-call-cannot-assign-is-passed-without-counting)), or in a step of a
`Concurrent` work. Then the name counts what it holds.

**What a program can observe:** nothing but time.

```spite
func contains(value: $element_type): Boolean {
    var index = 0
    while index < _length {
        var held = _read_value(index)
        if held == value {
            return true
        }
        index = index + 1
    }
    return false
}
```

## Storing an object into a list counts it only when it changes the slot

Writing an object into a list's slot compares it with what the slot holds. When it is the same object, nothing is
counted and nothing is written; otherwise the new object is counted and the old one let go, as before.

**When it applies:** to every write of an object, a union, a shape or a function value into a `List`, a
`Vector` or an `Items` slot.

**What a program can observe:** nothing but time.

```spite
var held = names[at]
crash held
names[at] = held
```

Ten million such write-backs went from 0.36 s to 0.23 s.

## Defaults the constructor replaces are never made

`var values = List<Integer>()` written beside a constructor that sets `values = List<Integer>()` itself made the
default list and freed it at once. A constructor that assigns an attribute before anything can read it makes its
objects with a copy of the class's defaults that leaves that attribute out, so the default is never made.

**When it applies:** to an attribute the constructor assigns in its own body, outside any `if` or loop, before
any statement that reads it or that names `this` other than to assign or read an attribute (a call on `this`, or
`this` passed on). The default left out must be quiet: a constant, a text, or an object whose making assigns only
its own attributes from quiet values, calls nothing the compiler cannot see the end of, cannot stop the program
(a check on its arguments that the constants given to it decide is followed), and whose class has no `drop()`. A
class whose defaults name `this`, or read another attribute, is made from all of its defaults.

**What a program can observe:** fewer allocations. A default left out is not made, so nothing it would have made
is ever counted, dropped or freed.

```spite
var values = List<Integer>()
var label = "none"

func Holder(start: Integer) {
    values = List<Integer>()
    values.append(start)
    label = "made"
}
```

`Holder(start)` makes neither the default list nor the default text. Three million holders went from 3.1 s to
1.5 s.


## Arithmetic a range proves is not checked

A `+`, `-` or `*` on whole numbers halts when its answer does not fit its type. Where the compiler proves while
compiling that it always fits, the check is left out and the operation is one machine instruction. The proof is a
range for each operand (`high_intermediary_representation/building/ranges.spite`), the rule of
`../SpiteLanguage/specs/values_and_types.md#a-range-proves-a-check-unneeded`:

- a literal is its own range; a local or a parameter of a whole-number type of at most four bytes has its type's
  range until a `var` or an assignment gives it its value's; a `Long` has no range until one is given to it;
- `count()` of a library `List`, `Dictionary`, `Vector` or `Items`, and `length()` of a `String`, run from 0 to
  2147483647; `x % n`, `x / n`, `minimum`, `maximum`, `clamp`, `to_long` and `to_integer` are bound by their
  operands;
- a comparison narrows the local it compares inside a `while` or an `if` whose condition says so, on each side of an
  `and`, after an `assert` or a `crash` of it, and after an `if` that leaves; `counter + c < bound` narrows `counter`
  by `bound - c` too;
- the two branches of an `if` join, and before a `while` every local its body assigns takes its type's range, except
  a counter only ever stepped up by constants: it keeps the floor it entered with and, under `counter < bound` with
  no step in a nested loop, at most the bound's largest value plus its steps.

```
func total(values: List<Integer>): Long {
    var sum: Long = 0
    var index = 0
    while index < values.count() {
        sum = sum + values[index]
        index = index + 1
    }
    return sum
}
```

`index + 1` is written unchecked: `index` runs from 0 to 2147483646 under the loop's condition. `sum + values[index]`
keeps its check, since `sum` is a `Long` that grows every pass.

When it does not apply: an operand that is an attribute, a list item or a call's answer has its type's range, so an
operation on two of them keeps its check. A `--repl`, `--repl-port` or `--hot-reload` build proves no ranges, since
code may run between two steps. What a user can observe: `--optimization-report` lists every check kept, under
"Overflow checks kept", with the ranges that did not prove it.

## A proven read tests only its bounds

`values[index]` where a bound proves the read (`while index < values.count()`) is a call to the list's `get_at`, which
answers a `T?`, and a test that halts when the answer is missing. For a library `List` whose items are not `T?`
(numbers, `Boolean`, objects), the compiler writes the read in place instead: one unsigned comparison of the index
with the list's length, which halts the same way when the index is below 0 or the list changed, one load of the
item, and for an object the count the call's answer would have taken. `count()` of a library `List`, `Vector` or
`Items`, and `length()` of a `String`, is one load of its length.

```
func rises(values: List<Integer>, threshold: Integer): Integer {
    var count = 0
    var index = 1
    while index < values.count() {
        if values[index] - values[index - 1] > threshold {
            count = count + 1
        }
        index = index + 1
    }
    return count
}
```

The loop calls nothing: `values.count()` is a load, and each read is a comparison and a load.

When it does not apply: a list of `T?` items, of unions or of function values still calls `get_at`; a `List` whose `get_at` or `count` a program replaces by reopening the class calls the
replacement. What a user can observe: nothing but the time; the message of a read outside its list is the same.

## Text joined in one piece

`"{first} meets {second} at the gate."` is one join, not a chain of pairs. The compiler makes the text once and
appends every piece to it in order: a written piece's bytes go straight in, with no text made for them, and a hole's
text is appended and let go. A chain of pairs would make a whole new text at every piece and copy everything joined
so far into it.

```
func greeting(first: String, second: String): String {
    return "{first} meets {second} at the gate."
}
```

The pieces are worked out left to right as written, so anything a hole calls runs in the order the source reads in.

When it does not apply: a join written as calls (`first.sum(second)`) is a call, and a program that replaces
`String.sum` by reopening `String` keeps calling its own. What a user can observe: fewer texts made, under
`--debug-memory`.

## A number joined into text is written in place

`"line {index} of {round};"` reads as turning each number into a text and joining the pieces. Inside a join, an
`Integer` or a `Long` piece is written as digits straight into the text being joined: the compiler counts the
digits, makes room for them and writes them from the last, so no text is made for the number.

```
func label(index: Integer, round: Integer): String {
    return "line {index} of {round};"
}
```

The digits are the ones the library's `to_string()` writes: a `-` for a number below 0, and `0` for zero. When it
does not apply: a number that is the whole text (`"{index}"`), a number of another type, and a program that
replaces `Integer.to_string()` or `Long.to_string()` by reopening the class, which keeps calling its own. What a
user can observe: fewer texts made, under `--debug-memory`.

## Maths on constants is worked out while compiling

A `+`, `-` or `*` on whole numbers whose operands' ranges are each one value, read from constants, locals and other
such operations, is worked out while compiling and written as its answer. A local given a constant is a constant
where it is read, until something assigns it again (the ranges of
[Arithmetic a range proves is not checked](#arithmetic-a-range-proves-is-not-checked)).

```
func area(): Integer {
    var width = 12
    var height = width * 3
    return width * height + 4
}
```

`area` returns 436 with no arithmetic left. When it does not apply: an answer that does not fit its type keeps the
operation, which halts as it would have; a division, a call and a decimal are not worked out. What a user can
observe: nothing but the time.

## What runs after lowering

These run in this order on the low representation, then in the x64 generator:

1. [inlining](#small-leaf-functions-are-inlined) (`low_optimization_passes/inlining`), over the whole program;
2. per function: [constant folding](#maths-left-on-constants-after-lowering-is-worked-out-too) (`constant_folding`),
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

## Maths left on constants after lowering is worked out too

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
