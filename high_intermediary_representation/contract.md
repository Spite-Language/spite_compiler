# high_intermediary_representation

The program as values and control flow, once every name answers and every type is known.

## What it takes and answers

It takes the resolved classes and answers a `HighProgram`: every class the program can reach, with its
attributes and functions, every function's body as a `HighBlock` of `HighStatement`s over `HighValue`s.

## Why a second shape

The abstract syntax tree answers where a name was written. The high representation answers what the
program *is*: a value is an `Integer`, a `String` or a reference to a class; a call names the function it
reaches. Optimisation passes read the high representation because a question like "is this call ever
reached" or "does this addition always overflow" has no answer on the syntax tree.

## What is built

A subset, enough to compile a program of whole numbers that calls its own functions, uses `while` and
returns a value. Classes hold `Integer` attributes. Nothing else is lowered yet: `String`, lists,
references, unions, reflection and concurrency are all still to come, and each needs its own value kinds
here first.

The `Builder` is the step from the syntax tree to this representation. It takes a class's `SourceFile` and
the substitution of the instance it belongs to, and answers a `HighClass`:

- every function with a body becomes a `HighFunction` with its parameters, their types *after* the
  substitution, its result type after the substitution, and its body lowered;
- a statement it cannot lower is counted, not dropped silently. `Builder.skipped_count` says how many.

The types it lowers are the whole numbers: a literal, a name, an addition or a multiplication, and a call.
Everything else is counted as skipped until it is written.

## The shapes

- `HighProgram` — the classes.
- `HighClass` — a name, its attributes and its functions.
- `HighFunction` — a name, its parameters, their types, its result type and its body.
- `HighBlock` — a list of statements.
- `HighStatement` — a union of `Declare`, `Assign`, `While`, `Call`, `Return`.
- `HighValue` — a union of `Number`, `Name`, `Operation`, `Answer` (a call that answers a value).
