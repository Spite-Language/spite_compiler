# TODO

What is left, in order. One line each; delete a line when it is done. The old compiler's rules are in
`../SpiteLanguage/specs`, its optimisations in `../SpiteLanguage/docs/optimizations.md`, its proofs in
`../SpiteLanguage/docs/proofs.md`.

## Architecture (now)

- Rules that need types, after the typed high representation: template walks (`template_walk`, `vector_template_walk`, `walk_with_function`), a condition that is not a Boolean, foreign libraries and callbacks, codegen value questions (`argument_count`, `function_reflection`, `parameter_write_question`, `returned_text`), a `_:` that answers for nothing, and the rest of level 5 of `../SpiteLanguage/diagnostics`
- Rules that need name resolution (level 4 of `../SpiteLanguage/diagnostics`): a class name that reaches nothing, attributes never read (reopenings can read them, and walks, `to_debug()` and the JSON writers read them only in the high representation, so it needs both), reopening rules, the parameters of a function that replaces another (exempt from the unread rule)
- A comment inside an enum, union or type body is not refused yet (only function bodies have their closing line)
- Port the rest of the mapping rules: a class named like a namespace, a hidden class, a class named like a library class, `spite/` folders
- The emitter's refusals have no place (`validators/low_intermediary_representation/emittable`): each becomes a validator one level up once the high representation carries places
- Every node carries its file, line and column, from the tree to the instructions
- Unions and enums instead of strings in both representations (instruction kind, operator, types, call owner)
- `printers/spite` and the formatter; the tree keeps comments, blank lines and literal spelling; `--final-classes`
- `printers/optimization_report` and `printers/machine_code`
- Low representation in SSA form with basic blocks, and register allocation
- Unit passes and program passes split by input type; every function has a stable identity for cache keys
- Objects live on the heap until a pass proves the frame (replaces copying a returned object into the caller)
- An argument is passed by its parameter's type only, never by where the caller's value came from
- Mortaro confirms or drops D8 to D11 and D17 to D27; D10 (type argument given at run time) contradicts monomorphisation

## Faults found

- A plural template's member is matched with the program's own `String.Inflection` table, but a word that table leaves out is inflected by the compiler's own library rules and irregulars, which a reopened table may have dropped (`foot`)
- A pattern template whose hole names no enum (`Symbol<$t.phase_each>` with no `Phase`) crashes the compiler instead of the old error naming the enum to declare
- A class name that reaches no file is collected in `SymbolTable.unknown_names` and never reported
- The emitter resolves a call whose class is unknown by the function's name alone, when one class has it
- A `load` inside an `if` is refused; the language allows it when the condition reads only build settings
- `WholeNumber.value()` answers 0 for a text that is not a number
- A union switch with repeated case bodies must use `_:`, which lets a member added later slip past a walk

## The language

- The runtime the library needs, as machine code: allocator, console, files, directories, clock, sockets, processes, dynamic library, weak references
- `DynamicLibrary.close_library` frees nothing yet; `whole_library` (a test that reads every class of the library) returns once text builds
- `--debug-memory` counts and the leak report; an attribute read from an object made in the same expression (`Maker().part`) leaks that object; the counts a pass proves unneeded are still written
- Chains of member templates as one loop, class filters on a `Dictionary`'s values, the errors of plural, enum value and chained templates (a singular where the plural differs, two members with one plural, `map_is_alive`, a member named like an enum value), and the passed-function forms that need an overload by count beyond `count(f)` or a function-level answer type beyond `sum(f)` (`sort_by(f)` by text)
- A dictionary keyed by hashing instead of a walk of its keys
- A function value that answers a nullable number carries its presence only through `CallAt`; reflection on function values (argument names and count)
- `Float` and `Double`: `%`, exponent notation in literals, a `Double` too large for a `Float` halting, and `UnsignedLong` to and from a decimal past 2^63; a decimal too large for a `Long` prints a wrong number in its range-stop message
- Crash reports: a crash line shows only the whole numbers its condition names (texts, decimals, enums, `T?` and the function's other locals and attributes are not shown yet), an `assert` of several parts keeps one site for all of them, the ring allocates its 32 lines as they first fill, halts other than `crash` (overflow, a missing item) and native faults do not print the ring, and the `<program>.crashes` map is not written
- A number's room is a `Buffer` made on every read of `_buffer` (D33): fold a read at a known position of a fresh room into the number itself

- `Symbol` is text marked as a symbol: `symbol.class` is not yet `Symbol`, `Symbol(text)` and `Symbol<T>` outside a template parameter are not built; `Anything`, and `Null` and `Number` as type names outside a `$T ==` test (D35)
- `Build` reads are not folded, so both branches of `if build.serve` are compiled; a `load` under an `if` on a `Build` field
- Arithmetic and functions through `Number` (`value + value` on a `Number`)
- A template's compiler-supplied functions (`BinaryWriter.schema()`); `deep_copy()` through a union or a shape, and of a graph with cycles (today a cycle recurses until the stack runs out); a copy runs the attribute defaults before it overwrites them; a walked row declared `var row: $row_type = null` when `$row_type` is a `type`
- Vector and Items keep their items inline: today they hold references, so changing a found item changes the one in the list
- Reflection as reopenable library classes (`Spite.Class`, `Spite.Namespace`, `Spite.Function`, `Spite.Attribute`, `Spite.Argument`, `Spite.Access`), filled in by the compiler and folded where constant (D37, D50 to D55): still missing are `function.arguments.each(f)` with an answer typed by the argument (`argument.class`, `reflection_walks`), folding of constant reads (a constant list's `[]`, `filter`, `each` and member templates, so `hurt.arguments[1]` needs no run-time check, D53), the `if` on a late answer (`function_waits`, `function_writes_parameter`) dropping its other branch, `Spite.Call`, enums as classes, `Symbol<Spite.Class>` and the `Spite` namespace by name (`class_walk`), a plural template over a generic's attributes (`reset_attributes`, `every_attribute`), stand-ins for singletons, and a function value being the same object as its `Spite.Function` (a function value put in a `List<Spite.Function>`, `run_time_accesses`, `reflection_walks`)
- `Parallel` starts a thread of its own for each handle (and `parallel_each_<function>()` one per piece): the thread pool behind it, the race rule of `parallel_each_` as a compile check, and the console's buffer shared by threads that print at once (D36)
- `Concurrent` does not return to the scheduler where a handle it holds is let go while its work runs: a handle, an object or a list holding handles dropped at its scope's end, a handle or an attribute holding one assigned again, and a list of handles cleared all wait in place for the work instead (`waits_never_hang`, `dropped_handle_waits`); file reads and writes block instead of running on a helper thread; one scheduler serves every thread, so a `Concurrent` made inside a `Parallel` races (`concurrent_in_parallel`); `run_ready()` and `resume_only_when_asked()`; a join halting when two `Concurrent`s wait for each other names neither (it stops in `Scheduler.every_concurrent_waits_for_another`); a poll that never steps anything does not halt
- A wait in a frame does not hold the frame: a frame loop's started calls, `WaitsInFlight` and the check that no carried value is written back (`frame_waits`, `frame_waits_kept`)
- `foreign_callbacks` and `ipv6_addresses` still use `Memory.Address` and `Memory.Heap`: rewrite them with `Buffer` when foreign callbacks and sockets come (D36)
- Allocation tests (frame objects, lent buffers, kept buffer addresses, the memory floor) come back as `--debug-memory` counts with the passes that place memory (D35)

## Faults found while porting

- The spec puts the inflection table at `library/string/inflection.spite` (`String.Inflection`), but a class file and a folder of one name are refused (`conformance/class_and_namespace`), so the table stays `common/inflection.spite` and the plural templates fall back to the compiler's own rules: a program reopening the table (`inflection_table`) is not read yet. Needs a decision on whether a class may also be a namespace

- `shape_members` corrupts the heap (reported in `List<Spite.Internal.Running>.reserve`) once a `type`'s function is held as a value and run through `Parallel`: a count is released once too often

- `tests/system` expects `Arguments.get(3)` to answer "" for a missing argument, a default nobody can tell from a real answer (D244): the library stops instead, and the test needs a decision

- The fault handler runs before any library's own exception handling, so a C library that catches its own faults inside a foreign call would be stopped

- `Json` and the old type spellings (`Int`, `Bool`, `LocalDate`...) are refused by name even when the program declares a class of that name
- A crash inside a library function names the library line, where the old compiler named the program's call (`smallest_absolute`, `negative_shift`, `items_remove_out_of_range`, `json_infinity`)
- `items_columns`, `sparse_rows` and `plain_items` stop reading a column after `Items.remove_swapping`

- Class objects are filled from a worklist once compiling ends, but every read of a constant one still reads the run-time object: fold the constant ones while compiling (the 64 MB main stack reserve raised for the nested fills can come back down)
- The study behind `function_waits` (D50) follows a call through a function value only when the compiler knows its function, so a function that waits only behind a function value it is handed answers `false` (a silent wrong answer under D244: answer `true` where it cannot tell, as `docs/proofs.md` says)

- A program can still name `Spite.Internal` in a written type, in a text, or as a class in its own `spite/internal/` folder: only expressions are refused (`internal_class`)
- The library breaks three rules it is exempt from for now (D71): singletons bound as locals (`Arguments`, `Environment._setting`, `Spite.Internal.Fault.report`, `Spite.Internal.Work._settle`), locals that only copy a path to narrow it (`BinaryCursor._buffer`, `BinaryWriterCursor`, `JsonReader`, `JsonWriter`), and a terminal `if` (`Dictionary.remove_at`)
- The `if` that narrows a path does not record which check narrowed it, so a second check inside its branch is "a condition is a Boolean" instead of "already narrowed by"; `while value` does not narrow its body

- A decimal `%` is computed as `x - trunc(x / y) * y`, which loses digits once the quotient passes 2^53: compute it exactly, as `fmod` does

- A singleton circle closed at run time halts with the message for one singleton; it should name the chain (`singleton 'Registry' binds 'Catalog', which binds 'Registry'`). The compile-time check follows only a singleton binding another directly, not a circle through an object that is not one (`Metronome` binds a `Tick` that binds `Metronome`)
- A list of `Parallel` handles read with a proven index stops as if the item were missing (`singleton_function_values`)
- `private_walk` crashes the compiler (`class_of` of an unknown class while building a JSON or binary reader of a class with a private union attribute)
- A shape declared inside a class, or in a namespace's own file (`tools/tools.spite`), is not found by its short name (`nearest_type`)
- Two folders making one namespace (`mod/creatures` reopening `package/creatures`) are refused instead of merged (`reopening`, `folder_namesake`)

- `lent_to_calls` stops with heap corruption (0xC0000374): bisect it
- A temporary the builder declares for a comparison (`call() == true`) can be read before its declaration in some branch; plain reads avoid it today
- Building a text by appending to it copies it each time (`text_building` takes minutes)
- Two `Concurrent`s that wait for each other loop forever instead of halting (`concurrent_wait_cycle`), since the work runs in order

## The errors

- Every folder of `../SpiteLanguage/diagnostics` is ported to `../SpiteSpec/conformance/<name>` with its exact text, and passes

## The outputs

- `spite program` builds and runs; `--check`, `--build`, `--executable-path`, with the original's error texts for every other flag
- Crash reports and the `<program>.crashes` map
- `--optimization-report`, `--final-classes`
- `--repl`, `--repl-port`, `--hot-reload`, `--development` (see `HOT_RELOAD.md`); check whether the reflection model can be the reload manifest
- The runner has no time limit, so a test that hangs stops the whole run; the suite runs tests one at a time: run them in parallel, and make one compile fast enough that a model can iterate on the language test by test
- Caches per step and per unit

## The compiler proves itself

- The compiler compiles itself, and the executable it writes is itself
- The programs of `../SpiteLanguage` (conformance, examples, docs) are ported to `../SpiteSpec/tests` and answer the same
- This compiler's own entry file names its library with `load`, when it builds itself

## Every optimisation the original does

### The tree shaking and the compile-time questions

- Deciding conditions at compile time
- Reflection, symbols and registries only where read
- Reflection on constants folds and unrolls
- Template chains run as one loop
- A function taking a `type` is compiled per class
- A test against a value a list never holds is decided while compiling
- A table filled once is read as constants
- A dictionary written out and only read by literal keys is folded
- Maths on constants is worked out while compiling
- A binary schema is a constant
- A word inflected while compiling
- Identical functions are folded into one

### The memory, the placement and the copies

- The compiler places memory
- Reading an address is one machine operation
- Objects that never leave their function live in the frame
- A local list of known size lives in the frame
- A variadic list the callee only reads lives in the caller's frame
- A list held only by another list lives in its slot
- A list of lists filled again keeps each list's room
- Objects of one class sit together
- A row of borrowed items lives in the frame
- An `Items`' storage is chosen while compiling
- A deep copy is written per class, with a table only where a graph needs one
- A deep copy nothing changes is the original
- Copies that cost nothing
- Allocation is the C library's, counted only where read

### The counts

- Singletons: made on first use, never counted
- Singletons that hold nothing are static objects
- Atomic reference counts only with threads
- Plain reference counts where no thread reaches a class
- An argument its caller holds is passed without counting
- An attribute a call cannot assign is passed without counting
- Storing an object into a list counts it only when it changes the slot
- An item passed to a call that cannot change its list is not counted
- A singleton's attribute that never changes is read in place
- A list's templates read its elements without counting them
- An item written back to its own slot is not written
- A list item read only to test it is not counted
- A write-back of what the slot already holds is not written
- An item a name holds from its list is not counted
- Reading through a `type` without counting
- Objects made for their owner are told apart
- Counts stay plain for what one of the calls run at once counts

### The text, the numbers and the collections

- Appending to text in place
- Text joined in one piece
- A number joined into text is written in place
- Short text lives inside the `String`
- Short symbols are inline text
- A foreign name is never copied
- Crash text out of the binary
- A number's bits are read in place
- A decimal literal beside a `Float` is a `Float`
- A proven divisor is not checked
- Arithmetic is checked in every build
- Arithmetic a range proves is not checked
- A loop over plain values reads its count once and its items unchecked
- A proven read tests only its bounds
- A number read from bytes is one load
- A walked `crash` line's read is the row's read
- Boxing only where a value travels as a shape
- A function value describes its arguments when asked
- Defaults the constructor replaces are never made
- Proofs that survive a call
- A dictionary hashes a key once, cheaply
- A dictionary keyed by numbers hashes the numbers

### The threads

- Concurrency machinery only where it is used
- Hidden async/await as compile-time state machines
- Reads in a row overlap
- A wait in a frame does not hold the frame
- The thread pool only where a `Parallel` is made
- Singletons a `Parallel` reaches take a lock
- Thread safety for singletons, the cheapest safe form
- While no task runs, a singleton's lock is skipped
- A singleton no other thread reaches takes no lock
- A singleton's reading functions do not exclude each other
- A counted loop of calls to one singleton takes its lock once
- An attribute read only under its singleton's lock is a plain number
- A loop of calls to one singleton tests for tasks once
- Thread safety for singletons, the rest of the plan
- Calls in a row run at once
- A loop over a list of different classes runs them at once
- A loop whose passes write only their own item runs in bands

### The compiler's own machinery

- REPL, live reload and debug machinery only in those builds
- A reload compiles only the classes that changed
- What a `--hot-reload` build carries so its objects can move
- The fault handler is in every program
- A crash's report is kept out of the way
- Smaller ones
- Other optimisations

## Every proof the original makes

### Presence and control flow

- Narrowing a `T?`
- Every side of an `and` narrows
- An `if` that leaves proves the rest
- Assigning undoes a proof
- A call keeps a proof it cannot change
- Proving what is proven is an error
- A copy made to narrow is an error
- A class test narrows its block
- Every path ends in a `return`
- A guard `assert` answers only "nothing"
- A switch covers every case

### Indices and numbers

- A proven count or bound proves a read
- A proven read halts outside its list
- A proven count or bound proves a read of a width
- An index built from loop counters is proven by one guard
- A counted loop reads its items unchecked
- A proven divisor is not checked
- A divisor written as zero is an error
- Arithmetic that does not fit halts
- A range proves arithmetic fits
- A wider operand is written first
- Maths on constants is worked out while compiling
- A dictionary only read by literal keys is never made

### Compile-time questions

- Conditions decided while compiling
- Whether a function waits
- How many arguments a function takes
- Whether a class fits a `Vector`
- Whether a function writes a parameter
- Whether a class keeps state
- The one class a `type` admits
- A `crash` that folds false is a compile error
- Tree shaking: what `main` can reach
- A reload compiles only the changed classes
- A reload reaches every object whose attributes it changes

### Memory

- A buffer freed in its block lives in the frame
- Objects that never leave their function live in the frame
- Local and variadic lists in the frame
- A function value its callee only calls lives in the frame

### Borrowing and lending

- Borrowed items of a `Vector` or `Items`
- No borrowed read past a resize
- Rows of borrowed items
- An item lent to the caller
- An item lent to a call
- A list element lent to a row
- An argument its caller holds is passed uncounted
- An attribute a call cannot assign is passed uncounted
- A singleton attribute that never changes is read in place
- A list's templates read their elements uncounted
- An item written back to its own slot is the slot
- A value followed through calls is the slot it was read from
- An item a name holds from its list is not counted
- A list item read only to test it is not counted
- An item used at once is not counted
- A list held only in a slot of another list
- A list only its class fills holds only what it fills
- A table filled once holds what its setup put in

### Threads and locks

- Calls that share nothing written
- Classes in a list that share nothing written
- Passes that write only their own item
- An object made for its owner is told apart
- No other thread counts a class
- What one of the calls run at once counts
- Objects of a class made on one thread
- A copy nothing changes is the original
- Which singletons a `Parallel` reaches
- No other thread touches a singleton
- Read-only and atomic singletons
- A function that touches no changing state takes no lock
- Reading functions share the lock
- A counted loop takes a singleton's lock once
- A loop that starts no task tests for tasks once
- No attribute is read past the lock
- A lock that would wait forever is an error
- A loop that can never end is an error
- A poll that nothing steps is an error
- A write to an object only this function holds must be read
- A name read from a list, assigned and never read, is an error
- What a `Parallel` may reach
- Which calls suspend a `Concurrent`
- A wait in a frame is started

### Other refusals built on an analysis

- Unused is an error: a name, parameter or attribute that is only written and never read
- A constructed object must be kept and used
- Singletons that make each other in a circle are an error
- Build settings are constants
- A value fits a `type`
- A member template fits
- A value can be written
- What crosses into C
- Reads in a row are independent
- The short form is proven the same, and the long form refused
