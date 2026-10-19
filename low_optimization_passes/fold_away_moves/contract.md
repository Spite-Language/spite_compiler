# fold_away_moves

The second low pass, and the one that decides where a value lives.

## The shape of a pass

A pass is a namespace holding one class `Pass(ir)`, taking the representation before and answering a
transformed one.

## What this pass does

It reads each instruction and the one before it, and rewrites the pair:

- a virtual register written and then read, with nothing between, becomes the value written, and
- a virtual register read twice in a row becomes one read and a copy, so the machine loads it once.

The first rewrite is what makes a virtual register worth having: a local that is written once and read
once is never stored at all, and the frame shrinks by one slot per local like it.

## Why it belongs here and not in the high passes

Folding a move away needs to know what a register is. On the high representation a local is a name, and
two names may be the same place; only once the low representation has given each place a register can the
pass say that writing it and reading it is one value.

## What it does not do

It does not remove a write that a jump may pass over. A register written on one path and read on another
is kept, because removing it would answer a value that was never written. A register that is live across
a call is kept for the same reason: the call may write it.

The live-range half of this pass, which keeps a register only where it is read, is not built yet. What is
built is the pair above.
