# high_intermediary_representation

The program as values and control flow, once every name answers and every type is known.

## What it takes and answers

It takes the `Model.ProgramModel` the name resolution answered and answers a `HighProgram` (`high_program.spite`): every
function the program reaches built as a `HighFunction` (`high_function.spite`) with a body of `Statements` over
`Values`, and what the builder recorded for the proofs.

## Why a second shape

The abstract syntax tree answers where a name was written. The high representation answers what the program *is*: a
value has a type, a call names the function it reaches. The proofs and the high passes read it because a question
like "is this call ever reached" or "may this value be null" has no answer on the syntax tree.

## The files

- `high_intermediary_representation.spite`: the entry, `HighIntermediaryRepresentation(model, resolver, flags)`; its
  `run` makes the `builder.spite` and builds.
- `builder.spite`: builds every reached function, one at a time, as names ask for them, through `building/`.
- `building`: the builder's concerns, one file each, around the `Context` it builds in (`building/context.spite`) and
  the sites it records for the proofs (`building/recorded_site.spite`).
- `statements` and `values`: the representation itself, data only, one file per kind; the unions of both are
  declared in `spite_compiler.spite`.
- `ownership`: which parameters a function keeps and how a value is used, which the lowering counts with.
- `layout.spite`, `waits.spite`, `assignments.spite`, `singleton_forms.spite`, `coarse_loops.spite`, `quiet_values.spite`,
  `list_gets.spite` and `setup_list_walk.spite`: what the high passes record on the program for the lowering.
- `presence_facts.spite` and `narrowed_read.spite`: what is proven present and what is narrowed.

## What the builder does

It only builds: a rule decides every error, so every check the builder meets is handed to the rule of
`validators/high_intermediary_representation` that owns it, with what was built; the rule decides and stops through
the layer's entry. What a program may say is decided by the proofs before any pass runs, and what is cheaper by the
passes after them; nothing that builds the representation also optimises it.

**An argument is passed by its parameter's type only.** The builder fits each argument to its parameter (made nullable,
boxed into a shape, widened, narrowed) by the two types alone, and the lowering passes the value it lowered, so the
callee is handed the same thing whether the caller's value is a local, an attribute, a list item or a call's answer.
Where the value came from decides only how it is counted (owned, borrowed or held), never what is passed.

**A crash and an assertion are one statement.** Both stop the program when their condition does not hold: a `crash` is a
guard that stops the program where a `fallback` stops the function. The builder builds both as a `Stop` statement with
the text the program prints when it stops.

**An index is a call to `get_at`.** `a[b]` is a shortcut for `a.get_at(b)`, and `a[b] = v` for `a.set_at(b, v)`; the
builder builds the call.

**The owner of a call** is the class whose function it reaches, so two functions of one name apart: a call with no
receiver reaches the class the file declares, a call of a class's name makes an object of it, and a call on an
instance reaches the class of the value the receiver holds. A receiver whose class is not known names no owner.
