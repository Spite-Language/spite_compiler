# Architecture

## Four kinds of folder

| Kind | Takes | Answers | Writes errors | Writes text |
|---|---|---|---|---|
| step | the representation before it | a new representation | no | no |
| pass | a representation | the same kind, transformed | no | no |
| validator | one representation | the problems in it | only it | no |
| printer | one representation | text | no | only it |

A representation is data only: no function on it writes text or decides an error.

## The order

Every stage folder has one entry class named for the folder (`proofs/proofs.spite` is `Proofs.Proofs`), whose
`run` does the stage. `spite_compiler.spite` only makes each stage and calls its `run`, in this order:

    command_line                           the settings, the program they name, the last build removed
    mapping                                the program's folders; then validators/mapping
    symbols                                the entry class and every class it names, a class at a time as names ask
                                           for it, each read through abstract_syntax_tree's `run` (lexed, parsed,
                                           formatted by printers/formatted_source and read again); then
                                           validators/abstract_syntax_tree
    name_resolution                        the model; then validators/name_resolution
    high_intermediary_representation       every reached function built (building only builds); then the rules
                                           of validators/abstract_syntax_tree that need the built program
    proofs                                 the proofs, in their order (below)
    high_optimization_passes               the high passes, in their order (below)
    low_intermediary_representation        the lowering; then validators/low_intermediary_representation
    low_optimization_passes                the low passes, in their order (below)
    outputs                                the texts (high and low representations, generated classes, the
                                           optimisation report, the crash map), then generators/windows_x64's `run`
                                           and the executable with its function map

The outputs stage runs the generator after writing the texts, so a refusal while emitting still leaves the
representations to read. With `--check` the low stages and the generator do not run, and the outputs stage writes
only what the high representation gives. No stage reaches back into an earlier one.

## A stage's passes

A stage with passes (proofs, high_optimization_passes, low_optimization_passes) declares a `type` for them in its
entry class, with the one function every pass has, so a class that does not fit is a compile error where it is
registered:

| Stage | Type | The function |
|---|---|---|
| proofs | `Proof` | `check(HighIntermediaryRepresentation.HighProgram)` |
| high_optimization_passes | `HighOptimizationPass` | `optimized(HighIntermediaryRepresentation.HighProgram)` |
| low_optimization_passes | `LowOptimizationPass` | `optimized(LowIntermediaryRepresentation.LoweredProgram)` |

The entry class registers its passes in its own setup, in order, with `register(pass)`, each made there and never
changed; `run` runs them in that order. Since the setup only makes passes and registers them, `proofs/setup_lists`
knows the list and `high_optimization_passes/setup_list_calls` writes `run` as one direct call per pass, so a stage
costs nothing over a hand-written sequence. `register` crashes once `run` has started. Each pass folder's entry class is
named for the folder and is what the stage registers; a low pass whose work is per function keeps that work in its
`Pass(function)` and its entry class runs it over every selected function (`LoweredProgram.is_selected`: every
function, except between the late inlining and `EveryFunction`, where only the functions the late inlining changed).
A pass that needs more than the representation reads it from the representation: the high passes and proofs read
the builder's context through `HighProgram.context` (the model, the symbol table, the flags, the facts asked).

### The proofs, in order

1. `present_values`: a value that may be null (an unnarrowed `T?`, an unproven `[]` read) is never used where a
   value is needed.
2. `proven_checks`: no check repeats what is already proven, no `assert` or `crash` checks a plain value, and no
   copy is made only to narrow it.
3. `loop_narrowings`: an assignment inside a loop does not undo a narrowing the next pass reads.
4. `guard_asserts`: a guard `assert` answers only "nothing", and a last `if` is not a hidden guard.
5. `lost_writes`: a write to an object only this function holds is read, and a name read from a list is not
   assigned as its last mention.
6. `borrowed_items`: a borrowed item is not kept, listed, returned, renamed or read past a resize, and is lent only
   to a program function by name (it records each lent call for `lent_parameters`).
7. `parallel_reach`: a `Parallel` work or a `parallel_each_` member reaches only what it may, and no lock waits
   forever.
8. `switch_cover`: every switch the builder recorded covers its cases, and a `_:` answers for something.
9. `vector_fit`: every `Vector` the builder recorded making holds a class that fits one.
10. `lent_parameters`: an item lent to a call is not kept, listed, returned or named again in the callee.
11. `compile_time_facts`: the answers to `function_waits`, `function_writes` and their kind, and the refusal of an
   answer that would decide itself.
12. `folded_crashes`: a `crash` that folds false in reached code is a compile error.
13. `every_attribute_is_read`: an attribute nothing reads is a compile error.
14. `narrowings_kept_across_calls`: a narrowed attribute is not read past a call that may assign it.
15. `registered_in_setup`: a stage's `register` is called only from its setup.
16. `ranges`: the ranges of numbers that let arithmetic and divisions go unchecked (a speed proof: it records its
   facts on the operations).
17. `setup_lists`: a list its setup fills with objects it makes holds exactly those (a speed proof: it records each
   counted loop over such a list in `HighProgram.setup_list_walks`).

The first seven judge the sites the builder recorded while building, each with what it resolved there (the names in
scope with their narrowed types, the block and the statement's place in it); `PROOFS.md` lists the sites.

### The high passes, in order

1. `setup_list_calls`: each recorded loop over a setup's list is one direct call per item, to the function of the
   item's class. This is what makes a stage's `run` direct calls in order.
2. `untouched_attributes`: attributes nothing reads have no slot, and attributes nothing writes are rebuilt where
   they are read.

### The low passes, in order

`low_optimization_passes/low_optimization_passes.spite` lists them: the cold reports, the singletons made at the
start, a first folding and threading, compile-time evaluation, inlining, compile-time evaluation again and the
specialised calls; then the placement (known headers, object placement) and the cleaning (twenty-five function
passes from settling the singletons to the last live values); then direct calls and the late inlining, the placement
and the cleaning again on the functions it changed; then, on every function again, releasing in place, vector loops,
and the last shaping of blocks, live values and copy coalescing.

## What the compiler writes itself

`Concurrent`, `Parallel` and their scheduler are not Spite classes: the lowering writes them as low functions
(`low_intermediary_representation/lowering/machine_writing.spite` is the kit). `scheduling.spite` writes the
scheduler (`_scheduler_*`: the frames each thread steps, joins, sleeps, the poll limit and the circle of joins),
`work_writing.spite` the functions of each handle and the table of calls in a row, and `debug_guard_writing.spite`
the guard that cuts a `to_debug()` cycle. A handle is a block the compiler lays out (`Spite.Work_of_<T>`: the frame
it waits for, its answer and its presence); the resolver makes its class model with no source, and its functions
have no body (`is_written_by_the_compiler`), so a call to one is an ordinary call. Only `to_debug` of a handle and
the stand-in for a null in a shape (`Spite.Absent`) are high functions the builder writes. A program that makes no
handle writes none of it, and a program that never starts calls in a row has no table.

The rest is Spite code the compiler holds as text (`symbols/machinery_text.spite`: the fault and crash reports
`Spite.Fault`, the assert ring `Spite.Asserts`, the deep copy table `Spite.CopyTable`; and, only in a `--repl` build,
`high_intermediary_representation/building/prompt_text.spite`: `Spite.Prompt` and `Spite.PromptPath`). The first
time a program names one, the symbol table adds it as a generated class under the program's
`.spite/build/spite/`, with the library's rights; a program that never needs one reads none of it. No folder holds
them, so nothing can load them, and a program that names one of them, or any `Spite.Internal` name, is refused.

Beside every executable the compiler writes `<name>.functions`: one line per function of the code, its start and
end as offsets from the start of the code section and its key (`# spite functions 1`, then `start\tend\tkey` in
hexadecimal). Nothing of it is in the executable. When a native fault halts the program, the fault report reads that
file and adds `spite.function\t<key>` for the function that faulted and one `spite.caller\t<key>` for each frame it
walks up through the frame pointers; without the file it prints only the fault line.

## How the compiler is built

The source is written to the language this compiler checks: its entry file loads `.spite/library/windows`, and
every rule of [the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/README.md) holds in it. The old compiler (0.0.6) cannot build it, so a build from
nothing is a chain, and `scripts/bootstrap.sh` runs all of it:

1. **The seed.** Commit `47767ec` is the last source the old compiler builds. The old compiler builds it into
   `.spite/bootstrap/spite_seed.exe`. Its executables reserve 1 MB of stack, too little for this compiler to
   resolve its own source, so the script sets the seed's `SizeOfStackReserve` (offset 72 of the PE optional header)
   to 256 MB. Only the seed is ever built by the old compiler.
2. **The seed builds the source**, about five minutes (`--check` about three). `.spite/library` must be a junction
   to [spite_standard_library](https://github.com/Spite-Language/spite_standard_library), since the entry file's `load` reaches it through `.spite/spite_compiler`.
3. **The compiler builds itself** until two builds write the same bytes, about seventy seconds each; the compiler
   the seed writes already rebuilds itself byte for byte. That fixed point is the compiler, and
   `bash scripts/bootstrap.sh --install` puts it in `.spite/spite.exe`.

Day to day nobody runs the chain: `.spite/spite.exe` builds the next compiler from the current source
(`.spite/spite.exe .spite/spite_compiler --build --executable-path=.spite/spite_next.exe`), and the next one is
kept when it rebuilds itself to the same bytes. A change the current compiler cannot build is built by the
compiler of the commit before it.

## The first error stops the run

A step holds no error text. When it finds something to judge (a folder name, a token it cannot read, a parsed
file), it hands it to the validator of that rule at once. The validator lets it pass, or reports the problem
and ends the compile through `Validators.Failure`. Nothing runs after the first error.

## Validators

`validators/<level>/<rule>/validator.spite` holds a class `Validator()` whose `check(...)` takes the data the rule
needs. The folder is named after the rule, and the validator holds every word of its error.

- A rule lives at the earliest level that has the facts it needs, and runs as soon as those facts exist: a file's
  rules run right after the file is parsed, before the next file is read.
- A validator never changes what it is given.
- A file's rules read one `AbstractSyntaxTree.Walk.Walk`: every block, statement and expression of the file with
  its line and function, made once. A message quotes code through `printers/spite`.
- A rule that needs the whole program runs once the program is complete; a rule about one class runs per class,
  and a reload runs only those.
- The message says what the old compiler's message says (the old compiler's diagnostic programs), in this compiler's
  words, and a `conformance` test of [spite_spec](https://github.com/Spite-Language/spite_spec) pins it.

## Printers

`printers/<what>/printer.spite` holds a class `Printer(input)` answering `text(): String`. A printer never writes
a file and never changes its input.

- `printers/spite` prints a tree as Spite, to quote code in a message; `--final-classes` uses it on a merged class.
- `printers/formatted_source` is the formatter: it prints a file's tokens and comments in the one layout (D901),
  and `formatting/formatter.spite` checks the result (`validators/abstract_syntax_tree/formatting`), writes it
  back and prints `formatted <path>`.
- `printers/diagnostics`, `printers/high_intermediary_representation`, `printers/low_intermediary_representation`,
  `printers/optimization_report`, `printers/machine_code`. `--high-ir` and `--low-ir` write the two
  representations next to the executable, as `<program>.high_ir.txt` and `<program>.low_ir.txt`.

A text that is an identity (a type's key, an instance's name) is not printing: it belongs to the step that owns it.

## Passes

`<stage>/<name>/<name>.spite` holds the pass's entry class, which fits the stage's type. A unit pass reads one
function or class at a time; a program pass needs the whole program (tree shaking, inlining across classes,
placement of objects that leave their function). Each optimisation and each proof is a pass of its own (D1086,
D1087), and nothing that builds a representation also optimises it.

## Proofs

`proofs/<what_it_proves>/<what_it_proves>.spite` proves one fact over the whole built high representation and hands
what breaks it to its validator (D1072). A proof that decides whether code is accepted runs here, after every
function is built and before any optimisation, so what a program may say never depends on how well it is optimised;
a proof that only makes code cheaper records its facts for the passes after it. `PROOFS.md` lists every proof, the
pass that makes it, and the ones still made inside a step or a pass, with why.

## Memory

- An object lives on the heap and is freed by reference counting (D658); a pass that proves an object never leaves
  its function places it in the frame instead. The lowering writes every count:
  - a value is owned (a new object, a call's answer, a text constant, a box) or borrowed (a read of a local, an
    attribute, a list slot, `this`, a singleton);
  - a place that keeps a value (a local, an attribute, a list slot, a function value's receiver, an answer) retains
    a borrowed one and releases what it held before;
  - an owned value nobody keeps (an argument, a receiver, a tested or discarded value) is released after its use;
  - a caller holds what it passes for the whole call, so a function counts only the parameters it assigns again
    (and every parameter of a step of a `Concurrent` work); the caller counts an argument or a receiver read from
    a place the call may assign, and lets it go after the call (`lowering/assignments.spite` answers what a call
    may assign, following every call to the end);
  - every block releases its locals when it ends or returns; a local declared from an attribute or a list slot
    that nothing after it in its block can write holds it uncounted;
  - `_release` frees an object whose count reaches zero through its class's `_free_<class>`: `drop()` first, then
    a list's items, the attributes that hold objects, and a buffer's bytes.
- A `Buffer`'s room is sized by the compiler (D659): a buffer proven never to grow keeps its bytes inside the
  value that holds it, exactly `size` of them; every other buffer keeps a heap block that grows.
- A class whose only memory is a room of at most 8 bytes, and nothing else, is a number: its value travels in a
  register (`Integer`, `Boolean`, ...), and its room is materialised in the frame when its bytes are read.
