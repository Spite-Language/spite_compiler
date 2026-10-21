# TODO

What is left, in order. One line each; delete a line when it is done. The old compiler's rules are in
`../SpiteLanguage/specs`, its optimisations in `../SpiteLanguage/docs/optimizations.md`, its proofs in
`../SpiteLanguage/docs/proofs.md`.

## Architecture (now)

- Rules that need types, after the typed high representation: the terminal `if` on a `T?`, template walks (`template_walk`, `vector_template_walk`, `walk_with_function`), a condition that is not a Boolean, foreign libraries and callbacks, `Environment` settings, codegen value questions (`argument_count`, `function_reflection`, `parameter_write_question`, `returned_text`), enum and union coverage of a switch, and the rest of level 5 of `../SpiteLanguage/diagnostics`
- Rules that need name resolution (level 4 of `../SpiteLanguage/diagnostics`): a class name that reaches nothing, attributes never read (reopenings can read them), reopening rules, the parameters of a function that replaces another (exempt from the unread rule)
- A comment inside an enum, union or type body is not refused yet (only function bodies have their closing line)
- Port the rest of the mapping rules: a class named like a namespace, a hidden class, a class named like a library class, `spite/` folders
- The emitter's refusals have no place (`validators/low_intermediary_representation/emittable`): each becomes a validator one level up once the high representation carries places
- Every node carries its file, line and column, from the tree to the instructions
- Unions and enums instead of strings in both representations (instruction kind, operator, types, call owner)
- Typed high representation: every value carries its resolved type as an object; type rules are validators over it
- `printers/spite` and the formatter; the tree keeps comments, blank lines and literal spelling; `--final-classes`
- `printers/optimization_report` and `printers/machine_code`
- 64-bit generator (`generators/windows_x64`, the Windows x64 calling convention)
- Low representation in SSA form with basic blocks, and register allocation
- Unit passes and program passes split by input type; every function has a stable identity for cache keys
- Objects live on the heap until a pass proves the frame (replaces copying a returned object into the caller)
- An argument is passed by its parameter's type only, never by where the caller's value came from
- Mortaro confirms or drops D8 to D11 and D17 to D27; D10 (type argument given at run time) contradicts monomorphisation

## Faults found

- A class name that reaches no file is collected in `SymbolTable.unknown_names` and never reported
- The emitter resolves a call whose class is unknown by the function's name alone, when one class has it
- The builder ignores the `singleton` line
- A `load` inside an `if` is refused; the language allows it when the condition reads only build settings
- `whole_library` (a test that reads every class of the library) returns once text and `DynamicLibrary` build
- `DictionaryLiteral` is not lowered
- `WholeNumber.value()` answers 0 for a text that is not a number
- A union switch with repeated case bodies must use `_:`, which lets a member added later slip past a walk

## The language

- The runtime the library needs, as machine code: allocator, console, files, directories, clock, sockets, processes, dynamic library, weak references
- `DynamicLibrary` itself: `open_library`, `find_symbol`, `close_library`
- The memory of a value of any type: `_read_value` and `_write_value`, and a room sized by item count times item size
- Memory: heap, reference counting, frees, and `--debug-memory` counts equal to the original's
- Strings and text literals with holes
- Lists and dictionaries, with their templates and member templates
- References, enums, unions and `type` shapes
- Functions as values, variadics, operators as functions
- `switch`, and narrowing a `T?`
- Every number type, casts, and overflow checks
- Concurrency, reflection, `load` of a package, codegen values
- Program settings: the program's own `build.spite` and `environment.spite`

## The errors

- Every folder of `../SpiteLanguage/diagnostics` is ported to `../SpiteSpec/conformance/<name>` with its exact text, and passes

## The outputs

- `spite program` builds and runs; `--check`, `--build`, `--executable-path`, with the original's error texts for every other flag
- Crash reports and the `<program>.crashes` map
- `--optimization-report`, `--final-classes`
- `--repl`, `--repl-port`, `--hot-reload`, `--development` (see `HOT_RELOAD.md`)
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
