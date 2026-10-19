# drop_unreachable_functions

The second optimisation pass, and the one that decides what is in the program at all.

## The shape of a pass

A pass is a namespace holding one class `Pass(ir)`, taking the representation before and answering a
transformed one. The order of the passes is written in `spite_compiler.spite`, not in the folder names.

## What this pass does

It starts from what the program can reach: the class of its entry file, its attributes' initial values,
and everything those call. Every function nothing reaches is dropped from the representation.

## Why it belongs here and not later

A class that nothing reaches is not a class that costs nothing: it has an entry in the instances
registry, its attributes are built at start up, and its reflection table is emitted. Dropping it is the
difference between a program that links what it uses and one that links what it was written with.

## What it does not do

It does not decide reachability by itself. Reachability is an answer of `name_resolution`: a call through
reflection, a template, or a `switch` over a value only naming some of a union's members all reach more
than a direct call can show. This pass asks name resolution what reaches what, and drops what the answer
says is unreachable.

Dropping a function that a `Parallel` or a `Concurrent` starts later is never done: reachability has to
count those before this pass runs.
