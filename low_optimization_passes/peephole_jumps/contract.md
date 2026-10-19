# peephole_jumps

The first low pass, and the simplest there is.

## The shape of a pass

A pass is a namespace holding one class `Pass(ir)`, taking the representation before and answering a
transformed one.

## What this pass does

It reads each instruction and the one before it, and rewrites the pair. Two rewrites are built:

- a jump whose target is a jump goes straight to where that jump goes, and
- a jump to the instruction straight after it is dropped.

## Why it is here

This is the pass that shows why the low representation is a list and not a tree. On the high
representation "a jump to a jump" is not a question anyone can ask, because there are no jumps. On the low
representation it is two instructions side by side, and the pass is a loop over the list.

## What it does not do

It never removes a jump that decides something. A conditional test whose two sides are the same
instruction is folded by `fold_away_tests` instead, because that is a question about the value, not about
the shape of the jump.

A jump chain is walked to its end before it is written, so a long chain of jumps costs the pass one pass
over the list, not one pass per jump.
