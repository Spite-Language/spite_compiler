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
    high_intermediary_representation       every reached function built (building only builds)
    proofs                                 the proofs, in their order (below), the rules of
                                           validators/abstract_syntax_tree that need the built program among them
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
| proofs (on the low representation) | `LowProof` | `proved(LowIntermediaryRepresentation.LoweredProgram)` |
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

A proof whose facts exist only on the low representation (after inlining, say) is a `LowProof`, declared in
`proofs/proofs.spite` and kept in its own folder of `proofs/` like every proof, but registered among the low passes,
right before the pass that reads its facts, through `LowOptimizationPasses.Proving(proof)`, whose `optimized` runs
the proof's `proved`. It records its facts on the representation (`LowFunction.placed_objects`,
`LowFunction.proven_tests`, `LoweredProgram.made_at_start`), and the pass after it only acts on what was recorded,
clearing a function's facts once it has, so no fact outlives the round that proved it.

### The proofs, in order

1. `recorded_sites`: every site the builder recorded, in the order built, judged by the proof of its kind:
   - `present_values`: a value that may be null (an unnarrowed `T?`, an unproven `[]` read) is never used where a
     value is needed;
   - `proven_checks`: no check repeats what is already proven, no `assert` or `crash` checks a plain value, and no
     copy is made only to narrow it;
   - `loop_narrowings`: an assignment inside a loop does not undo a narrowing the next pass reads;
   - `guard_asserts`: a guard `assert` answers only "nothing", and a last `if` is not a hidden guard;
   - `lost_writes`: a write to an object only this function holds is read, and a name read from a list is not
     assigned as its last mention;
   - `borrowed_items`: a borrowed item is not kept, listed, returned, renamed or read past a resize, and is lent
     only to a program function by name (it records each lent call for `lent_parameters`);
   - `parallel_reach`: a `Parallel` work or a `parallel_each_` member reaches only what it may, and no lock waits
     forever.
   A refusal the builder still makes asks this walk first, so the earliest error is the one told.
2. `rules_after_building`: the rules of `validators/abstract_syntax_tree` that need the built program.
3. `switch_cover`: every switch the builder recorded covers its cases, and a `_:` answers for something.
4. `vector_fit`: every `Vector` the builder recorded making holds a class that fits one.
5. `lent_parameters`: an item lent to a call is not kept, listed, returned or named again in the callee.
6. `compile_time_facts`: the answers to `function_waits`, `function_writes` and their kind, and the refusal of an
   answer that would decide itself.
7. `folded_crashes`: a `crash` that folds false in reached code is a compile error.
8. `every_attribute_is_read`: an attribute nothing reads is a compile error.
9. `narrowings_kept_across_calls`: a narrowed attribute is not read past a call that may assign it.
10. `registered_in_setup`: a stage's `register` is called only from its setup.
11. `ranges`: the ranges of numbers that let arithmetic and divisions go unchecked (a speed proof: it records its
   facts on the operations).
12. `setup_lists`: a list its setup fills with objects it makes holds exactly those (a speed proof: it records each
   counted loop over such a list in `HighProgram.setup_list_walks`).
13. `lists_in_the_frame`: a local list of whole numbers filled at its own level and then only counted and read by
   index holds a known count of items (a speed proof: it records the count on the list's declaration,
   `Declare.frame_items`, which a high pass carries with the statement, and the lowering lays the list out in the
   frame).

The sites `recorded_sites` judges hold what the builder resolved where it recorded them (the names in scope with
their narrowed types, the block and the statement's place in it); `PROOFS.md` lists them.

### The low proofs, where they run

1. `singletons_made_at_start`: which singletons the entry class's defaults make on every path, and which functions
   may run before they end; once, before `made_singletons`.
2. `objects_in_the_frame`: which objects a function makes never leave it, and how each is placed; before each
   `object_placement`, so after inlining and compile-time evaluation, and again after the late inlining on the
   functions it changed.
3. `bounds_proven_by_signed_tests`: which unsigned bound tests a signed test of the same values already proved, and
   which sign tests a never negative value decides; before each `proven_bounds`, in every cleaning.

### The high passes, in order

1. `setup_list_calls`: each recorded loop over a setup's list is one direct call per item, to the function of the
   item's class. This is what makes a stage's `run` direct calls in order.
2. `fused_chains`: a `List` template called on the answer of `filter_` and `map_` steps is one call to a function
   written from the last template's body, with the steps inside its loop.
3. `banded_loops`: an `each_` over a `List` whose passes write only their own item calls the template that runs it
   in bands, and a counted loop of one such call runs its count inside each band.
4. `folded_dictionaries`: a local dictionary written out and only read by keys written out is its entries.
5. `unreached_functions`: a function only the calls those passes replaced reached is dropped.
6. `untouched_attributes`: attributes nothing reads have no slot, and attributes nothing writes are rebuilt where
   they are read.
7. `layouts_by_use`: every class's layout (offsets, sizes, packing, the shared blocks of union members, the room of
   a short text), recorded as `HighProgram.layout`.
8. `call_assignments`: what each call may assign (`HighProgram.assignments`).
9. `singleton_locks`: which functions wait or can be resumed, which singletons keep a lock and which loops share
   it (`HighProgram.waits`).
10. `replaced_defaults`: the defaults a constructor replaces, trimmed for that constructor, and the slots it hands a
   fresh object (`HighProgram.trimmed_defaults`, `trimmed_keys`, `fresh_by_constructor`).
11. `taken_parameters`: the parameters a function keeps, which its callers hand over without counting
   (`HighProgram.taken_parameters`).
12. `embedded_attributes`: an object only its holder holds lives inside it (into `HighProgram.layout`).
13. `inline_items`: a list's objects sit inside its storage, or in one array per attribute (into the layout).
14. `lent_attributes`: an attribute that only holds an item of its holder's list is not counted (into the layout).

Passes 2 to 14 run only when the program is lowered (not with `--check`). Passes 7 to 14 make the decisions the
lowering reads, so the lowering only lowers; they read nothing a later high pass changes. The layout and the studies of calls
they share (`Layout`, `Assignments`, `Waits`, `SingletonForms`, `CoarseLoops`, `QuietValues`, `ListGets`) are
classes of `high_intermediary_representation/`, beside the representation they describe.

### A high pass that rewrites and builds functions

The builder builds what the program says, plain: a chain of templates builds each template, a dictionary literal
makes its dictionary. A high pass that replaces such a call with a cheaper one uses two kits at the top of
`high_optimization_passes/`:

- `Rewriting(rule)` walks every statement and value of a body and hands each value to the rule's
  `rewritten(value)`, before its parts, putting back what the rule answers; a rule that only reads answers the value.
- `FunctionBuilding(high)` builds the functions a pass asks for (`need`): the builder goes on from where it
  stopped (`Builder.continue_from`, `build_the_needed`), building them and whatever they newly reach, after every
  function built before, and the proof `ranges` records its facts on each new body, so its arithmetic is unchecked
  where a range proves it as in any other function. The new functions are then placed right after the first
  function whose call the pass replaced, where the builder would have built them, so the order of the others stays
  as it was. `replaced` records the function a call reached before a pass
  replaced it, for `unreached_functions`.

A pass that builds functions runs after the proofs that decide what a program may say, so what a program may say
never depends on these passes. Moving a function to the end of the order changes the executable, so such a pass is
proven by the same outputs on every test and the same or better times on the benchmarks it affects, not by
identical bytes.

### The low passes, in order

`low_optimization_passes/low_optimization_passes.spite` lists them, with the low proofs before the passes that
read them: the cold reports, the singletons made at the start, a first folding and threading, compile-time evaluation, inlining, compile-time evaluation again and the
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

The repositories sit side by side under one folder, as `gh repo clone` names them: this one as `spite_compiler`
and [spite_standard_library](https://github.com/Spite-Language/spite_standard_library) beside it. The source is
written to the language this compiler checks: its entry file loads `../spite_standard_library/windows`, and every
rule of [the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/README.md) holds in it.
Nothing else is needed: no link, no copied file, no older compiler. `bash scripts/bootstrap.sh --install` builds
it from a fresh clone:

1. **The seed.** Until 1.0 the seed is the last compiler this source built itself (D1071), published as a
   prerelease of this repository (`SEED_TAG` in the script, `seed-2026-10-25` now). The script uses
   `.spite/spite.exe` when it is there, and otherwise downloads the release's `spite.exe` and `spite.functions`
   into `.spite/` (`SEED=path` names another compiler instead).
2. **The seed builds the source**, about ten minutes, from the folder above this one (`spite_compiler` is the
   program's folder, so the paths written into the compiler are the same in every checkout).
3. **The compiler builds itself** until two builds write the same bytes. That fixed point is the compiler, and
   `--install` puts it in `.spite/spite.exe`. A seed built from this same source is already the fixed point, so
   its first build writes the seed's own bytes.

Day to day nobody runs the chain: from the folder above, `spite_compiler/.spite/spite.exe spite_compiler --build
--executable-path=spite_compiler/.spite/spite_next.exe` builds the next compiler from the current source, and the
next one is kept when it rebuilds itself to the same bytes. A change the current compiler cannot build (a rule
it would apply to its own source, or a library it would not recognise) is built through a compiler that accepts
both forms, and that change publishes a new seed: its fixed point as a new `seed-<date>` release, named in
`SEED_TAG` in the same commit.

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

`<stage>/<name>/<name>.spite` holds the pass's entry class, which fits the stage's type. What several low passes
and low proofs read the same way is a reader at the top of `low_optimization_passes/` (`Operands`, `Flow`,
`BlockEdges`, `SingletonTests`), not part of any one pass. A unit pass reads one
function or class at a time; a program pass needs the whole program (tree shaking, inlining across classes,
placement of objects that leave their function). Each optimisation and each proof is a pass of its own (D1086,
D1087), and nothing that builds a representation also optimises it.

## Proofs

`proofs/<what_it_proves>/<what_it_proves>.spite` proves one fact over the whole built high representation and hands
what breaks it to its validator (D1072). A proof that decides whether code is accepted runs here, after every
function is built and before any optimisation, so what a program may say never depends on how well it is optimised;
a proof that only makes code cheaper records its facts for the passes after it, where those facts exist: on the
high representation as a `Proof`, or on the low representation as a `LowProof` run among the low passes. `PROOFS.md` lists every proof, the
pass that makes it, and the ones still made inside a step or a pass, with why.

## Memory

- An object lives on the heap and is freed by reference counting (D658); where the proof `objects_in_the_frame`
  records that an object never leaves its function, the pass `object_placement` places it in registers or the frame
  instead. The lowering writes every count:
  - a value is owned (a new object, a call's answer, a text constant, a box) or borrowed (a read of a local, an
    attribute, a list slot, `this`, a singleton);
  - a place that keeps a value (a local, an attribute, a list slot, a function value's receiver, an answer) retains
    a borrowed one and releases what it held before;
  - an owned value nobody keeps (an argument, a receiver, a tested or discarded value) is released after its use;
  - a caller holds what it passes for the whole call, so a function counts only the parameters it assigns again
    (and every parameter of a step of a `Concurrent` work); the caller counts an argument or a receiver read from
    a place the call may assign, and lets it go after the call (`high_intermediary_representation/assignments.spite`,
    recorded by the high pass `call_assignments`, answers what a call may assign, following every call to the end);
  - every block releases its locals when it ends or returns; a local declared from an attribute or a list slot
    that nothing after it in its block can write holds it uncounted;
  - `_release` frees an object whose count reaches zero through its class's `_free_<class>`: `drop()` first, then
    a list's items, the attributes that hold objects, and a buffer's bytes.
- A `Buffer`'s room is sized by the compiler (D659): a buffer proven never to grow keeps its bytes inside the
  value that holds it, exactly `size` of them; every other buffer keeps a heap block that grows.
- A class whose only memory is a room of at most 8 bytes, and nothing else, is a number: its value travels in a
  register (`Integer`, `Boolean`, ...), and its room is materialised in the frame when its bytes are read.
