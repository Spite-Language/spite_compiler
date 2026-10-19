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

## The owner of a call

A call names the function it reaches, and the class that owns it. The owner is what tells two functions of
one name apart: `Counter.reset` and `Timer.reset` are two functions, and a call that says only "reset" says
neither.

The `Builder` fills the owner in with what the language lets it tell:

- a call with no receiver reaches a function of the class the file declares, so the owner is that class;
- a call of a class's name makes an object, so the owner is that class;
- a call on a class's name reaches a function of that class, so the owner is that class;
- a call on an instance reaches a function of the receiver's class, and the receiver's class is not known
  yet, so the owner is empty.

An empty owner is not a guess and not a name: it says the compiler does not know yet. The owner is what a
pass needs to tell two functions of one name apart, and a pass that is given an empty owner falls back to
the name alone.

## The shapes

- `HighProgram` — the classes.
- `HighClass` — a name, its attributes and its functions.
- `HighFunction` — a name, its parameters, their types, its result type and its body.
- `HighBlock` — a list of statements.
- `HighStatement` — a union of `Declare`, `Assign`, `While`, `Call`, `Return`.
- `HighValue` — a union of `Number`, `Name`, `Operation`, `Answer` (a call that answers a value).

A `Call` and an `Answer` carry the name of the function they reach and the class that owns it.
