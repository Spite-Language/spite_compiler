# Architecture

## Four kinds of folder

| Kind | Takes | Answers | Writes errors | Writes text |
|---|---|---|---|---|
| step | the representation before it | a new representation | no | no |
| pass | a representation | the same kind, transformed | no | no |
| validator | one representation | the problems in it | only it | no |
| printer | one representation | text | no | only it |
| fix | one representation | the same representation, changed, and a `fixed:` problem for each change | no | no |

A representation is data only: no function on it writes text or decides an error.

## The order

Every stage folder has one entry class named for the folder (`proofs/proofs.spite` is `Proofs.Proofs`), whose
`run` does the stage. `spite_compiler.spite` only makes each stage and calls its `run`, in this order:

    command_line                           the settings, the program they name, the last build removed
    mapping                                the program's folders; then validators/mapping
    symbols                                the entry class and every class it names, a class at a time as names ask
                                           for it, each read through abstract_syntax_tree's `run` (lexed, parsed,
                                           fixed by fixes/abstract_syntax_tree, written by `Fixes.Fixes` through
                                           printers/spite's Printer and read again); then
                                           validators/abstract_syntax_tree; once every class is read, fixes/symbols,
                                           then validators/mapping
    name_resolution                        the model; then validators/name_resolution
    high_intermediary_representation       every reached function built (building only builds)
    proofs                                 the proofs, in their order (below), the rules of
                                           validators/abstract_syntax_tree that need the built program among them
    fixes                                  the fixes found while or after building written, and the compile
                                           restarted on the fixed files (`Fixes.Fixes`'s `run`, below)
    high_optimization_passes               the high passes, in their order (below)
    low_intermediary_representation        the lowering; then validators/low_intermediary_representation
    low_optimization_passes                the low passes, in their order (below); then
                                           validators/low_intermediary_representation/written_functions
    outputs                                the texts (high and low representations, generated classes, the
                                           optimisation report, the crash map), then generators/windows_x64's `run`
                                           and the executable with its function map

The outputs stage runs the generator after writing the texts, so a refusal while emitting still leaves the
representations to read. With `--check` the low stages and the generator do not run, and the outputs stage writes
only what the high representation gives. No stage reaches back into an earlier one.

## A stage's passes

A stage with passes (proofs, high_optimization_passes, low_optimization_passes) has a `type` for them, with the one
function every pass has, in its entry class or, where other stages take it too, in the entry class holding them all, so a class that does not fit is a compile error where it is
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
costs nothing over a hand-written sequence. `register` crashes once `run` has started. A high pass's entry is its folder's `pass.spite`
(class `Pass`), which the stage registers; a low pass's entry class is named for the folder and is what the stage registers,
and a low pass whose work is per function keeps that work in its `pass.spite` (`Pass(function)`), its entry class running it over every selected function (`LoweredProgram.is_selected`: every
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

0. `proven_present`: first the literal conversions (`literal_conversions`, which evaluates each conversion of a literal
   the builder recorded over the high representation, so it runs in every build and `--check` agrees with `--build`);
   then the `T?` locals, attributes and answers every assignment or `return` of which is present
   (`present_assignments` and `present_answers`, run together until neither proves more), recorded as the builder
   context's `PresenceFacts`, which `present_values` and `proven_checks` read. A refusal the builder makes first
   proves them over the functions built so far.
1. `recorded_sites`: every site the builder recorded, in the order built, judged by the proof of its kind:
   - `present_values`: a value that may be null (an unnarrowed `T?`, an unproven `[]` read) is never used where a
     value is needed;
   - `proven_checks`: no check repeats what is already proven, no `fallback` or `crash` checks a plain value, and no
     copy is made only to narrow it;
   - `loop_narrowings`: an assignment inside a loop does not undo a narrowing the next pass reads;
   - `guard_asserts`: a guard `fallback` answers only "nothing", and a last `if` is not a hidden guard;
   - `lost_writes`: a write to an object only this function holds is read, and a name read from a list is not
     assigned as its last mention;
   - `literal_conversions`: a literal's conversion did not answer `null`.
   A refusal the builder still makes asks this walk first, for all but `present_values`.
2. `rules_after_building`: the rules of `validators/abstract_syntax_tree` that need the built program (the call
   inside a call, unused names, and the lone hole, which reads whether each hole the builder built is text), and the
   reopening that changes an attribute's type (`validators/mapping/reopened_type`, comparing the resolved types).
3. `switch_cover`: every switch the builder recorded covers its cases, and a `_:` answers for something.
4. `vector_fit`: every `Vector` the builder recorded making holds a class that fits one.
5. `compile_time_facts`: the answers to `function_waits`, `function_writes` and their kind, and the refusal of an
   answer that would decide itself.
6. `literal_dictionaries`: a local dictionary written out and only read by keys written out holds exactly its
   entries; it records each one and marks each read of a key it lacks (a speed proof, and what lets the next proof
   refuse a `crash` on such a read).
7. `folded_crashes`: a `crash` that folds false in reached code is a compile error.
8. `every_attribute_is_read`: an attribute nothing reads is a compile error.
9. `narrowings_kept_across_calls`: a narrowed attribute is not read past a call that may assign it.
10. `ranges`: the ranges of numbers that let arithmetic and divisions go unchecked (a speed proof: it records its
   facts on the operations).
11. `setup_lists`: a list its setup fills with objects it makes holds exactly those (a speed proof: it records each
   counted loop over such a list in `HighProgram.setup_list_walks`).
12. `lists_in_the_frame`: a local list of numbers filled at its own level and then only counted and read by
   index holds a known count of items (a speed proof: it records the count on the list's declaration,
   `Declare.frame_items`, which a high pass carries with the statement, and the lowering lays the list out in the
   frame).
13. `reload_changed_classes`: in a reload compile (`--reload-at`), which of the program's files and classes changed
   since the running program's manifest; none answers `unchanged` before anything is lowered.

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

0. `literal_answers`: a number or an enum value the proof `literal_conversions` worked out replaces its call.
1. `setup_list_calls`: each recorded loop over a setup's list is one direct call per item, to the function of the
   item's class. This is what makes a stage's `run` direct calls in order.
2. `fused_chains`: a `List` or `Vector` template called on the answer of `filter_` and `map_` steps is one call to
   a function written from the last template's body, with the steps inside its loop.
3. `banded_loops`: an `each_` over a `List` whose passes write only their own item calls the template that runs it
   in bands, and a counted loop of one such call runs its count inside each band.
   Right after it, the proof `independent_work`, registered through `HighOptimizationPasses.Proving`, marks each
   declaration whose call is quiet work and each that stands apart from the run before it, and the pass
   `overlapped_work` starts every heavy marked call of a run but the last on the pool and joins each where its name
   is first read.
4. `folded_dictionaries`: a local dictionary written out and only read by keys written out is its entries.
5. `unreached_functions`: a function only the calls those passes replaced reached is dropped.
6. `untouched_attributes`: attributes nothing reads have no slot, and attributes nothing writes are rebuilt where
   they are read.
7. `layouts_by_use`: every class's layout (offsets, sizes, packing, the shared blocks of union members, the room of
   a short text), recorded as `HighProgram.layout`.
   Right after it, `split_classes` marks each call whose receiver or argument holds one known value in an attribute
   only its constructor sets (`Call.known_regions`), which the specialised calls read to split the class.
8. `static_singletons`: the singletons that hold nothing and make nothing, each one object in the executable's data
   (`HighProgram.static_singletons`).
9. `call_assignments`: what each call may assign (`HighProgram.assignments`).
10. `singleton_locks`: which functions wait or can be resumed, which singletons keep a lock and which loops share
   it (`HighProgram.waits`).
   Right after it, the proof `no_thread_counts`, registered through `HighOptimizationPasses.Proving` since it reads
   that walk, records the classes another thread may count (`HighProgram.thread_counted_classes`); every other
   class is counted plainly. Then the proof `copies_nothing_changes`, registered the same way since it reads what
   each call may assign and the waits, marks each copy that nothing changes while it lives, and the pass
   `shared_copies` declares each marked copy from its original. Between `singleton_locks` and `no_thread_counts`,
   the proof `lone_atomic_attributes` records the attributes of a locked singleton that are atomic on their own
   (`HighProgram.lone_atomic_attributes`), which another class reads with no lock.
11. `replaced_defaults`: the defaults a constructor replaces and those only left-out defaults read, trimmed for that
   constructor, and the slots it hands a fresh object (`HighProgram.trimmed_defaults`, `trimmed_keys`,
   `fresh_by_constructor`).
12. `taken_parameters`: the parameters a function keeps, which its callers hand over without counting
   (`HighProgram.taken_parameters`).
13. `embedded_attributes`: an object only its holder holds lives inside it (into `HighProgram.layout`).
14. `inline_items`: a list's objects sit inside its storage, or in one array per attribute (into the layout).
15. `lent_attributes`: an attribute that only holds an item of its holder's list is not counted (into the layout).
   Right after it, in a reload compile, the proof `reload_reaches_moved_objects`, registered through
   `HighOptimizationPasses.Proving` since it reads the final layout, refuses a reload whose layout of a class the
   running program holds, or whose numbers of an enum's values, differ from the manifest's.
   Then the proof `steady_singleton_attributes` records the singleton attributes nothing assigns after their
   singleton is made (`HighProgram.steady_singleton_attributes`), whose loads `made_singletons` marks invariant.

Passes 2 to 15 run only when the program is lowered (not with `--check`). Passes 7 to 15 make the decisions the
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
specialised calls; then the placement (known headers, object placement) and the cleaning (thirty-five function
passes from settling the singletons to the last live values, the registers written more than once renamed into
one per write and joined again once copies are read through); then direct calls and the late inlining, the placement
and the cleaning again on the functions it changed; then, on every function again, releasing in place, vector loops,
and the last shaping of blocks, live values and copy coalescing.

## The folders

One layout for each kind of folder, so opening one says where its entry is. `folder_layout/` walks the compiler's own
namespaces with `crash`es decided while compiling, so a stage without its entry, a pass or proof folder without its
class, a rule folder without `Validator`, a fix layer without `EveryFix` or a printer without `Printer` refuses the
build, under `--check` too (D1885, `spite_spec`'s `compiler_folder_layout_broken`). A `Validator` holds a `check*` when it
walks something, or a `refuse*` when the lexer or the parser found the mistake and only asks it for the words (`spelling`,
`syntax`; D1886). `compiler_contracts_are_true` holds that every stage has a `contract.md` naming only files, folders and
flags that exist. The size of every file is held by `validators/abstract_syntax_tree/file_content_budget`.

| Folder kind | What it holds today |
|---|---|
| stage (`name_resolution/`, `outputs/`, ...) | `<stage>.spite` (the entry class `Stage.Stage`) and `contract.md` |
| high pass | `high_optimization_passes/<pass>/pass.spite` (class `Pass`) and its helpers |
| low pass | `low_optimization_passes/<pass>/pass.spite` (class `Pass`, the per-function work) and the entry `<pass>.spite` the stage registers; some folders hold several entries |
| proof | `proofs/<proof>/proof.spite` (class `Proof`) and its helpers |
| validator rule | `validators/<layer>/<rule>/validator.spite` (class `Validator` with a `check*` or a `refuse*`), and `every_rule.spite` in the layer |
| fix rule | `fixes/<layer>/<rule>/fix.spite` (class `Fix`), and `every_fix.spite` in the layer; `fixes/fixes.spite` writes |
| printer | `printers/<printer>/printer.spite` (class `Printer`) |
| emitter | `generators/<target>/instructions/<instruction>.spite` per instruction kind |
| builder (`high_intermediary_representation/building`, `low_intermediary_representation/lowering`) | flat folders of one file per concern; no hub or state file layout yet, except `building/prompt` (`SourceState`, and `*_text.spite` for the texts it writes), `building/reflection.spite` (`ReflectionState`), `building/statements.spite` (`StatementsState`), `building/values.spite` (the `Values` its concerns take) and `low_optimization_passes/vector_loops` (`VectorLoopState`), which keep their fields in one state object every concern class takes, as the lowering does |
| helper | next to what uses it; a helper several passes read lives in the stage folder (`high_optimization_passes/references.spite`), though a few low passes still read each other's `Pass` and `compile_time_evaluation`'s `Frame` and `Machine` |

The passes and proofs are registered in the constructor of their stage's entry class, in order; there is no
`every_pass.spite` or `every_proof.spite` yet, since `proofs/setup_lists` reads that constructor.

## The lowering of a function

`low_intermediary_representation/lowering/function_lowering.spite` is the entry of the lowering of one function. It holds
the exhaustive `switch`es over the values and statements (`lower_value`, `lower_a_statement`), the block and register
primitives (`emit`, `new_register`, `new_block`, `switch_to`), the small questions every concern asks (`is_a_pointer`,
`width_of`) and the setup of a function (`lowered`). Its fields live in one object, `LoweringState`, which every concern
takes (never the `FunctionLowering`, which would be a reference cycle). The concerns call each other both ways, since a
statement lowers a value and a value lowers a call, so none holds another as an attribute: a function that needs the
primitives, a switch or another concern makes one over the same state as a local (`var lowering = FunctionLowering(state)`).

`frame_lists` lays out the lists a frame holds and the appends of a slot, `counting` owns, retains and releases a value,
`statements` lowers a block and each statement, `values` the plain values, the operations and the objects made,
`calls` the calls, their arguments, function values and foreign calls, `singletons` the making, locking and sharing of
a singleton, and `conversions` the conversions, boxing, shape calls and the checks of decimals and ranges. The
collaborators that write one kind of function (`working`, `settling`, `callbacks`, `list_reads` and the rest) take the
`FunctionLowering` they write into and reach its fields through `lowering.state`.

## The resolver and the reflection builder

A class too large for one file keeps its fields in one state object, and each concern is a class beside it that takes
that object (never the entry, which would be a reference cycle), as the emitter does. The more basic class never
names the one above it.

The resolver (`name_resolution/resolver.spite`) only holds the state and the concerns and starts the resolution.
`ResolutionState` holds the fields; `same_members` finds a union or type already written under another name,
`instances` (the `monomorphiser`) is the worklist of classes to fill and the generic instances minted for it, `types`
resolves a written type, `owners` works out the owner and class of the names of a template, and `reading` reads a class
file's declarations into the model. A class waiting in the worklist is filled by a `Reading` that `instances` makes when
it drains the list, since `types` asks for a drain and `reading` asks `types` for a type.

The reflection builder (`high_intermediary_representation/building/reflection.spite`) is split the same way, over
`ReflectionState`: `described_names` (names and paths), `features` (which reflection functions the program asks for),
`writing` (constants, locals and calls a fill writes), `class_objects` (the objects of classes, namespaces, enums,
unions and types), `declarations` (the objects describing one declaration), `wrappers` (the wrappers of a described
function), `member_lists` (a class's attribute and function lists), `fills` (the fill of each reflection object) and
`making` (the constructor of every reflected class). A caller names the concern: `reflection.class_objects.class_object`,
`resolver.types.type_in`.

The statements builder (`high_intermediary_representation/building/statements.spite`) keeps its fields in
`StatementsState` (`statements_state.spite`) and builds a block and each statement. Like the lowering, its concerns call
each other both ways, since an `if` builds a block and a block builds a loop, so none holds another as an attribute: a
function that needs another concern makes one over the same state as a local (`var statements = Statements(state)`).
`statements` holds the block and body orchestration, the exhaustive `switch` over the written statements (`build`), the
variable, the evaluation, the return, the `if` and the `fallback`, the facts an `if` proves and what the builder
records for the proofs; `assignments` writes a name, an attribute, a bound member, a shape and an index and forgets
what a write undoes; `loops` builds the `while`, the renewal of a list of lists and the checks a loop asks of a count
or a bound; `switches` builds the `switch`, checks its cover and its case kinds and reads a case's condition; `crashes`
builds the `crash`, the guard's failure, and the site and identity a crash is recorded under; `reports` writes the
program that prints a crash's report and the parts of the failed condition it shows. A caller outside names the entry:
`statements.function_body_of`.

The values builder (`high_intermediary_representation/building/values.spite`) builds the value of every expression.
Its concerns take the `Context` and the `Values` and do not hold their parent, as `declared_walks.spite` does, so
`Values(context)` and every caller that holds a `Values` stay as they are; the fields they share (`temporary_count`,
`spread_into`, `typing`) stay on the `Values`. A concern that needs another makes one as a local
(`var fitting = Fitting(context, values)`). The order of the fits, of the calls and of the operators is written as plain
functions in each file, never as a list of rules, since the order is the meaning. `values` keeps `value_of` (the
exhaustive `switch` over the written expressions), `known_constants` and the helpers more than one concern uses;
`operators` builds the binary and unary values, logic, comparisons and class tests; `literals` the literal, default,
text, enum and `this` values; `fitting` the fit of a value to a type (`fitted`), its conversions, unions, shapes and
signatures; `collections` the list, dictionary and object literals, the index and the foreign call; `reads` the
names, members, getters, attributes and what a build setting reads; `walked_lists` the walks over the classes, values
and attributes a class declares; `arguments` the arguments of a call, their spreading and the refusals of a value passed;
`calls` the calls, constructions, member calls, presets and function values; `templates` the specialising of a member
template, pattern matching and the template match; `naming` plurals and inflection; `questions` the value calls,
the reflection questions, the waits and writes questions and the folded counts. A caller outside names the concern:
`operators.condition_of`, `fitting.fitted`.

## The targets

A target is a folder of `generators/` (`windows_x64`), chosen once by which one `spite_compiler.spite` makes; no
code asks which system it builds for (D1709). What every x64 target writes the same bytes for is shared in
`generators/x64`: the instruction encoding (`Encoder`, `Fixup`, the divisions by a constant `Magic` and
`UnsignedMagic`), the vector kernels and the register allocation. What a target alone owns stays in its folder:
its emitter, its calling convention, its executable format, its fault handler, its allocator of small blocks
(which asks the system for memory), and its hot-reload host.

The emitter (`windows_x64/emitter.spite`) holds the exhaustive `switch` over the low instructions and the walk over
functions and blocks. Its fields live in one object, `EmitterState`, which every helper class takes (never the
`Emitter`, which would be a reference cycle): `instructions/<instruction>.spite` writes one kind of instruction
(`instructions/decimal/` the decimal ones), and `fixups`, `frames`, `edge_moves`, `block_analysis`, `places`,
`runtime_routines`, `decimals`, `cold_stops` and `division` hold what several of them share. A constant two classes
use lives in `opcodes.spite`. A jump is written in the emitter, since a rotated loop emits the test of its head again.

The allocator never names a register a convention decides. It reads the target's `X64.CallingConvention`, a table
the target fills (`windows_x64/convention.spite`): the registers that carry the first arguments, the registers a
call keeps (in the order values take them), the scratch registers a value may hold where nothing it lives through
calls, the first decimal register a call keeps (16 when none is kept), and the room a caller leaves above its
arguments (the shadow space).

`x64/allocation.spite` is the allocator's entry: its lists live in one object, `AllocationState` (`allocation_state.spite`), and
`allocate` calls the phases by name, each a class of its own that reads and fills those lists through the state it is given:
`lay_out_the_blocks` and `find_the_flow` (`block_flow.spite`: block layout, positions, edges, reachability, loop depths),
`read_the_operands` (`operand_readings.spite`: counts, constants, decimals), `fold_the_addresses` (`address_folds.spite`: fused
compares, folded addresses, rematerialised loads), `find_the_lives` (`lives.spite`: liveness, weights, live sets),
`build_the_intervals` (`intervals.spite`: segments and joined copies) and `place_the_values` (`placement.spite`, which asks
`occupancy.spite` what a physical register may hold where and `splits.spite` for the split and spill choice). `answers.spite` holds
what the emitter asks once the registers are placed (`home_of`, `moves_on_the_edge`, ...) and the small readers of the tables the phases share.
`NoAllocation` (`no_allocation.spite`) is the state a phase holds until its constructor is given the real one, so making a phase
builds no lists. Each phase reads what the ones before it filled. The layout runs first because the emitter reads it for a function
the rest skips, and liveness runs after the flow because it walks the blocks in layout order.

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
`Spite.Fault`, the fallback ring `Spite.Fallbacks`, the deep copy table `Spite.CopyTable`; and, only in a `--repl` build,
`high_intermediary_representation/building/prompt/text.spite`: `Spite.Prompt` and `Spite.PromptPath`). The first
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

Day to day nobody runs the chain: in this folder, `.spite/spite.exe --build
--executable-path=.spite/spite_next.exe` builds the next compiler from the current source, and the
next one is kept when it rebuilds itself to the same bytes. A change the current compiler cannot build (a rule
it would apply to its own source, or a library it would not recognise) is built through a compiler that accepts
both forms, and that change publishes a new seed: its fixed point as a new `seed-<date>` release, named in
`SEED_TAG` in the same commit.

## A failure stops its own check

A step holds no error text. When it finds something to judge (a folder name, a token it cannot read, a parsed
file), it hands it to the validator of that rule at once. The validator lets it pass, or refuses it through
`Diagnostics.Failure`. A mistake with one fix never reaches its validator: the layer's fix rule changes the tree
first (below).

A refusal stops the check it happened in, and the compile goes on to the other checks. `Diagnostics.Gathering`
(a singleton) holds what was found, and what happens next depends on the check:

| The check | What a refusal does | Why |
|---|---|---|
| a rule of `validators/abstract_syntax_tree` on a read file, a proof | `Failure` keeps the problem and returns, and the rule walks on (`gathering.goes_on`) | they only read a whole tree or program |
| reading a file (its lexer and parser), building a function or a class's defaults | a new round: `Diagnostics.Rounds` runs the compiler again, and that run skips the failed check | a step cannot be left half way, and nothing in the language unwinds it. A fresh run has no half-built state, so it cannot echo |
| anything else (the command line, the mapping, name resolution, the steps after the proofs) | everything found so far is told and the compile ends | nothing can go on without it |

The first run drives the rounds, so at most two compilers are in memory: each later round writes what it found to
`.spite/failed_checks.txt` (`Diagnostics.Ledger`) and answers `goes_on_answer`, and the last one tells everything.
A round costs one compile up to the next failure, the same as fixing that error and compiling again. Rounds stop at
25 errors in the program or after `most_rounds`; the list then ends `and possibly more in the program`. A fix
written in a round restarts the compile from nothing, since the lines it found may have moved.

A stage does not run on a broken input. Once every file is read, any refusal so far ends the compile before name
resolution (`tell_if_reading_broke`); once every reached function is built, any refusal ends it before the proofs
(`Builder.build`), since a proof reads the whole build and would call a proven line unproven. The proofs all run,
and any refusal ends the compile after them. A refusal the builder makes first asks the proofs about what is recorded
so far, since a check of a plain value is a fix or a proof's error before it is a type error; only what does not need
the whole build answers then, so `present_values` waits, and the builder's own refusal is dropped when that found an
error in its function, as it may be an echo of it. So an entry file that does not parse, or one error
in a stage's input, hides what later stages would say; that is a missing error, never a false one, and `Gathering.add`
keeps only the first error of a line for the same reason. `Diagnostics.Listing` cuts the list to its limits.

## Fixes

What has exactly one fix is fixed in a program's own file instead of refused (D800, D1767). `fixes/<layer>/` holds
one rule per folder (`fixes/<layer>/<rule>/fix.spite`, a class `Fix()`), and each layer reaches its rules through
one entry, `Fixes.<Layer>.EveryFix`, called the way a pass is, just before that layer's validators, so a
validator only ever sees what stays an error:

| Layer | Entry, called from | Rules |
|---|---|---|
| tokens | `fixes/tokens/every_fix.spite`'s `fixed`, per file between the lexer and the parser (`AbstractSyntaxTree.run`) | `misspelt_keyword` |
| syntax tree | `fixes/abstract_syntax_tree/every_fix.spite`'s `fixed`, per file as it is read (`SymbolTable.read_class`) | `misplaced_comment`, `declaration_order` (the printer prints declarations in the enforced order), `type_member_form`, `after_return`, `local_names`, `default_guard` |
| symbols | `fixes/symbols/every_fix.spite`'s `fixed`, once, when every class is read (`Symbols.run`), and it writes and restarts right there | `unneeded_load`, `repeated_declaration` (a `union` or `type` two classes of a root declare with one name and content moves to the entry class of the lowest namespace holding every copy) |
| after building | `fixes/after_building/every_fix.spite`: `fixed_a_check` from the proof `proven_checks` before each refusal, `fixed_a_terminal_if` from `guard_asserts`, `fixed_a_walk` before the rules after building, `fixed_an_attribute` from `every_attribute_is_read` | `proven_check` (a `crash` or `fallback` line that proves nothing), `decided_condition` (an `if`, a `while` or a `fallback` decided while compiling), `known_if` (an `if` on what is already narrowed, proven or a decided class test), `terminal_if`, `copy_to_narrow`, `unread_plain_local`, `unread_attribute` |

A fix rule changes the tree it is given (a statement replaced in or removed from the block that holds it, a
declaration moved between files) and answers a `Diagnostics.Problem` with `is_fix` for each change. It never writes. A rule called while the proofs still read the blocks hands its change to the owner instead (`replaced_later`, `cut_later`, `renamed_with_the_last_fix`), which makes it right before writing. A rename changes only the name a declaration or an identifier holds, so nothing proven about a value's slot is assigned again. A library file, a pinned
package's file, a generated class, a generic class, a walk and a file holding breakpoints are never fixed: their
mistakes stay errors.

One owner writes, `fixes/fixes.spite` (`Fixes.Fixes`, a singleton): no step, validator or proof writes a file or
restarts.

- `rewritten` prints a file read with `printers/spite`'s `Printer`, and when the text differs from the file
  checks that it reads back to the same text with every comment and every text's value (`validators/abstract_syntax_tree/formatting`),
  writes it, and prints the `fixed:` lines, or `formatted <path>` when no rule changed it; the symbol table then
  reads the written text again.
- `found_later` keeps a tree a fix changed, a file not yet on disk included. `run`, called once the proofs end, by
  the symbols layer and by
  `Diagnostics.Failure` before it tells an error, prints every such tree and reads each back, writes them only when
  all of them read back, prints the `fixed:` lines and
  runs the compiler again with the same flags, folder and environment, answering what that run answers (D1833).
  The number of restarts so far travels in `SPITE_FIX_RESTARTS`; past 8, the compiler names the fix that keeps
  coming back and crashes.

A `fixed:` line names the line the mistake was on in the file that run read.

`symbols/repeated_declarations.spite` (`Symbols.RepeatedDeclarations`) finds what repeats and decides where each lands
and whether it can: it needs every file of a root, so the fix runs after `read_the_program`, the first moment every class
the compile will use is read, and before name resolution, which would otherwise read each class's copy. The syntax-tree
layer sees one file at a time, and the after-building layer comes after name resolution has already minted a type for
every copy. What cannot move stays in `SymbolTable.repeated_declarations` for `validators/mapping/repeated_declaration`.

## Validators

`validators/<level>/<rule>/validator.spite` holds a class `Validator()` whose `check(...)` takes the data the rule
needs. The folder is named after the rule, and the validator holds every word of its error.

- A rule lives at the earliest level that has the facts it needs, and runs as soon as those facts exist: a file's
  rules run right after the file is parsed, before the next file is read.
- A validator never changes what it is given.
- Each layer reaches its rules through one entry, `validators/<layer>/every_rule.spite`, called the way a pass is
  (D1750): the syntax tree's `check` per file, name resolution's `check` once the model is resolved, the high
  representation's `check_an_evaluation` and the like as the builder meets each statement, the low
  representation's `check` once it is optimised, the command line's `check` once the program's `Build` settles
  the settings (`take_the_build`), and the mapping's `check` once every mapped class is read (the end of
  `Symbols.run`). The high entry also holds `stop`, which judges the sites the
  proofs have not judged yet before it ends the compile, so the earliest error is the one told. A check still
  written inside a step moves behind its layer's entry (spite_compiler#243).
- A rule is a `check` or `check_...` that receives the data it is about (what the resolver found, the built value,
  the site a proof recorded) and decides: a step never tests the condition and then asks a validator to word it.
  Name resolution hands its rules a `NameResolution.Place`, which finds the function a message names only when one
  is told.
- A proof decides what it proves and hands what breaks it to a validator of its own
  (`validators/high_intermediary_representation/<rule>`), never to the shared `typing`.
- A check no program can reach, a fault of the compiler itself, is a `crash` on a condition named for the fault
  (`expects_its_slots_fresh` in the lowering), not a rule with a message.
- `diagnostics/failure.spite` (`Diagnostics.Failure`) ends the compile; only a validator or a proof builds one.
- The test `tests/compiler_rules_are_validators` of spite_spec reads this source: every
  `validators/**/validator.spite` defines a `check`, and no file outside `validators/` and `proofs/` defines a
  `refuse...` or builds a `Diagnostics.Failure`. The files still waiting for a rule to move (the parser, the lexer
  and the `typing` refusals, after spite_compiler#25) are listed there, each with what it waits for.
- A file over its file content budget ([the rule](https://github.com/Spite-Language/spite_spec/blob/master/specs/style.md#the-file-content-budget))
  stops the compile first, in `validators/abstract_syntax_tree/file_content_budget`. A file still over it would wait in
  that folder's `waiting_list.spite`, a literal of program folder plus path, with no flag, setting or file that adds to
  it. `tests/compiler_file_content_budget` of spite_spec holds the same list, so it can only shrink, and a listed file
  back within the budget is an error until it leaves both. Both lists are empty now, and both go when spite_compiler#311 closes.
- A file's rules read one `AbstractSyntaxTree.Walk.Walk`: every block, statement and expression of the file with
  its line and function, made once. A message quotes code through `printers/spite`.
- A rule that needs the whole program runs once the program is complete; a rule about one class runs per class,
  and a reload runs only those.
- The message says what the old compiler's message says (the old compiler's diagnostic programs), in this compiler's
  words, and a `conformance` test of [spite_spec](https://github.com/Spite-Language/spite_spec) pins it.

## Printers

`printers/<what>/printer.spite` holds a class `Printer(input)` answering `text(): String`. A printer never writes
a file and never changes its input.

- `printers/spite` prints a tree as Spite: a statement or an expression to quote code in a message, and a whole
  file (`Printer`, with `LineBreaking` for lines over 120 columns) as the one way a file is printed: the
  same tree always prints the same text, with the comments the tree holds (a function's, the class's heading).
  `Fixes.Fixes` writes what it prints ([Fixes](#fixes)); `--final-classes` writes its merged classes as
  `printers/final_class` prints them.
- `printers/diagnostics`, `printers/high_intermediary_representation`, `printers/low_intermediary_representation`,
  `printers/optimization_report`, `printers/machine_code`. `--high-ir` and `--low-ir` write the two
  representations next to the executable, as `<program>.high_ir.txt` and `<program>.low_ir.txt`.

A text that is an identity (a type's key, an instance's name) is not printing: it belongs to the step that owns it.

## Passes

`<stage>/<name>/pass.spite` is the pass of the folder (a proof's is `proof.spite`); a high pass's and every proof's fits the stage's type, and a low pass's entry class is `<name>.spite`. What several low passes
and low proofs read the same way is a reader at the top of `low_optimization_passes/` (`Operands`, `Flow`,
`BlockEdges`, `Dominance`, `RegisterLives`, `SingletonTests`), not part of any one pass. A unit pass reads one
function or class at a time; a program pass needs the whole program (tree shaking, inlining across classes,
placement of objects that leave their function). Each optimisation and each proof is a pass of its own (D1086,
D1087), and nothing that builds a representation also optimises it.

## Proofs

`proofs/<what_it_proves>/proof.spite` proves one fact over the whole built high representation and hands
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

### The list let go at exit

A singleton and a reflection object each have a slot of state (`singleton.<class>`, `singleton.<kind>:<name>`): the
object, the next slot on the list, whether it is made, its `drop()` or let-go function and the thread making it.
The thread that wins the claim on a slot (a compare-exchange of its state) makes the object and pushes the slot on
the list the program lets go of at exit, newest first. Two threads can each be making a different one at the same
moment, so the push is a compare-exchange on the list's head that reads the head again and retries when another
push came between, instead of a plain store that would lose one of them.

### Work a condition needs runs where the condition reaches it

Building a value can need statements before it (a temporary that holds a call's answer once, an object literal's
fields): the builder keeps them pending and writes them before the statement that reads the value. The right side
of `and` and `or` is reached only when the left does not decide, so its work cannot be written before the whole
condition: that would run a call the program skips (`shown and maybe_true()` asks `maybe_true` when `shown` is
false) and read a temporary on a path where it was never set. When the right side needs work, the builder holds
the answer in a `Boolean` local set to the left side and writes the right side's work, then the assignment of its
answer, in an `if` that runs only when the left side did not decide. A `while` whose condition has work holds its
answer the same way: a `Boolean` local starts true, and each round of the loop does the work, sets the local to the
condition and runs the body in an `if` on it. The work is written once, so its temporaries live and die within a round
and a fact a proof records on a value holds for every round that value is reached by.
