# fold_constants

The first optimisation pass, and the shape every pass has.

## The shape of a pass

A pass is a namespace holding one class `Pass(ir)`. It takes the representation the step before it
answered, and answers a transformed one. It never reaches back into an earlier step and never writes to
the representation it was given: it answers a new one.

So a pass is written as:

    func FoldConstants(starting_program: HighProgram) {
        program = starting_program
    }

    func transformed(): HighProgram {
        ...
    }

## What this pass does

It walks every value and replaces an operation whose two sides are both whole numbers with the number the
operation makes. It does this bottom up, so `2 * 3 + 1` folds to `7` in one run.

It answers the same numbers the machine would compute: a division or a remainder by zero is not folded,
because the machine halts there, and folding it to a number would hide the halt.

## Why this pass first

It needs nothing from the high representation but the shape of a value, so it is the cheapest pass that
can be written and the easiest to check. `drop_unreachable_functions` is the other one written first,
because between them they show both kinds: one changes values, one removes work.

## What it does not do

It does not fold a comparison of two numbers into a flag, and it does not fold a value that overflows.
Those are the two places where folding would lie, and the rule of this compiler is that nothing may fail
silently.
