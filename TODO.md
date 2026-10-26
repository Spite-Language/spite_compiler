# TODO

What is left, in order. One line each; delete a line when it is done. The old compiler's rules are in
[the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/README.md), its optimisations in [`optimizations.md`](https://github.com/Spite-Language/spite_documentation/blob/master/optimizations.md), its proofs in
[`proofs.md`](https://github.com/Spite-Language/spite_documentation/blob/master/proofs.md).

## Architecture (now)

- Rules that need types, after the typed high representation: template walks (built: every row of `specs/control_flow.md` with a member of the element or one of the class's own functions; not built: the `var value = item.m` then `result.append(value)` form of `map_`, a walk over a path or a computed collection, and a function of an attribute, of a local or held in a function value), a condition that is not a Boolean, a `type` holding text or objects at a foreign call (built: a class, and a list of anything but numbers, refused as crossing into C, and what crosses into a callback), codegen value questions (`argument_count`, `function_reflection`, `parameter_write_question`, `returned_text`), a `_:` that answers for nothing, and the rest of level 5 of the old compiler's diagnostic programs
- Rules that need name resolution (level 4 of the old compiler's diagnostic programs): a class name that reaches nothing, attributes never read (built: the program's own classes, counting reads in every file's tree and in the built high representation, so walks, `to_debug()` and the JSON writers count; not built: an unread singleton binding in a loaded package, an attribute a program adds by reopening a library class, and a read counted per name rather than per class, so a read of another class's attribute of the same name hides one), reopening rules, the parameters of a function that replaces another (exempt from the unread rule)
- A member template that does not fit its member is refused only for `sum_`, `count_` and `each_` on a library collection (D714) and for `map_` of a Boolean; the other forms are not checked yet
- A comment inside an enum, union or type body is not refused yet (only function bodies have their closing line)
- Mapping rules across roots: a file in one root and a folder of the same dotted name in another (`specs/packages.md`), and the mapping rules for classes of a root loaded after the entry class is read
- The emitter's refusals have no place (`validators/low_intermediary_representation/emittable`): each becomes a validator one level up once the high representation carries places
- Every node carries its file, line and column, from the tree to the instructions
- Unions and enums instead of strings in both representations (instruction kind, operator, types, call owner)
- The formatter's rules that need the tree (D901): a line wider than 120 columns broken one argument per line, the minimum parentheses, `else if` on one line, `{ }` for an empty body, `: Nothing` dropped, `crash false` as `crash`, a single named codegen value written positionally, an enum, union or type body one member per line, a multi-line list without commas; `--final-classes`
- `printers/machine_code`
- Low representation in SSA form; until then a value's register stretches are found per block (D986) but a value no register holds for its whole life is spilled for all of it (D771), unless a scratch register can hold it outside the blocks where it crosses a call (D1011), and copy propagation only crosses a block for a parameter
- Every function has a stable identity for cache keys
- Every high-level optimisation is its own pass (D1087, D1096, D1151): a list of lists renewed in place (`_renew_lists`) and a serializer's folded keys are still chosen while building; the weights of a banded pass and the values a folded dictionary holds are proven inside their passes, not in `proofs/`
- `--optimization-report` lists every local list and copy as made on the heap (D733), though the low pass now keeps the objects that never leave their function in registers or the frame (D801), and it leaves out an object only because nothing it reads lets that object go (D884): the report does not read what that pass placed
- No range is proved yet, so every whole-number `+`, `-` and `*` keeps its overflow check, and `--optimization-report` lists each one (D733); a `-` in front is not listed
- An argument is passed by its parameter's type only, never by where the caller's value came from
- Mortaro confirms or drops D634 to D637 and D643 to D653; D636 (type argument given at run time) contradicts monomorphisation

- The scheduler's crash lines name the program's frames only where the walk reaches them: a halt inside a `Concurrent`'s state machine prints no `spite.frame` line, since its frame lives on the heap (`concurrent_wait_cycle_in_place`)

## Faults found
- A class that reaches itself only through a `type` attribute gets no copy table (`uses_a_table` in `building/copying.spite` follows object attributes and the classes of a union, D1252), so its `deep_copy()` recurses around a cycle through one until the stack overflows (D244)

- A serializer's `keys` map (D893, D1204) is refused when changed through an index, `set_at`, `remove_at`, `clear` or a local holding it, but not when it is passed to a function that changes it: a lost write (D244)
- A wider operand of `bits_and`, `bits_or` and `bits_exclusive_or` is refused only in the program's own code: the library's calls are not audited yet (D748)
- A getter or setter called by its bare name inside its own class (`set_rotation(rotation)` in `Matrix4`) is not refused (D752 refuses `point.set_height(4)`), and `equals`, `negate`, `get_at`, `set_at` and the arithmetic functions called by name are not refused yet
- `passed_symbol` (a symbol helper called with a literal) and `lent_arguments` (`streamed_rows` over a helper whose name has no `argument`) have no rule in the spec, so neither is refused
- A plural template's member is matched with `String`'s `irregulars()` and `uncountables()` as the program reopens them, but a word they leave out is inflected by the compiler's own library rules and irregulars, which a reopened table may have dropped (`foot`)
- A union switch with repeated case bodies must use `_:`, which lets a member added later slip past a walk
- Leaks `--debug-memory` cannot be asked about: a reflection object made on two threads at once records itself on the list let go at exit without a lock

## The language
- `Spite.Call` on a declaration known only at run time (D864, D1271): an argument filled twice is not refused (the second write replaces the first), an argument the function lacks halts only as "fills an argument ... does not have" without naming it, and a parameter that is nullable, a union or a `type` halts instead of being passed
- A function value of another object held in a local (`var roar = troll.roar`, then `run(roar)`) is still looked up by name in its class object's `.functions`, bound to the stand-in and not to `troll`, so its `call_function()` runs on the stand-in (D866): describing it in place, bound to its object, loses its `accesses`, which are filled only after the program's functions are built
- Templates over `Spite.Attribute` and `Spite.Function`, bound to one object (D798, D815): a parameter of those types is still an ordinary parameter; and `Namespace.classes.each(walker)` unrolls only with a walker of one parameter named in the same class (D813)
- spite_spec as the whole specification (D799): one program per rule and corner of every spec page, then the Markdown spec retired
- Fixes instead of errors (D800, to discuss): the layout is fixed (D901); each other rule whose fix needs no choice, such as the declaration order, waits for Mortaro's choice in `mortaros_missing_decisions.md`
- A cycle the program's code does not link as owner and back reference still leaks (D759): two objects stored in each other's attributes where neither was made in that function, one attribute pointing both ways (`partner`), a cycle through a union or a `type`, a non-nullable back attribute, or links made in two different functions; a leak no run reports until `--debug-memory` has its report (D244)
- A back reference is read without a count (D760), so a call on it (`child.parent.leave()`) whose body lets the owner go runs on freed memory, and on two threads the check that its object lives races with the owner's last release
- A pinned `load` is fetched (D839, D1270), but a copy is not checked again against its `<commit>.files`, which lists each file's size and not the two hashes and modification times the spec asks; a URL git cannot clone is refused without git's own first line; a relative pin inside a fetched package is resolved from the copy, not from the repository it came from; and two versions of one repository are read as one
- The compiler's generated files (the REPL's `Spite.Prompt`, the copy table) are still exempt from three rules (D838, D1274): a case of two statements, an `if` that only holds an `if`, and `crash` on a value that cannot be null
- A lone hole in an untyped `var` knows a text only from a local or parameter declared with text (D836); a reopening's attribute type is compared only between two written types or two literals (D840)
- A `load` of a repository pinned to a commit is refused even when well formed (D839): fetching into `.spite/git/` is not built
- The library and the compiler's generated files break three rules they are exempt from for now (D838): a case of two statements (`Duration.part`), an `if` that only holds an `if` (`ZoneRules.transition_offset_seconds_at`), and `crash` on a value that cannot be null (`Spite.Prompt`, the generated REPL)
- An `assert`/`crash` on a value that cannot be null is refused only on a parameter or an attribute, not on a local; a lone hole in an untyped `var` knows a text only from a local or parameter declared with text (D836); a reopening's attribute type is compared only between two written types or two literals (D840)
- The unread-attribute check counts a read of any attribute of the same name in any class of the program's own folder (reads by name, not per class, D878); in a folder the program loads it checks only singleton bindings, counting reads from that folder
- The spec pages in [the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/README.md) still describe `String.Inflection`, `Weak`, getters by name beside an attribute, and `argument_count` answering 0: update them with D750 to D756

- The runtime the library needs, as machine code: console, files, directories, clock, sockets, processes, dynamic library
- A serializer's `keys` map is folded only when it is written out where it is set (D893): a map made at run time (the spec's key table filled once per attribute) is refused, not built
- Calling a `Spite.Class` known only at run time makes a class of the program's own folder, a number, a `Boolean` or a `String` (D865, D1272): any other library class halts, and `kind()` through an attribute or a member (`argument.class()` on a run-time argument) is not built
- `Color("#ffffff")` with a literal is not specialised per literal: the format tests run at run time unless the lowered program's evaluation (D784) folds the whole call (D807)
- `File.lock()` waits in place: inside a `Concurrent` it does not return to the scheduler while another process holds the lock
- A header's prototype casts each foreign argument to its C type's number (D848), but a prototype written over several lines, or with a `typedef`'d parameter type, is not read, so its arguments pass as written
- `DynamicLibrary.close_library` frees nothing yet; `whole_library` (a test that reads every class of the library) returns once text builds
- `--debug-memory` (D883, D1242): fresh memory is zero, not `0xA5`, since the generated code relies on zeroed memory (a text's end byte, a `Buffer`'s inline room): write those zeros explicitly, then fill; an object the compile-time evaluation writes out whole is counted but not named in the leaked-object summary; the counts a pass proves unneeded are still written
- `whole_library` (a test that reads every class of the library) returns once text builds
- `--debug-memory` prints its counts (D883), but not the leaked-object summary by class name, and fresh memory is zeroed, not filled with `0xA5`; the counts a pass proves unneeded are still written
- Chains of member templates as one loop beyond `filter_` and `map_` steps on a `List` (D876, D945: a `filter_` or `find_by_` after a `map_`, a passed function `filter(f)`, a chain on a `Dictionary`'s values or an `Items`, and a last step other than `filter_`, `count_`, `any_`, `all_`, `sum_`, `each_`, `map_`, `find_by_` run step by step; an unfused step's function is still compiled), class filters on a `Dictionary`'s values, the errors of plural, enum value and chained templates (a singular where the plural differs, a member named like an enum value), and the passed-function forms that need an overload by count beyond `count(f)` or a function-level answer type beyond `sum(f)` (`sort_by(f)` by text)
- A function value that answers a nullable number carries its presence only through `CallAt`; reflection on function values (argument names and count)
- A decimal too large for a `Long` prints a wrong number in its range-stop message
- Crash reports (D908, D913 to D920): a call the condition may skip (the right side of an `and`, or of an `or` that passed) or one after a read it could change is not reported; a reported call's answer is let go at the end of the function, not after the check; a function holding a `crash` is never inlined, since its report is written in line; halts other than `crash` (overflow, a missing item) and native faults print neither the ring nor the frames; the `.crashes` map gives each part's line only through the site's line (the tree keeps no column per expression); `Color(text)` prints its own `spite:` line naming the text and exits 1 instead of crashing, an `assert` of several parts keeps one site for all of them, the ring allocates its 32 lines as they first fill, a crash line carries no site id, and the map leaves out the asserts in `library/` (D881)
- A number's room is a `Buffer` made on every read of `_buffer` (D659): fold a read at a known position of a fresh room into the number itself

- `Symbol` is text marked as a symbol: `symbol.class` is not yet `Symbol`, `Symbol(text)` finds only the names written in single quotes that were compiled (not the names reflection answers), and `Symbol<T>` outside a template parameter is a symbol whose class is not checked; `Anything`, and `Null` and `Number` as type names outside a `$T ==` test (D661)
- A `Build` field whose default is not a literal is read from the singleton while the program runs (D1273); the reads of the compiler's own options are not kept constant in a `--hot-reload` build, as the spec asks
- A value typed `Number` (D1277) answers only the operators, `to_long()` and `to_double()`, by the number class it holds; its other functions, and a `Number` filled by a program's own class, halt or are refused
- `deep_copy()` of a graph (D724): a class that reaches itself only through a union or a `type` attribute is not seen as one and is copied plainly, so a cycle through one still recurses until the stack runs out; `List.deep_copy()` gives each item a table of its own, so items that hold each other are copied twice; a `Dictionary`, `Items` or `Vector` reached inside a table copy is copied by its own `deep_copy()`, without the table; and a `deep_copy()` through a shape some number, text, enum or singleton fills (refused as not fitting); a walked row declared `var row: $row_type = null` when `$row_type` is a `type`
- `Build` reads are not folded (only `crash build.<field>` on a Boolean field that is false is refused, D749), so both branches of `if build.serve` are compiled; a `load` under an `if` on a `Build` field
- Arithmetic and functions through `Number` (`value + value` on a `Number`)
- `deep_copy()` of a graph (D724): a class that reaches itself only through a `type` attribute is not seen as one and is copied plainly, so a cycle through one still recurses until the stack runs out; `List.deep_copy()` gives each item a table of its own, so items that hold each other are copied twice; a `Dictionary`, `Items` or `Vector` reached inside a table copy is copied by its own `deep_copy()`, without the table; the table finds a copy by walking its keys (it waits for a hashed `Dictionary`); and a `deep_copy()` through a shape some number, text, enum or singleton fills (refused as not fitting); a walked row declared `var row: $row_type = null` when `$row_type` is a `type`
- Vector and Items keep their items inline: today each write stores a copy of the item by reference (one allocation and one copy per write, and every move inside the library copies again), not its attributes in the block
- Reflection as reopenable library classes (`Spite.Class`, `Spite.Namespace`, `Spite.Function`, `Spite.Attribute`, `Spite.Argument`, `Spite.Access`), filled in by the compiler and folded where constant (D663, D673 to D678): still missing are folding of constant reads (a constant list's `[]`, `filter` and member templates, so `hurt.arguments[1]` needs no run-time check and a filter's predicate runs while compiling, D676; an `each` unrolled over `C.functions` or a known function's `arguments` (D896) still reads each item at run time and checks its name, and it is unrolled only when its walker needs the item known), the `if` on a late answer (`function_waits`, `function_writes_parameter`) dropping its other branch, enums as classes, `Symbol<Spite.Class>` and the `Spite` namespace by name (`class_walk`), stand-ins for singletons, a function value known only at run time answering its `Spite.Function` (a parameter given a function the compiler knows is compiled once for it, and one the compiler knows is looked up by name), `is_stateful` following the singletons a class binds, and a reflection argument other than `Class.attributes['name']` compiled once for its constant (`attribute.class()` and `Spite.Debug<attribute.class>` on an attribute known only at run time)
- A `Parallel`'s reach (`ThreadReach`) does not follow a call through a function value, a `type` or a union (D1289); work that never finishes counts as never waiting only when it calls nothing but the console; a locked singleton's lock is taken by every function of its own that reads `this`
- The race rule of `parallel_each_` as a compile check (D662)
- A blocking call outside a `Concurrent` (a file read or write, a socket or console read, a file lock) always runs on a helper thread and polls the scheduler, even where no `Concurrent` is alive and the spec blocks in place (D721, D1288); a thread finds its scheduler loop by its id under a lock instead of through a thread slot (D719); `run_ready()` and `resume_only_when_asked()`
- `ForeignCallback` (D725 to D728): the check of what a context callback reaches reads the function's own body and not the functions of its class it calls, and a callback arriving on another thread may reach the scheduler
- Allocation tests (frame objects, lent buffers, kept buffer addresses, the memory floor) come back as `--debug-memory` counts with the passes that place memory (D661)

## Faults found while porting


- `Vector<T>` refuses a class holding a singleton attribute (`Date._time_text`), while `Items<T>` and `is_fixed_size` count it inline: the two answers of "fits a Vector" disagree (D877)




- The fault handler runs before any library's own exception handling, so a C library that catches its own faults inside a foreign call would be stopped


- Class objects are filled from a worklist once compiling ends, but every read of a constant one still reads the run-time object: fold the constant ones while compiling (the 64 MB main stack reserve raised for the nested fills can come back down)

- A program can still name a `Spite.Internal` class, or one of the classes the compiler adds (`Spite.Fault`, `Spite.Asserts`, `Spite.CopyTable`, `Spite.Prompt`, `Spite.PromptPath`), in a text, or in a `type` member's or union's written type: only expressions and written types are refused
- The fault and crash reports and the assert ring are Spite source the compiler holds as text (D936): they become low functions writing the site texts from one table of data labels, with `cut` and the value texts as synthetic high functions
- The library breaks three rules it is exempt from for now (D680): singletons bound as locals (`Arguments`, `Environment._setting`, `Spite.Internal.Fault.report`), locals that only copy a path to narrow it (`BinaryCursor._buffer`, `BinaryWriterCursor`, `JsonReader`, `JsonWriter`), and a terminal `if` (`Dictionary.remove_at`)

- Lost writes: a local holding an item that a program function answers (`lookup.of(0)`, "'found' holds 'values[row]' of 'Column'") and an assignment in the branches of a last `if` or `switch` are not judged; a write is judged only to a local the block made with a constructor, `copy()` or an own function that always answers one

- A singleton circle closed at run time halts with the message for one singleton; it should name the chain (`singleton 'Registry' binds 'Catalog', which binds 'Registry'`). The compile-time check follows only a singleton binding another directly, not a circle through an object that is not one (`Metronome` binds a `Tick` that binds `Metronome`)

- A temporary the builder declares for a comparison (`call() == true`) can be read before its declaration in some branch; plain reads avoid it today

## The outputs

- Crash reports
- `--final-classes` (D1223, D1389): the printed folder does not run as the same program yet: compiling it stops at the first class the compiler writes for itself (`spite/copy_table.spite`, `Spite.CopyTable` is internal to the standard library), the library's classes are printed beside the program as reopenings of the library its moved `load` still reads, and the generic templates its code names are not printed (only their instantiations, as `type`s); a class the compiler makes without a file is printed as a `type`, not as code that compiles
- `--repl-port`; `--hot-reload` is refused until it swaps code (D1241): every part of `HOT_RELOAD.md` (slots, the reload library, the manifest, the file hashes, the watcher, moving live objects, `Reload` filled by each swap) is to build, and whether the reflection model can be the manifest
- `--repl` (D698 to D701): a singleton made with arguments (`Channel(1)`), `bytes <path>`, the `not made yet` mark in `classes`, walking `Environment()` and the library's own classes, `eval`, `run`, breakpoints and `reload`
- `--hot-reload`, `--development` (see `HOT_RELOAD.md`); check whether the reflection model can be the reload manifest
- `--repl-port` (D1236): a command is answered only at a loop's check point and after the constructor returns, not where the program waits (`Program.sleep`, `Console.read_line`, a `File` or `Socket` call, a `Concurrent`'s value); a check point asks a flag a thread raises every 25 ms, not the REPL thread's handover, so an answer waits up to 25 ms, and a remote `exit` ends the program at the first check point that runs after it (D1388), up to 25 ms after the next pass
- `--repl` (D698 to D701, D1234, D1235, D1237): `eval`, `run`, breakpoints, `reload`, `last_reload`, `wait_reload` and a construction on the right of `=` only answer their refusal, since they need the `--hot-reload` machinery
- Caches per step and per unit

## The compiler proves itself

- The programs of the old compiler's repository (conformance, examples, docs) are ported to `tests` of [spite_spec](https://github.com/Spite-Language/spite_spec) and answer the same

## Every optimisation the original does
- Classes specialised by use (D758, D769): one layout per allocation site, following each object to every place it reaches and merging or specialising the code at each meeting point by measured cost (built: one layout per class from the whole program, so an attribute only some objects use is still stored in all of them); an attribute only written is still stored; a member read through a union is never folded to its classes' constants; the functions only a dropped default called are still in the executable
- Shared blocks across classes (D762, D769): built for a member read or written through a union; a class in two unions that place the same member at different offsets keeps the test of the class for one of them, and attributes read together without a union (two systems each taking one class) are not placed alike
- A table rebuilt where it is read (D769) is built at every read, so a function that reads it called from a loop builds it on every call: one constant table built once needs objects whose counts never free them

### The tree shaking and the compile-time questions

- Deciding conditions at compile time (measured 2026-10-25: 12.7 ms against the old compiler's 11.9)
- Reflection, symbols and registries only where read
- Reflection on constants folds and unrolls (measured 2026-10-25: 19.8 ms against the old compiler's 12.2: the walk is unrolled, the `Stats` objects are still on the heap and read one by one)
- Template chains run as one loop (built as the high pass `fused_chains`, D1151; not built: a `filter_` or `find_by_` after a `map_`, a passed function, chains on a `Dictionary`'s values or `Items`); a class whose objects only a dropped step made keeps its layout and defaults (D1153)
- A function taking a `type` is compiled per class (built once the function is inlined: the class of an object made in the caller is known, D1053; not built: a call not inlined still boxes a number and tests the class at run time, and the loop's four `Double` sums wait on one another, 78 ms against the old compiler's 51)
- A test against a value a list never holds is decided while compiling (measured 2026-10-25: 28.4 ms against the old compiler's 26.8; needs the proof "a list only its class fills holds only what it fills")
- A table filled once is read as constants (built for an object its own function makes, or a call run while compiling makes, followed through every path and loop, D1041, D1042; not built: an object a singleton holds, made in another function, is never known, so a table a singleton fills once is read at run time)
- Maths on constants is worked out while compiling (built: whole numbers in the high representation, and every call, decimal operation and maths function on constants in the lowered program, D784, followed through every path and loop of a function, D1041; not built: a call is run on at most 100 000 instructions (D1047), so a whole case over a hundred thousand points is not answered while compiling, and an object a singleton holds is never known)
- The whole-function evaluation (D1041 to D1046) makes three cases slower than before it: `the_thread_pool_only_where_a_parallel_is_made` 8.7 to 11.1 ms, `a_crashs_report_is_kept_out_of_the_way` 23.5 to 27.3 ms, `copies_that_cost_nothing` 48.9 to 53.1 ms; find which rewrite (an unrolled loop, a constant written before its instruction) costs them and keep it out there
- A call is copied for its known arguments only when it passes a known closure (D1043): a callee given known numbers or a known object without a function in it is not copied, and a loop is unrolled only when no loop is nested in it
- A binary schema is a constant (measured 2026-10-25: 2.1 ms against the old compiler's 1.2)
- Identical functions are folded into one

### The memory, the placement and the copies

- The small-block allocator (D794 to D796) never gives a chunk back to the system and never moves a free block to another size class, so a program's peak of small blocks of one size stays its memory; an allocation of a constant size above 120 bytes, and every free of a block above 1016 bytes, is a call
- The compiler places memory (built: an object or a `Buffer` that never leaves its function is registers or frame room, D801, D1341; not built: a placed buffer is still made by a call to `Buffer.Buffer` and grown by calls to `reserve`, so `the_compiler_places_memory` and `a_variadic_list_the_callee_only_reads_lives_in_the_callers_frame` save only the allocation of the buffer itself, and a list filled past the 48 bytes inside its buffer grows its bytes on the heap step by step)
- Reading an address is one machine operation (`reading_an_address_is_one_machine_operation` is about 50 times expert C: `Base64._encoded`'s values are nearly all spilled, see the register intervals in Architecture, and every `append_code` keeps the buffer's and the text's counts in memory)
- Objects that never leave their function live in the frame (built after inlining, D801: in registers or the frame, made at the `return` when answered, its count followed while compiling, D953; not built: a local assigned a new object on every pass of a loop whose first object was made before it (`accumulated = accumulated * step_matrix` in `game_maths` is registers now), an object whose class has a `drop`, back references or frees its attributes other than by releasing them, an object of a class that releases attributes passed to a call that is not inlined, and anything in a function that waits)
- A local list of known size lives in the frame (built for a literal of numbers, whole or decimal, only counted and read by index, D991, D1171; and, once the list is registers after inlining, its buffer in the frame, D1341; not built: a literal of objects or texts, and one passed to a call that only reads it and is not inlined)
- A variadic list the callee only reads lives in the caller's frame (built: once the callee is inlined the list object is registers, D1051, and its `Buffer` frame room, D1341; not built: the buffer is still set up by calls to `Buffer.Buffer` and `reserve` on every call, 34 ms against the old compiler's 4, and a callee that is not inlined still gets a heap list)
- A list held only by another list lives in its slot
- A list of lists filled again keeps each list's room
- Objects of one class sit together (built: a list of a class of numbers, filled only with fresh objects and read back, holds its objects inside its storage, D994, and one array per attribute with no header when no item is handed whole to a function of its class, D998; not built: the header dropped for a list whose items are handed to the class's functions, elements holding text, decimals or objects, and objects of one class outside a list)
- A row of borrowed items lives in the frame (built when the function it is passed to is inlined, D801, D942: the row is registers; a row passed to a call too large to inline is still made on the heap, and the items it holds are still counted when it is made and let go when it ends)
- An `Items`' storage is chosen while compiling
- An object attribute only its holder ever holds lives inside the holder (built for a class of plain numbers written only by the defaults or a constructor with a new object and read only for its parts, D1034; not built: a held class with objects or texts in it (`Order.customer`), a holder copied by `copy()` or `deep_copy()`, a part passed to a function, and a list's objects holding such attributes laid whole in the list's storage (built in one array per attribute, D1065; laid whole, `defaults_the_constructor_replaces_are_never_made` ran 2.3 times slower); an `Item` holding a room is still made on the heap and copied into the arrays, since an object that holds a room is never placed in registers)
- A loop that sums a list filtered by its counter on every pass is one pass over the list (`report_over_records`' 64 profits)
- An if-converted body may hold a checked product or difference when ranges prove it fits, and decimals; the generator writes its picks as `cmov` instead of masks (D996)
- Copies that cost nothing (built for a copy of a plain object that never leaves the function, once `copy()` is inlined, D801; and a copy nothing changes while it lives is the original, D1344; not built: a copy kept in an attribute or a list or answered, and a copy in a block that writes anything at all, even to objects the copy never reaches, since what a call may write is known per attribute and not per object)

### The counts

- Singletons: made on first use, never counted (built: a singleton passed to a call is not counted, a function answering a singleton (a rebuilt attribute among them) neither counts it nor has its caller let it go, D949, and an attribute holding a quiet singleton is the singleton itself, D954; a local declared from a call answering one is not counted either, D1173; not built: kept in a list or a local of a union it still is, and so is an attribute in a program with a `drop()`; a singleton the entry class makes is never tested again outside what its defaults reach (D961), and a quiet one read in a loop is tested once before it (D967), but the first-use test of any other singleton read in a loop is made on every pass)
- Plain reference counts where no thread reaches a class (built per class, D1166: a count whose object's class is known where it is taken or let go; not built: a count the compiler's own machinery writes (a thread's start and end, a task's frame, the free functions' texts), a union's, a shape's or a function value's, and `_release` where it is called rather than written in place stay atomic in a program with threads, and the loop passes that move counts (`loop_invariants`) still stand aside for the whole program once it has a thread)
- An item passed to a call that cannot change its list is not counted (built for the receiver of a call and for an argument after a `crash` that proves the read, D957, D1170; not built: a read whose index or call arguments are not plain reads, and a call through a function value)
- A singleton's attribute that never changes is read in place: read in place today only because a read of a locked singleton's attribute from another class takes no lock at all (The threads); when that lock is built, an attribute holding an object nothing assigns after the singleton is made must stay outside it
- A list's templates read its elements without counting them: done where nothing after the read in the template can write a list of that class; a template handed a function value still counts when any function the program takes as a value could write one
- An item written back to its own slot is not written (built for `list[index] = name` after `var name = list[index]` proven in the same block, D1033, and for a call whose whole body is `list[index] = held` after a call on the same receiver that ended with `held = list[index]`, D1061; not built: any other write-back from another block, or of a name that is counted)
- `a_list_held_only_by_another_list_lives_in_its_slot` runs about 9% slower since `append` stores into the empty slot past the end without the load and comparison it made before (D1032): fewer instructions, so the cause is in the generated loop's layout, not yet found
- Who holds an object is decided while compiling (built: a parameter a function keeps on its one read is handed its count, and a local is handed to what keeps it at its last read, D1031; a slot a constructor's defaults leave empty is stored without reading it, D1032; a singleton's attribute only given items of a list it holds is not counted and its default is not made, D1062, D1063; not built: such an attribute of an object that is not a singleton, a borrow of a slot of a row passed to calls across a loop (the row slots of `a_walked_crash_lines_read_is_the_rows_read`), objects laid inside their one holder, and classes with a `drop()` in what they hold)
- A list item read only to test it is not counted (built for `is present` on a `List`, `Vector` or `Items`, D947, D1172; not built: a read tested by another comparison than presence)
- Reading through a `type` without counting (built for a row placed in registers whose reads meet their releases on one path, D951 to D953; not built: a row passed to a call too large to inline, and a count taken before a call that is not inlined)
- Objects made for their owner are told apart, and counts stay plain for what one of the calls run at once counts: both wait on calls in a row and loops over a list of different classes running at once (The threads, D1175); until then no call runs at the same time as another, and every count those calls take is already plain

### The text, the numbers and the collections

- Short text lives inside the `String` (D789): a text whose `String` keeps other attributes is still two allocations
- A slice shares its source's bytes where the source outlives it and neither changes (texts can change in place through `append_code` and an append, so it needs that proven first)
- Short symbols are inline text
- A foreign name is never copied
- A number's bits are read in place (built for a read at offset 0 of the number's own width, D786, D791 and D805, and the parts `to_half_precision` takes apart with `/` and `%` by powers of two are shifts and masks, D1323: 264 ms to 170 ms; not built: a read of part of a number's bytes, or at another offset; what is left of the case is the machine code: the alignment padding at every join, the moves between registers, and a magnitude whose subnormal path the bounds cannot follow, so the `UnsignedShort` narrowing keeps its two tests)
- A decimal literal beside a `Float` is a `Float` (built: the literal is a `Float` and decimals live in decimal registers, D971; not built: a sum of decimals in a loop is never reassociated or vectorised, which needs a proof that every partial sum is exact, so `a_decimal_literal_beside_a_float_is_a_float` waits on one addition after another, about 16 times expert C)
- Arithmetic is checked in every build (37.8 ms to 35.5 since a checked 32-bit operation works in its target's register, D1418, against the old compiler's 19.8): the loop is three checked 32-bit operations in a chain, each the operation, a jump on overflow and a sign extension, so the chain waits two cycles per operation; the 64-bit form tested beside the chain halves that wait but was slower elsewhere (D1418), and nothing bounds `values[index]`, so the checks stay
- Arithmetic a range proves is not checked (built in the proof `proofs/ranges`; not built: a total that adds at most one term a pass, a counter stepped down under `>` or `>=`, a loop local other than a counter keeping the range of what it is assigned, a `-` in front reported as a negation)
- A loop over plain values reads its count once and its items unchecked (built: the count and the storage read once before the loop when it writes only number items, and the bound test dropped under the loop's own signed test, D972, D973; not built: a `set_at` into another list still tests that list's count each pass, and the loop is never vectorised nor fused with the next loop over the same list)
- A proven read tests only its bounds (built for a library `List` of numbers or objects, and for a window `values[at + k]` under `at + m < count`, D1321, which leaves `a_proven_read_tests_only_its_bounds` with no bound test but its time unchanged: its loop waits on a chain of checked 32-bit sums, see the line above; not built: `Vector`, `Items`, a list of `T?` items, unions or function values)
- A walked `crash` line's read is the row's read (measured 2026-10-25: 92 ms against the old compiler's 50)
- Boxing only where a value travels as a shape (measured 2026-10-25: 57 ms against the old compiler's 17: each `to_string()` through `Printable` makes its text)
- A function value describes its arguments when asked (built: a function value made and called in one loop is a direct call, inlined, D1052; not built: a function value passed in from outside the function, or one of several functions, is still called through its address)
- Defaults the constructor replaces are never made: done for a quiet default the constructor assigns before reading it; a default some other making (a deep copy, a reader) overwrites is still made
- Proofs that survive a call

### The threads

- The small-block allocator (D794 to D796) finds a thread's lists through its thread slot on every allocation and free in a program with threads (two loads and two tests, D1419), where a `Parallel`'s own block could hand them over
- Hidden async/await as compile-time state machines
- Reads in a row overlap
- Thread safety for singletons, the cheapest safe form (built: unreached, never changing, atomic and locked, D780 to D783): a read or write of a locked singleton's attribute from another class takes no lock yet
- A singleton no other thread reaches takes no lock: the walk is made only from what a `Parallel` starts, not again over the tree-shaken program
- A singleton's reading functions do not exclude each other: a counted loop of reads shares the lock (D988), but a single read outside such a loop still takes it alone
- An attribute read only under its singleton's lock is a plain number
- A loop of calls to one singleton tests for tasks once
- Thread safety for singletons, the rest of the plan
- Calls in a row run at once
- A loop over a list of different classes runs them at once
- A loop whose passes write only their own item runs in bands (built for `each_` on a `List` of a class of the program, D975; not built: a `Vector`, a `filter_` chain before it, a pass that calls a member of another object or of a number)

### The compiler's own machinery

- REPL, live reload and debug machinery only in those builds
- A reload compiles only the classes that changed
- What a `--hot-reload` build carries so its objects can move
- A crash's report is kept out of the way (20.1 ms to 14.1 since the report's block is written after the function and the loop tests at the bottom, D1416, D1417, against the old compiler's 13.4): the loop keeps the checked `picks[index] + round`
- Smaller ones (45.8 ms to 29.1 ms since a loop calling a function value keeps its receiver's attributes in registers, D1324, against the old compiler's 26)
- `a_word_inflected_while_compiling` runs about 10% slower (65 ms to 72 ms) since the register bounds (D1322) left ten checks of `String._plural_by_ending` and two of `String._inflected` out, and 62.0 to 65.0 ms since the checked 32-bit operations lost their move (D1418), with its loop byte for byte the same: fewer instructions both times, so the cause is in the generated code's layout, not yet found
- Other optimisations

### The machine code (D771 to D775 are built)

- Loop-invariant code motion (built, D803, D962, D973): a load without a region moves before its loop only from the loop's first block and only when nothing in the loop writes memory or calls (a load known never to change moves from anywhere); a load with a region moves from any block every pass runs when every write in the loop has another region; anything in a loop that calls is still made on every pass
- In a program with threads a load moves out of a loop only when the compiler knows it never changes or no other thread touches its class (D968, D973): a load without a region (a worker's local list) is still made on every pass
- Assigning a fresh empty `List()` to a slot whose old list nothing else holds (count 1, proven or tested once) clears the old list in place and keeps its room (D969); not built (the `clear()` of a list of lists followed by a loop appending new empty lists is, D981, but nothing else between them, and not a list of `Vector`s or `Dictionary`s)
- An attribute a loop updates is kept in a register (D966, D974) only when every access in the loop carries its region and the loop calls and allocates nothing: an access through a union, a shape or a type parameter, or any call (a buffer's growth on a cold path) keeps every attribute in memory; in a program with threads only a locked singleton's attributes and those of a class no other thread touches are kept
- Decimals live in decimal registers (built, D971; loads and stores straight to memory, D1305): a decimal constant is moved in from an immediate rather than read from the program's data, a decimal that finds no decimal register free (and no constant to take one from, D1058) is moved through a general register on every use instead of spilled, and a decimal operation on a constant (`x + 0.0` with `x` known) is never folded through a loop
- `an_attribute_a_call_cannot_assign_is_passed_without_counting` runs about 20% slower than under the old compiler (10.8 against 13.0 ms head to head, 2026-10-26) with the same low IR (one comparison fewer): the cost is in the machine code written for it, since the loop inlining and the late cleanups (D1051 to D1059), not yet found where; its read after `crash values[at]` also still tests the index twice, under the old compiler too
- Copies are read through only for a register written once (D1054), and the allocator gives a result the register of a left operand whose life ends there only for a target written once (D1303): a loop's variable copied from another register written several times, both live across the back edge, keeps both registers (lives are kept per block, so no hole inside a block is seen)
- The block merges, inverted comparisons and steady constants (D1056) run only after vectorising, so the passes before it (common subexpressions, loop invariants) still see the small blocks inlining left
- Common subexpressions across blocks only for registers written once (D803): a computation over a register written twice (a loop counter) is still made again in a later block; a repeated comparison is answered only when made in its branch's block on registers written once under a dominating branch (D1304), so one made in another block, or a decimal one, is made again
- A function inlined into a loop keeps the bounds checks its ranges needed (ranges are proved before inlining; after it only registers written once get bounds, D1059, so a counter's range is not followed into an inlined callee), and a callee of more than 40 instructions, or that waits, is called (D802) unless the call is in a loop (up to 96, or 400 for the only call to it, with no loop of its own, D1051); inlining is chosen by size alone, with no estimate of the registers a loop then needs
- A division and a remainder of the same two numbers are one `div` (D1183) only when written one right after the other with a divisor that is not a constant: an instruction between them, or a constant divisor (two multiplications), keeps two
- A value is split around the blocks where it crosses a call (D1011) and, when spilled, by loop depth into a register in its deepest loop (D1301): a value given a register for its whole life is never split to free it in a hot loop it barely uses (only a spill decided by weight frees it), a decimal is never split, the split is only at the deepest loop where it is used, and loads are never rematerialised
- An object let go unread is never made (D984) only when nothing but its class and count is written into it and its class frees nothing but its memory: a default object with attributes, or one holding objects, is still made and freed
- An object read from a steady load is not counted (D985) only when every register holding it is written by that load or copies of it: a local that may hold either a steady object or another one is counted
- A loop tests its condition at the bottom (D1416) only when its head is up to three comparisons, loads and copies before its branch and no value changes its register on the edges into or out of the head: a head that computes (arithmetic, a call) still jumps back to the test at the top, and the body the rotated test jumps back to is not aligned (only the head is)
- A counted loop runs in vector lanes (D1021 to D1024) only with AVX2: a processor without it runs every loop as written (no SSE2 kernels); and only a loop whose head is the one test `counter < bound`, with no other branch than halting bound tests, that reads and writes numbers at `counter * size`: not built are a read through an object an item points to (a gather: `sum_` over a list of objects, the most common refusal across the benchmarks), a write narrower than 4 bytes, a division or a remainder, an unsigned comparison of two values, the counter used as a number, a decimal `if` (no decimal `Select`), a loop that reloads its bound in its head, a stride other than the item's width (an object kept inside its list's storage), and two loops over the same lists fused into one pass
- A decimal total runs in lanes only where the exactness proof (D1023) follows every term: a list's items are told apart by where the list (or its buffer) was made, so lists made by one shared function, a list written through a `Buffer` function or filled by copying bytes from elsewhere, and a decimal a call answers prove nothing; and only one decimal total per loop is kept in lanes
- A slot a loop assigns from a list's items is counted on every pass (built for a singleton's attribute given only items of a list the singleton holds, whose items nothing but `append` and a write-back of that attribute writes, D1062; not built: an attribute of an object that is not a singleton, or of a list whose items other writes replace)

## Every proof the original makes

What each proof still lacks; `PROOFS.md` has the whole of each. A line marked "fails silently" lets a wrong program
through (D244) and comes first. Every proof still made inside a step or another pass moves into its own pass in
`proofs/` (D1086): the builder's other refusals (endings, a divisor written as zero, a wider operand, an unstepped
poll, a folded build crash) are still made while building, and the borrow analysis the proofs `borrowed_items` and
`lent_parameters` run is still `building/borrows.spite`, shared with the builder's `lends` (D1107);
the objects and lists in the frame, the singletons made at the start and the bounds a signed test proves are proofs
of their own (D1121, D1122), but the lowering's other proofs are still made inside it (D1124): the counts it leaves
out (an argument its caller holds, an attribute a call cannot assign, a template's element, an item written back, a
held, tested or used item, an address keeping its owner), since each reads what the lowering resolved while
writing the function (its locals, its scopes, the registers it holds); the facts the low passes `unread_objects`,
`known_headers` and `compile_time_evaluation` find stay in them, since each is the optimisation itself; the thread
reach, the singleton forms and a loop's coarse lock go with the decisions at the start of the lowering (D1111).

### Presence and control flow

- A call keeps a proof it cannot change: a `[]` or count proof is undone only by a direct shrinking call, a bare call of the class's own function and a call on a `[]` receiver (its read still halts); a call inside a condition is ordered after the block it guards
- An `if` that leaves proves the rest: a count side after `not found` proves no read
- Proving what is proven is an error: a re-check inside the `if`/`while`/`switch` that narrowed gets the Boolean text; not refused: a `[]` read proven by a count or an earlier check, a divisor re-proven, a class test already answered, the same condition on the next line, an `assert` that folds true, and a check of a plain local
- A copy made to narrow is an error: a copy narrowed by an `if not copy` whose block does not leave

### Indices and numbers

- A proven count or bound proves a read: `<=` bounds; count facts in a `while`; undoing a proof inside the loop that read it is not refused; a shrinking call inside an assignment or argument does not undo it
- A proven count or bound proves a read of a width (`read_<number>_at`), and a position known not to be negative drops the low test
- A text's length known while compiling proves its `code_at`: a `String` attribute holding a literal that nothing changes keeps its literal's length, so `alphabet.code_at(value.bits_and(63))` on a 64-letter alphabet needs no test; today only the test below 0 is left out, and the one against the length stays (D1211)
- An index built from loop counters is proven by one guard (`rows * stride <= list.count()`)
- An index offset by a base is proven by one guard (`base + bound <= list.count()`)
- A counted loop reads its items unchecked: a second list indexed by the counter keeps its test on every pass outside the vector loop, and a window read loses its test only when the registers line up
- A proven divisor is not checked: `!= 0`, an attribute or member path as the divisor, and `--repl`/`--hot-reload` builds
- Arithmetic that does not fit halts: a `Long` counter whose bound has no range keeps its check and interactive builds keep every check
- A range proves arithmetic fits (built, D768; not built: `absolute`, the counters stepped down, the loop locals other than counters, see the optimisation's line)

### Compile-time questions

- How many arguments a function takes: `argument.argument_count()` outside a walk over functions has no error
- Whether a class keeps state: the answer is a filled value, not a folded constant
- Conditions decided while compiling: `function_waits` and `function_writes_parameter` are late (D673), a codegen number against a literal, a function taking a `type` copied per class, `x and false` and `x or true` whose `x` calls something
- Tree shaking: nothing is shaken after lowering, inlining or late folding; a function nobody calls is not type-checked; no inspectable build keeps everything
- A reload compiles only the changed classes, and reaches every object whose attributes it changes (no reload yet)

### Memory

- A buffer freed in its block lives in the frame (waits for `Memory.Heap` in the library)
- Objects that never leave their function live in the frame: the fresh result of a function not inlined, an object whose class lets go of attributes in the frame, `.memory.section` answering `'stack'`
- Local and variadic lists in the frame (built: a literal of whole numbers only counted and read by index, D991; not built: variadic lists, other items, other reads, constant data)
- A function value its callee only calls lives in the frame: the "only calls it" proof for a callee that is not inlined

### Borrowing and lending

- No borrowed read past a resize (fails silently, memory stays safe): assigning an object two levels up the path is not a resize; the library's own functions are not followed; a value of unknown type fans out to every function of the name; effects computed under the recursion guard are cached short
- An item lent to the caller: not built: the uncounted return, `is_fixed_size` and `functions[...]` folded in its conditions
- An item lent to a call (fails silently): a lent parameter the callee passes on through a receiver whose class the study cannot tell, or to a library function, a row's attribute, the unnamed expression refusal, lending to a local function value, variadic positions; not built: the uncounted argument
- Borrowed items of a `Vector` or `Items`: the reads stay counted references, walk copies and library member templates are not checked, `InlineMemory` is not a borrowing collection
- Rows of borrowed items: the row in the frame and uncounted for a callee not inlined, a walked template's `var stored_row = rows[...]`, the arguments a plural fills, `row.describe` as a function value, a row passed to a library function
- A list element lent to a row
- A singleton attribute that never changes is read in place: the per-attribute fact (a singleton is steady only when all its attributes are plain)
- An item written back to its own slot is the slot: a write-back nested in a block, and lists other than a library `List`
- A value followed through calls is the slot it was read from
- An item a name holds from its list is not counted (built for `var item = list[index]` with a proven read when nothing after it in its block can write the slot, D992; not built: a name kept across a call that may write any list of the item's class, even another one)
- A list item read only to test it is not counted: lists of nullable items, `Items`, a path through the item
- An item used at once is not counted: the item passed as an argument, indices and arguments that are not plain reads
- A list held only in a slot of another list
- A list only its class fills holds only what it fills
- A table filled once holds what its setup put in: a table held by a singleton or made in another function

### Threads and locks

- No attribute is read past the lock: the old compiler's plain attributes under the lock and atomic attributes
- What a `Parallel` may reach: reach is followed only through the work's own class
- Calls that share nothing written
- Classes in a list that share nothing written
- Passes that write only their own item: `Vector`, writes other than number and enum attributes, other calls
- An object made for its owner is told apart
- No other thread counts a class
- What one of the calls run at once counts
- Objects of a class made on one thread
- A copy nothing changes is the original
- No other thread touches a singleton (the second walk over the tree-shaken program)
- Read-only and atomic singletons: one lone atomic attribute inside a locked singleton
- A function that touches no changing state takes no lock: "touches no changing attribute" rather than "never reads `this`", and a call between two locked functions going to the unlocked body
- Reading functions share the lock: outside a counted loop that holds it (D988)
- A loop that starts no task tests for tasks once
- A loop that can never end is an error: in `Parallel` work "waits" is "calls nothing but the console", not the waits fact
- Reads in a row are independent

### Other refusals built on an analysis

- A value fits a `type`: a `type` member is compared by its members' names, not their types (D1255), and a `$T`'s constraint checks only that each member exists
- Singletons that make each other in a circle are an error: the "makes" links (a circle through an ordinary object made in an attribute default halts at run time instead)
- A member template fits: the specific error for `each` given something that is not a function, and the member checks of a member template of the program's own class (only a library collection's are checked)
