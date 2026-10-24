# TODO

What is left, in order. One line each; delete a line when it is done. The old compiler's rules are in
`../SpiteLanguage/specs`, its optimisations in `../SpiteLanguage/docs/optimizations.md`, its proofs in
`../SpiteLanguage/docs/proofs.md`.

## Architecture (now)

- Rules that need types, after the typed high representation: template walks (built: every row of `specs/control_flow.md` with a member of the element or one of the class's own functions; not built: the `var value = item.m` then `result.append(value)` form of `map_`, a walk over a path or a computed collection, and a function of an attribute, of a local or held in a function value), a condition that is not a Boolean, a `type` holding text or objects at a foreign call (built: a class, and a list of anything but numbers, refused as crossing into C, and what crosses into a callback), codegen value questions (`argument_count`, `function_reflection`, `parameter_write_question`, `returned_text`), a `_:` that answers for nothing, and the rest of level 5 of `../SpiteLanguage/diagnostics`
- Rules that need name resolution (level 4 of `../SpiteLanguage/diagnostics`): a class name that reaches nothing, attributes never read (built: the program's own classes, counting reads in every file's tree and in the built high representation, so walks, `to_debug()` and the JSON writers count; not built: an unread singleton binding in a loaded package, an attribute a program adds by reopening a library class, and a read counted per name rather than per class, so a read of another class's attribute of the same name hides one), reopening rules, the parameters of a function that replaces another (exempt from the unread rule)
- A member template that does not fit its member is refused only for `sum_`, `count_` and `each_` on a library collection (D714) and for `map_` of a Boolean; the other forms are not checked yet
- A comment inside an enum, union or type body is not refused yet (only function bodies have their closing line)
- Mapping rules across roots: a file in one root and a folder of the same dotted name in another (`specs/packages.md`), and the mapping rules for classes of a root loaded after the entry class is read
- The emitter's refusals have no place (`validators/low_intermediary_representation/emittable`): each becomes a validator one level up once the high representation carries places
- Every node carries its file, line and column, from the tree to the instructions
- Unions and enums instead of strings in both representations (instruction kind, operator, types, call owner)
- The formatter's rules that need the tree (D901): a line wider than 120 columns broken one argument per line, the minimum parentheses, `else if` on one line, `{ }` for an empty body, `: Nothing` dropped, `crash false` as `crash`, a single named codegen value written positionally, an enum, union or type body one member per line, a multi-line list without commas; `--final-classes`
- `printers/machine_code`
- Low representation in SSA form; until then a value's register stretches are found per block (D986) but a value no register holds for its whole life is spilled for all of it (D771), unless a scratch register can hold it outside the blocks where it crosses a call (D1011), and copy propagation only crosses a block for a parameter
- Unit passes and program passes split by input type; every function has a stable identity for cache keys
- `--optimization-report` lists every local list and copy as made on the heap (D733), though the low pass now keeps the objects that never leave their function in registers or the frame (D801), and it leaves out an object only because nothing it reads lets that object go (D884): the report does not read what that pass placed
- No range is proved yet, so every whole-number `+`, `-` and `*` keeps its overflow check, and `--optimization-report` lists each one (D733); a `-` in front is not listed
- An argument is passed by its parameter's type only, never by where the caller's value came from
- Mortaro confirms or drops D634 to D637 and D643 to D653; D636 (type argument given at run time) contradicts monomorphisation

- The scheduler's crash lines name the program's frames only where the walk reaches them: a halt inside a `Concurrent`'s state machine prints no `spite.frame` line, since its frame lives on the heap (`concurrent_wait_cycle_in_place`)

## Faults found
- `tests/memory_debug_memory_balance` prints `allocations: 24 frees: 22` under `--debug-memory` (D883): two blocks are never freed, and nothing names them until the leaked-object summary is built

- A serializer's `keys` map (D893) is refused when assigned through an index, but `clear()`, `set_at`, `remove_at` called on it, or a local holding it, change a map whose folded keys stay as they were: a lost write (D244)
- A wider operand of `bits_and`, `bits_or` and `bits_exclusive_or` is refused only in the program's own code: the library's calls are not audited yet (D748)
- A getter or setter called by its bare name inside its own class (`set_rotation(rotation)` in `Matrix4`) is not refused (D752 refuses `point.set_height(4)`), and `equals`, `negate`, `get_at`, `set_at` and the arithmetic functions called by name are not refused yet
- `passed_symbol` (a symbol helper called with a literal) and `lent_arguments` (`streamed_rows` over a helper whose name has no `argument`) have no rule in the spec, so neither is refused
- `conformance/vector_rows` stops first on `'alias' is never read`, an abstract syntax tree rule that runs before any borrow rule can, where it expects the row's resize error (D731)
- `conformance/lent_arguments` stops on `unknown type 'argument.class'` (the reflection walks over a function's arguments, as `tests/reflection_walks`), before its plural-naming error
- A plural template's member is matched with `String`'s `irregulars()` and `uncountables()` as the program reopens them, but a word they leave out is inflected by the compiler's own library rules and irregulars, which a reopened table may have dropped (`foot`)
- A class name that reaches no file is collected in `SymbolTable.unknown_names` and never reported
- The emitter resolves a call whose class is unknown by the function's name alone, when one class has it
- A `load` inside an `if` is refused; the language allows it when the condition reads only build settings
- `WholeNumber.value()` answers 0 for a text that is not a number
- A union switch with repeated case bodies must use `_:`, which lets a member added later slip past a walk

## The language
- `Spite.Call` on a declaration known only at run time (D864): `call()` of a function that takes arguments halts instead of passing the ones `.arguments` holds, and an argument filled there twice or under a name the function lacks is not refused
- A bare call of an operator function inside its own class (`negate()`, which `-this` writes) is not refused yet (D910)
- A call of an operator function by name on a value of a `type` or a union (`item.less_than(other)`) is not refused yet (D907)
- A function value of another object held in a local (`var hurt = troll.hurt`, then `describe(hurt)`) is still looked up by name in its class object's `.functions` (bound to the stand-in, not to `troll`), and halts for the entry class (D866)
- `'<path>' is not a class known while compiling` is given for an attribute typed `Spite.Class` named as a type; a local or a parameter so named is still "unknown type" (D868)
- Templates over `Spite.Attribute` and `Spite.Function`, bound to one object (D798, D815): a parameter of those types is still an ordinary parameter; and `Namespace.classes.each(walker)` unrolls only with a walker of one parameter named in the same class (D813)
- SpiteSpec as the whole specification (D799): one program per rule and corner of every spec page, then the Markdown spec retired
- Fixes instead of errors (D800, to discuss): the layout is fixed (D901); each other rule whose fix needs no choice, such as the declaration order, waits for Mortaro's choice in `mortaros_missing_decisions.md`
- A cycle the program's code does not link as owner and back reference still leaks (D759): two objects stored in each other's attributes where neither was made in that function, one attribute pointing both ways (`partner`), a cycle through a union or a `type`, a non-nullable back attribute, or links made in two different functions; a leak no run reports until `--debug-memory` has its report (D244)
- A back reference is read without a count (D760), so a call on it (`child.parent.leave()`) whose body lets the owner go runs on freed memory, and on two threads the check that its object lives races with the owner's last release
- A `load` of a repository pinned to a commit is refused even when well formed (D839): fetching into `.spite/git/` is not built
- The library and the compiler's generated files break three rules they are exempt from for now (D838): a case of two statements (`Duration.part`), an `if` that only holds an `if` (`ZoneRules.transition_offset_seconds_at`), and `crash` on a value that cannot be null (`Spite.Prompt`, the generated REPL)
- An `assert`/`crash` on a value that cannot be null is refused only on a parameter or an attribute, not on a local; a lone hole in an untyped `var` knows a text only from a local or parameter declared with text (D836); a reopening's attribute type is compared only between two written types or two literals (D840)
- The unread-attribute check counts a read of any attribute of the same name in any class of the program's own folder (reads by name, not per class, D878); in a folder the program loads it checks only singleton bindings, counting reads from that folder
- The spec pages in `../SpiteLanguage/specs` still describe `String.Inflection`, `Weak`, getters by name beside an attribute, and `argument_count` answering 0: update them with D750 to D756

- The runtime the library needs, as machine code: console, files, directories, clock, sockets, processes, dynamic library
- A serializer's `keys` map is folded only when it is written out where it is set (D893): a map made at run time (the spec's key table filled once per attribute) is refused, not built
- Calling a `Spite.Class` known only at run time makes only a class of the program's own folder (D865): a library class (`Integer`, `String`) halts, and `kind()` through an attribute or a member (`argument.class()` on a run-time argument) is not built
- `Color("#ffffff")` with a literal is not specialised per literal: the format tests run at run time unless the lowered program's evaluation (D784) folds the whole call (D807)
- `File.lock()` waits in place: inside a `Concurrent` it does not return to the scheduler while another process holds the lock
- A header's prototype casts each foreign argument to its C type's number (D848), but a prototype written over several lines, or with a `typedef`'d parameter type, is not read, so its arguments pass as written
- `DynamicLibrary.close_library` frees nothing yet; `whole_library` (a test that reads every class of the library) returns once text builds
- `--debug-memory` prints its counts (D883), but not the leaked-object summary by class name, and fresh memory is zeroed, not filled with `0xA5`; the counts a pass proves unneeded are still written
- Chains of member templates as one loop beyond `filter_` and `map_` steps on a `List` (D876, D945: a `filter_` or `find_by_` after a `map_`, a passed function `filter(f)`, a chain on a `Dictionary`'s values or a `Vector`/`Items`, and a last step other than `filter_`, `count_`, `any_`, `all_`, `sum_`, `each_`, `map_`, `find_by_` run step by step; an unfused step's function is still compiled), class filters on a `Dictionary`'s values, the errors of plural, enum value and chained templates (a singular where the plural differs, a member named like an enum value), and the passed-function forms that need an overload by count beyond `count(f)` or a function-level answer type beyond `sum(f)` (`sort_by(f)` by text)
- A dictionary keyed by hashing instead of a walk of its keys
- A function value that answers a nullable number carries its presence only through `CallAt`; reflection on function values (argument names and count)
- `Float` and `Double`: `%`, exponent notation in literals, a `Double` too large for a `Float` halting, and `UnsignedLong` to and from a decimal past 2^63; a decimal too large for a `Long` prints a wrong number in its range-stop message
- Crash reports (D908, D913 to D920): a call the condition may skip (the right side of an `and`, or of an `or` that passed) or one after a read it could change is not reported; a reported call's answer is let go at the end of the function, not after the check; a function holding a `crash` is never inlined, since its report is written in line; halts other than `crash` (overflow, a missing item) and native faults print neither the ring nor the frames; the `.crashes` map gives each part's line only through the site's line (the tree keeps no column per expression); `Color(text)` prints its own `spite:` line naming the text and exits 1 instead of crashing, an `assert` of several parts keeps one site for all of them, the ring allocates its 32 lines as they first fill, a crash line carries no site id, and the map leaves out the asserts in `library/` (D881)
- A number's room is a `Buffer` made on every read of `_buffer` (D659): fold a read at a known position of a fresh room into the number itself

- `Symbol` is text marked as a symbol: `symbol.class` is not yet `Symbol`, `Symbol(text)` finds only the names written in single quotes that were compiled (not the names reflection answers), and `Symbol<T>` outside a template parameter is a symbol whose class is not checked; `Anything`, and `Null` and `Number` as type names outside a `$T ==` test (D661)
- `Build` reads are not folded (only `crash build.<field>` on a Boolean field that is false is refused, D749), so both branches of `if build.serve` are compiled; a `load` under an `if` on a `Build` field
- Arithmetic and functions through `Number` (`value + value` on a `Number`)
- `deep_copy()` of a graph (D724): a class that reaches itself only through a union or a `type` attribute is not seen as one and is copied plainly, so a cycle through one still recurses until the stack runs out; `List.deep_copy()` gives each item a table of its own, so items that hold each other are copied twice; a `Dictionary`, `Items` or `Vector` reached inside a table copy is copied by its own `deep_copy()`, without the table; the table finds a copy by walking its keys (it waits for a hashed `Dictionary`); and a `deep_copy()` through a shape some number, text, enum or singleton fills (refused as not fitting); a walked row declared `var row: $row_type = null` when `$row_type` is a `type`
- Vector and Items keep their items inline: today each write stores a copy of the item by reference (one allocation and one copy per write, and every move inside the library copies again), not its attributes in the block
- Reflection as reopenable library classes (`Spite.Class`, `Spite.Namespace`, `Spite.Function`, `Spite.Attribute`, `Spite.Argument`, `Spite.Access`), filled in by the compiler and folded where constant (D663, D673 to D678): still missing are folding of constant reads (a constant list's `[]`, `filter` and member templates, so `hurt.arguments[1]` needs no run-time check and a filter's predicate runs while compiling, D676; an `each` unrolled over `C.functions` or a known function's `arguments` (D896) still reads each item at run time and checks its name, and it is unrolled only when its walker needs the item known), the `if` on a late answer (`function_waits`, `function_writes_parameter`) dropping its other branch, enums as classes, `Symbol<Spite.Class>` and the `Spite` namespace by name (`class_walk`), stand-ins for singletons, a function value known only at run time answering its `Spite.Function` (a parameter given a function the compiler knows is compiled once for it, and one the compiler knows is looked up by name), `is_stateful` following the singletons a class binds, and a reflection argument other than `Class.attributes['name']` compiled once for its constant (`attribute.class()` and `Spite.Debug<attribute.class>` on an attribute known only at run time)
- A `Parallel`'s reach (`ThreadReach`) follows calls only to the work's own class, attributes and locals made by a constructor; work that never finishes counts as never waiting only when it calls nothing but the console; a locked singleton's lock is taken by every function of its own that reads `this`, and not by another class reading or writing its attributes
- `Parallel` starts a thread of its own for each handle (and `parallel_each_<function>()` one per piece): the thread pool behind it, the race rule of `parallel_each_` as a compile check, and the console's buffer shared by threads that print at once (D662)
- `Concurrent` does not return to the scheduler where a handle it holds is let go while its work runs: a handle, an object or a list holding handles dropped at its scope's end, a handle or an attribute holding one assigned again, and a list of handles cleared all wait in place for the work instead (`waits_never_hang`, `dropped_handle_waits`); file writes block instead of running on a helper thread; a blocking call outside a `Concurrent` (a file read, a socket or console read) always runs on a helper thread and polls the scheduler, even where no `Concurrent` is alive and the spec blocks in place (D721); a thread finds its scheduler loop by its id under a lock instead of through a `ThreadLocal` (D719); `run_ready()` and `resume_only_when_asked()`
- A wait in a frame does not hold the frame: the check that no carried value is written back skips the library's own functions (D717)
- `ForeignCallback` (D725 to D728): the singletons a handed-over function reaches are not made safe for threads yet (only the counts become atomic), the check of what a context callback reaches reads the function's own body and not the functions of its class it calls, and a callback arriving on another thread may reach the scheduler
- A function value passed to one foreign call keeps it in a slot of its call site with the thread that made the call (D726), not a thread-local one, so two threads calling C through one site at once stop the program as if the function had been called on another thread
- `foreign_callbacks` and `ipv6_addresses` still use `Memory.Address` and `Memory.Heap`: rewrite them with `Buffer` when foreign callbacks and sockets come (D662)
- Allocation tests (frame objects, lent buffers, kept buffer addresses, the memory floor) come back as `--debug-memory` counts with the passes that place memory (D661)

## Faults found while porting

- `String.code_at(index)` reads its bytes without testing the index (D244): past the length it answers the zeroed room's 0, and past the room or below 0 whatever memory holds, where `specs/standard_library.md` says `0` out of range (itself a default a caller cannot tell from a real 0)

- A file write (`File.write`, `File.append`, `File.write_bytes`, `File.append_bytes`) answers `function_waits` true (D873) but blocks its thread inside a `Concurrent`: the helper-thread wait for file writes is not built
- `Vector<T>` refuses a class holding a singleton attribute (`Date._time_text`), while `Items<T>` and `is_fixed_size` count it inline: the two answers of "fits a Vector" disagree (D877)

- At the prompt, a singleton the program has not made yet is made when a path names it (`Tick()`), where `specs/repl.md` refuses it: the generated `bind_<n>` constructs it, since nothing reads a singleton's slot without making it (a silent change of the program's state under D244)

- `shape_members` corrupts the heap once a `type`'s function is held as a value and run through `Parallel`: a count is released once too often

- `tests/system` expects `Arguments.get(3)` to answer "" for a missing argument, a default nobody can tell from a real answer (D244): the library stops instead, and the test needs a decision

- The fault handler runs before any library's own exception handling, so a C library that catches its own faults inside a foreign call would be stopped

- `Json` and the old type spellings (`Int`, `Bool`, `LocalDate`...) are refused by name even when the program declares a class of that name
- `items_columns`, `sparse_rows` and `plain_items` stop reading a column after `Items.remove_swapping`

- Class objects are filled from a worklist once compiling ends, but every read of a constant one still reads the run-time object: fold the constant ones while compiling (the 64 MB main stack reserve raised for the nested fills can come back down)
- The study behind `function_waits` (D673) follows a call through a function value only when the compiler knows its function, so a function that waits only behind a function value it is handed answers `false` (a silent wrong answer under D244: answer `true` where it cannot tell, as `docs/proofs.md` says)

- A program can still name a `Spite.Internal` class, or one of the classes the compiler adds (`Spite.Fault`, `Spite.Asserts`, `Spite.CopyTable`, `Spite.Prompt`, `Spite.PromptPath`), in a text, or in a `type` member's or union's written type: only expressions and written types are refused
- The fault and crash reports and the assert ring are Spite source the compiler holds as text (D936): they become low functions writing the site texts from one table of data labels, with `cut` and the value texts as synthetic high functions
- The library breaks three rules it is exempt from for now (D680): singletons bound as locals (`Arguments`, `Environment._setting`, `Spite.Internal.Fault.report`), locals that only copy a path to narrow it (`BinaryCursor._buffer`, `BinaryWriterCursor`, `JsonReader`, `JsonWriter`), and a terminal `if` (`Dictionary.remove_at`)
- The `if` that narrows a path does not record which check narrowed it, so a second check inside its branch is "a condition is a Boolean" instead of "already narrowed by"; `while value` does not narrow its body

- Proofs undone by calls: only a call to the class's own function (the attributes it assigns itself, not through what it calls) and a call on a receiver reached through `[ ]` or a call (what it shrinks through `[ ]`) undo proofs; a call that shrinks a list parameter, a function value, and an undone proof read inside a loop (named by the call) are not followed. Undoing a narrowing made before a loop is refused only for an attribute path, not a name; a check of a `[ ]` read proven by a count or an earlier check is not refused (D695)
- Lost writes: a local holding an item that a program function answers (`lookup.of(0)`, "'found' holds 'values[row]' of 'Column'") and an assignment in the branches of a last `if` or `switch` are not judged; a write is judged only to a local the block made with a constructor, `copy()` or an own function that always answers one
- A decimal `%` is computed as `x - trunc(x / y) * y`, which loses digits once the quotient passes 2^53: compute it exactly, as `fmod` does

- A singleton circle closed at run time halts with the message for one singleton; it should name the chain (`singleton 'Registry' binds 'Catalog', which binds 'Registry'`). The compile-time check follows only a singleton binding another directly, not a circle through an object that is not one (`Metronome` binds a `Tick` that binds `Metronome`)
- A list of `Parallel` handles read with a proven index stops as if the item were missing (`singleton_function_values`)
- `private_walk` crashes the compiler (`class_of` of an unknown class while building a JSON or binary reader of a class with a private union attribute)
- A shape declared inside a class, or in a namespace's own file (`tools/tools.spite`), is not found by its short name (`nearest_type`)
- Two folders making one namespace (`mod/creatures` reopening `package/creatures`) are refused instead of merged (`reopening`, `folder_namesake`)

- `lent_to_calls` stops with heap corruption (0xC0000374): bisect it
- A temporary the builder declares for a comparison (`call() == true`) can be read before its declaration in some branch; plain reads avoid it today

## The errors

- Every folder of `../SpiteLanguage/diagnostics` is ported to `../SpiteSpec/conformance/<name>` with its exact text, and passes

## The outputs

- `spite program` builds and runs (this compiler only builds, so a setting its `Environment` declares is checked and then unused, D842)
- Crash reports
- `--final-classes`
- `--repl-port`, `--hot-reload`, `--development` (see `HOT_RELOAD.md`); check whether the reflection model can be the reload manifest
- `--repl` (D698 to D701): a singleton made with arguments (`Channel(1)`), `bytes <path>` and `memory`, the `not made yet` mark in `classes`, walking `Environment()` and the library's own classes, `eval`, `run`, breakpoints and `reload`
- The runner has no time limit, so a test that hangs stops the whole run; the suite runs tests one at a time: run them in parallel, and make one compile fast enough that a model can iterate on the language test by test
- Caches per step and per unit

## The compiler proves itself

- The programs of `../SpiteLanguage` (conformance, examples, docs) are ported to `../SpiteSpec/tests` and answer the same

## Every optimisation the original does
- Classes specialised by use (D758, D769): one layout per allocation site, following each object to every place it reaches and merging or specialising the code at each meeting point by measured cost (built: one layout per class from the whole program, so an attribute only some objects use is still stored in all of them); an attribute only written is still stored; a member read through a union is never folded to its classes' constants; the functions only a dropped default called are still in the executable
- Shared blocks across classes (D762, D769): built for a member read or written through a union; a class in two unions that place the same member at different offsets keeps the test of the class for one of them, and attributes read together without a union (two systems each taking one class) are not placed alike
- A table rebuilt where it is read (D769) is built at every read, so a function that reads it called from a loop builds it on every call: one constant table built once needs objects whose counts never free them

### The tree shaking and the compile-time questions

- Deciding conditions at compile time
- Reflection, symbols and registries only where read
- Reflection on constants folds and unrolls
- Template chains run as one loop
- A function taking a `type` is compiled per class
- A test against a value a list never holds is decided while compiling
- A table filled once is read as constants
- Maths on constants is worked out while compiling (built: whole numbers in the high representation, and every call, decimal operation and maths function on constants in the lowered program, D784; not built: the evaluator follows a block and the blocks only it leads to (D941) and knows only the objects they made, so a constant list filled before a loop is unknown inside the loop, and an object made in another function or held by a singleton is never known)
- A binary schema is a constant
- Identical functions are folded into one

### The memory, the placement and the copies

- The small-block allocator (D794 to D796) never gives a chunk back to the system and never moves a free block to another size class, so a program's peak of small blocks of one size stays its memory; an allocation of a constant size above 120 bytes, and every free of a block above 1016 bytes, is a call
- The compiler places memory
- Reading an address is one machine operation (`reading_an_address_is_one_machine_operation` is about 50 times expert C: `Base64._encoded`'s values are nearly all spilled, see the register intervals in Architecture, and every `append_code` keeps the buffer's and the text's counts in memory)
- Objects that never leave their function live in the frame (built after inlining, D801: in registers or the frame, made at the `return` when answered, its count followed while compiling, D953; not built: an object whose class has a `drop`, back references or frees its attributes other than by releasing them, an object of a class that releases attributes passed to a call that is not inlined, and anything in a function that waits)
- A local list of known size lives in the frame (built for a literal of whole numbers only counted and read by index, D991; not built: a literal of decimals or objects, one passed to a call that only reads it, and one made with `List()` and a known count of appends)
- A variadic list the callee only reads lives in the caller's frame
- A list held only by another list lives in its slot
- A list of lists filled again keeps each list's room
- Objects of one class sit together (built: a list of a class of numbers, filled only with fresh objects and read back, holds its objects inside its storage, D994, and one array per attribute with no header when no item is handed whole to a function of its class, D998; not built: the header dropped for a list whose items are handed to the class's functions, elements holding text, decimals or objects, and objects of one class outside a list)
- A row of borrowed items lives in the frame (built when the function it is passed to is inlined, D801, D942: the row is registers; a row passed to a call too large to inline is still made on the heap, and the items it holds are still counted when it is made and let go when it ends)
- An `Items`' storage is chosen while compiling
- A deep copy is written per class, with a table only where a graph needs one
- An object attribute only its holder ever holds lives inside the holder (built for a class of plain numbers written only by the defaults or a constructor with a new object and read only for its parts, D1034; not built: a held class with objects or texts in it (`Order.customer`), a holder copied by `copy()` or `deep_copy()`, a part passed to a function, and a list's objects in its storage holding such attributes)
- A loop that sums a list filtered by its counter on every pass is one pass over the list (`report_over_records`' 64 profits)
- An if-converted body may hold a checked product or difference when ranges prove it fits, and decimals; the generator writes its picks as `cmov` instead of masks (D996)
- A deep copy nothing changes is the original
- Copies that cost nothing (built for a copy of a plain object that never leaves the function, once `copy()` is inlined, D801; not built: a copy kept or passed on, and a copy nothing changes being the original)
- Allocation is the C library's, counted only where read

### The counts

- Singletons: made on first use, never counted (built: a singleton passed to a call is not counted, a function answering a singleton (a rebuilt attribute among them) neither counts it nor has its caller let it go, D949, and an attribute holding a quiet singleton is the singleton itself, D954; not built: kept in a local or a list it still is, and so is an attribute in a program with a `drop()`; a singleton the entry class makes is never tested again outside what its defaults reach (D961), and a quiet one read in a loop is tested once before it (D967), but the first-use test of any other singleton read in a loop is made on every pass)
- Singletons that hold nothing are static objects
- Atomic reference counts only with threads
- Plain reference counts where no thread reaches a class
- An item passed to a call that cannot change its list is not counted (built for the receiver of a call after a `crash` that proves the read, D957; not built: an argument, and a read whose index or call arguments are not plain reads)
- A singleton's attribute that never changes is read in place
- A list's templates read its elements without counting them: done where nothing after the read in the template can write a list of that class; a template handed a function value still counts when any function the program takes as a value could write one
- An item written back to its own slot is not written (built for `list[index] = name` after `var name = list[index]` proven in the same block, D1033; not built: a write-back from another block, or of a name that is counted)
- `a_list_held_only_by_another_list_lives_in_its_slot` runs about 9% slower since `append` stores into the empty slot past the end without the load and comparison it made before (D1032): fewer instructions, so the cause is in the generated loop's layout, not yet found
- Who holds an object is decided while compiling (built: a parameter a function keeps on its one read is handed its count, and a local is handed to what keeps it at its last read, D1031; a slot a constructor's defaults leave empty is stored without reading it, D1032; not built: a borrow kept in an attribute across calls (`Desk.open` in `a_write_back_of_what_the_slot_already_holds_is_not_written`), a borrow of an attribute or slot across a loop, objects laid inside their one holder, and classes with a `drop()` in what they hold)
- A list item read only to test it is not counted (built for `is present` on a `List` or `Vector`, D947; not built: a read tested by another comparison than presence, and `Items`)
- A write-back of what the slot already holds is not written
- An item a name holds from its list is not counted
- Reading through a `type` without counting (built for a row placed in registers whose reads meet their releases on one path, D951 to D953; not built: a row passed to a call too large to inline, and a count taken before a call that is not inlined)
- Objects made for their owner are told apart
- Counts stay plain for what one of the calls run at once counts

### The text, the numbers and the collections

- Short text lives inside the `String` (D789): a text whose `String` keeps other attributes is still two allocations
- A slice shares its source's bytes where the source outlives it and neither changes (texts can change in place through `append_code` and an append, so it needs that proven first)
- `List.join` copies every `String` item with `to_string()` before it appends it, one allocation per item that an append of the item itself would not need
- Short symbols are inline text
- A foreign name is never copied
- Crash text out of the binary
- A number's bits are read in place (built for a read at offset 0 of the number's own width, D786, D791 and D805; not built: a read of part of a number's bytes, or at another offset)
- A decimal literal beside a `Float` is a `Float` (built: the literal is a `Float` and decimals live in decimal registers, D971; not built: a sum of decimals in a loop is never reassociated or vectorised, which needs a proof that every partial sum is exact, so `a_decimal_literal_beside_a_float_is_a_float` waits on one addition after another, about 16 times expert C)
- Arithmetic is checked in every build
- Arithmetic a range proves is not checked (built in `building/ranges.spite`; not built: a total that adds at most one term a pass, a counter stepped down under `>` or `>=`, a loop local other than a counter keeping the range of what it is assigned, a `-` in front reported as a negation)
- A loop over plain values reads its count once and its items unchecked (built: the count and the storage read once before the loop when it writes only number items, and the bound test dropped under the loop's own signed test, D972, D973; not built: a `set_at` into another list still tests that list's count each pass, and the loop is never vectorised nor fused with the next loop over the same list)
- A proven read tests only its bounds (built for a library `List` of numbers or objects; not built: `Vector`, `Items`, a list of `T?` items, unions or function values)
- A walked `crash` line's read is the row's read
- Boxing only where a value travels as a shape
- A function value describes its arguments when asked
- Defaults the constructor replaces are never made: done for a quiet default the constructor assigns before reading it; a default some other making (a deep copy, a reader) overwrites is still made
- Proofs that survive a call

### The threads

- The small-block allocator (D794 to D796) has no inline fast path in a program with threads (every allocation and free there is a call), and a thread's lists are found through a thread slot where a `Parallel`'s own block could hand them over
- Concurrency machinery only where it is used
- Hidden async/await as compile-time state machines
- Reads in a row overlap
- The thread pool only where a `Parallel` is made
- Thread safety for singletons, the cheapest safe form (built: unreached, never changing, atomic and locked, D780 to D783): a read or write of a locked singleton's attribute from another class takes no lock yet
- A singleton no other thread reaches takes no lock: the walk is made only from what a `Parallel` starts, not again over the tree-shaken program
- A singleton's reading functions do not exclude each other: a counted loop of reads shares the lock (D988), but a single read outside such a loop still takes it alone
- An attribute read only under its singleton's lock is a plain number
- A loop of calls to one singleton tests for tasks once
- Thread safety for singletons, the rest of the plan
- Calls in a row run at once
- A loop over a list of different classes runs them at once
- A loop whose passes write only their own item runs in bands (built for `each_` on a `List` of a class of the program, D975; not built: a `Vector`, a `filter_` chain before it, a pass that calls a member of another object or of a number, and a pool of threads kept between loops (each band starts a thread; a counted loop of one banded pass starts them once, D978, but any other loop starts them on every pass))

### The compiler's own machinery

- REPL, live reload and debug machinery only in those builds
- A reload compiles only the classes that changed
- What a `--hot-reload` build carries so its objects can move
- The fault handler is in every program
- A crash's report is kept out of the way
- Smaller ones
- Other optimisations

### The machine code (D771 to D775 are built)

- Loop-invariant code motion (built, D803, D962, D973): a load without a region moves before its loop only from the loop's first block and only when nothing in the loop writes memory or calls (a load known never to change moves from anywhere); a load with a region moves from any block every pass runs when every write in the loop has another region; anything in a loop that calls is still made on every pass
- In a program with threads a load moves out of a loop only when the compiler knows it never changes or no other thread touches its class (D968, D973): a load without a region (a worker's local list) is still made on every pass
- Assigning a fresh empty `List()` to a slot whose old list nothing else holds (count 1, proven or tested once) clears the old list in place and keeps its room (D969); not built (the `clear()` of a list of lists followed by a loop appending new empty lists is, D981, but nothing else between them, and not a list of `Vector`s or `Dictionary`s)
- An attribute a loop updates is kept in a register (D966, D974) only when every access in the loop carries its region and the loop calls and allocates nothing: an access through a union, a shape or a type parameter, or any call (a buffer's growth on a cold path) keeps every attribute in memory; in a program with threads only a locked singleton's attributes and those of a class no other thread touches are kept
- Decimals live in decimal registers (built, D971): a decimal load or store still passes through `rax`, a decimal constant is moved in from an immediate rather than read from the program's data, and `==` or `!=` of decimals still makes its answer before the branch
- Common subexpressions across blocks only for registers written once (D803): a computation over a register written twice (a loop counter) is still made again in a later block, and a repeated comparison is made again
- An unsigned 64-bit division by a constant that is not a power of two keeps the `div` (D804)
- A function inlined into a loop keeps its bounds checks (ranges are proved before inlining), and a callee of more than 40 instructions, or that waits, is called (D802) unless the call is in a loop and passed an object the caller made (up to 128, D983); inlining is chosen by size alone, with no estimate of the registers a loop then needs
- A division and a remainder of the same two numbers are two divisions, not one `idiv`
- A value is split only around the blocks where it crosses a call, and only into a scratch register (D1011): a value live across a hot loop it barely uses still holds a kept register there, a value the loop needs is not moved into it from the slot at the loop's edge, and loads are never rematerialised
- An object let go unread is never made (D984) only when nothing but its class and count is written into it and its class frees nothing but its memory: a default object with attributes, or one holding objects, is still made and freed
- An object read from a steady load is not counted (D985) only when every register holding it is written by that load or copies of it: a local that may hold either a steady object or another one is counted
- Loops are not rotated (each pass jumps back to the test at the top)
- Live-range splitting is not built: a value spilled anywhere is spilled across every loop it lives in, and a value live across a call takes a kept register for its whole life
- A slot a loop assigns from a list's items is counted on every pass (the write-back case's `Desk.open`): counting it once around the loop needs a proof that the list keeps each item while the slot holds it

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
- A divisor written as zero is an error
- Arithmetic that does not fit halts
- A range proves arithmetic fits (built, D768; not built: the totals, the counters stepped down, and the loop locals other than counters, see the optimisation's line)
- A wider operand is written first
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
- Local and variadic lists in the frame (built: a literal of whole numbers only counted and read by index, D991)
- A function value its callee only calls lives in the frame

### Borrowing and lending

- Borrowed items of a `Vector` or `Items` (built as refusals, D729, in `building/borrows.spite`: kept in an attribute, put in a list, returned, made a function value, given a second name, assigned again, borrowed from a collection nothing keeps; not built: the reads stay counted references, so nothing is uncounted yet, a member template's `get_at(...)` on its own collection is not seen as borrowed, and nothing is checked inside a walk copy)
- No borrowed read past a resize (built as a refusal, D730, followed through the program's calls, a `type`'s fillers, `print`'s `to_string`s and text holes; not built: the library's own functions are not followed, so a library function handed a function value that it calls (`each`) is followed only when the value names a function, and a value of unknown type fans out to every function of the name)
- Rows of borrowed items (built: a literal row and a walked row are refused when a call they are passed to may resize what they borrow from, and are never kept, returned, listed, aliased or assigned; not built: the row in the frame, the `___lent_<positions>` copy that compiles the callee under the rules, the error for a non-plain attribute of a literal row, and the arguments a plural fills)
- An item lent to the caller (built: a `return` of a singleton's `Vector` or fitting `Items` item lends, with `fits_vector()` and `$T == X` folded, and the caller's name is borrowed; not built: the uncounted return, the refusal of a lending function used as a value or through a `type`, of a non-item return beside a lent one, and of a reused name)
- An item lent to a call (built: a call lent a borrowed item is refused when it may resize its collection; not built: the `___lent_` copy that compiles the callee under the rules, so a callee keeping a lent item is not refused, and the errors for lending to a library function, a union parameter or an unnamed expression)
- A list element lent to a row
- An argument its caller holds is passed uncounted
- An attribute a call cannot assign is passed uncounted
- A singleton attribute that never changes is read in place
- A list's templates read their elements uncounted
- An item written back to its own slot is the slot
- A value followed through calls is the slot it was read from
- An item a name holds from its list is not counted (built for `var item = list[index]` with a proven read when nothing after it in its block can write the slot, D992; not built: a name kept across a call that may write any list of the item's class, even another one)
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
- A function that touches no changing state takes no lock
- Reading functions share the lock
- A loop that starts no task tests for tasks once
- No attribute is read past the lock
- A lock that would wait forever is an error
- A loop that can never end is an error
- A poll that nothing steps is an error
- A write to an object only this function holds must be read
- A name read from a list, assigned and never read, is an error
- What a `Parallel` may reach
- Which calls suspend a `Concurrent`

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
