# Hot reload

Save a file of a running program: the program compiles it again, writes the functions whose machine code changed
into a block of new code, and swaps them in where it already pauses, at a loop's check point or at the REPL's
prompt. Objects and singletons stay. What a reload may change is the language's rule, in
[`repl.md`](https://github.com/Spite-Language/spite_documentation/blob/master/repl.md) ("What a reload can change"),
and how it works is in [How it works](https://github.com/Spite-Language/spite_documentation/blob/master/repl.md#how-it-works).

A build without `--hot-reload` carries none of this: no slot, no manifest, no watcher, no reload code. The flag
implies `--development`, an inspectable build.

Target: a changed function reloads in well under 0.1 s of swapping, after the compile it waits for (the original:
1.7 s, most of it a C compiler run).

## The parts

1. **Slots.** In a `--hot-reload` build every function starts with `jmp [slot]`, six bytes, and its body follows.
   The slot is eight bytes of the executable's data that the loader leaves holding the body's address. Every call,
   every function value and every thread entry still names the function's start, so all of them follow a swap: a
   reload writes the new body's address into the slot. Functions are aligned to 32 bytes in such a build, so a
   function's code does not depend on where it lands. Other builds call directly and pay nothing.
2. **The manifest**, `<program>.reload_host` beside the executable: for every function its start, its slot and a
   digest of its machine code; for every piece of state the code reaches (a singleton's record, a static object,
   the counts, the scheduler's state) its name and address; every system function the executable imports with the
   address of its entry; the digest of the shared routines (allocating, freeing, stopping); every class's id and
   layout; every enum's values; and a digest of each of the program's files. A reload compiles against it.
3. **The reloader**, `Spite.HotReload`, library Spite (`spite_standard_library/common/spite/hot_reload.spite`, and
   `windows/spite/hot_reload.spite` for the room, the compiler's run and the swap), which the start of the program
   starts through `Spite.ReloadPoint`. That class is the one part the compiler writes for the build
   (`.spite/build/spite/reload_point.spite`), since it is what varies: the program's folder, the compiler's path, the
   build's flags and the folders to watch, as plain values handed to `start`, and in a REPL build the session and
   the console ([Lines typed at the REPL](#lines-typed-at-the-repl)). A suite test builds the library's class without the flag
   (`tests/hot_reload_library_is_built_without_the_flag`). It watches the program's folders with
   `FileSystemWatcher`, and a check point asks it whether a saved file waits, waiting for a file still being
   written to settle (`settled_changes`). A check point is one load of a flag a helper thread raises every 25 ms; it
   ends every loop of the program's own code, sits just before and after each call from it into a library function
   that waits, the same waits started work moves on at (`Waits.reaches_a_wait`: `Console.read_line`, `File` reads,
   writes and `lock`, sockets), and runs inside `Program.sleep`, which the
   helper wakes. Then it runs the compiler that built the program with the program's own flags and
   `--reload-at=<address>`, and swaps in what comes back.
4. **The reload compile**, `spite <folder> <flags> --executable-path=<program> --reload-at=<address>`: it reads the
   manifest, compiles the program, and compares the digest of every function's machine code with the manifest's.
   A digest leaves out the four bytes of every reference that leaves the function and puts in its place what it
   names (`call Hero.grow`, `state singleton.World`, `import Sleep`, the text a constant holds), so a function
   whose code is the same compiles to the same digest wherever it lands. Every function whose digest changed, and
   every function the running program lacks, is written into `<program>.reload_<n>`, laid out at the given address,
   with every reference resolved against the running program: a call to a function the program has goes to its
   start (and so through its slot), state the program holds is the program's, and new state and constants are
   copied in. It prints `rebuilt Hero`, `removed Hero.grow` for a function the program has and the new code does
   not, `library <path>` and `manifest <path>`, or `unchanged`, or `no code the program runs changed, so nothing
   was rebuilt`.
5. **The swap.** The program commits the room at the address (it reserved 256 MB at its image's base plus 1 GB the
   first time, so every reference reaches it with 32 bits), copies the code in, flushes the instruction cache,
   writes each changed function's slot, and makes the new manifest the running one. A library is never unloaded: a
   call already running finishes on the old code, and values the old code made stay valid.
6. **The ends.** A reload never swaps `_start`, so in such a build `_start` calls `_ends`, an ordinary function
   with a slot that ends every piece the program holds at exit (the `to_debug` guard's table, the singletons, the
   callback table). A reload that brings a piece in changes `_ends` and swaps it, so the piece is ended too
   (`tests/hot_reload_frees_a_piece_it_brings_in`). Other builds end the pieces in `_start` itself.

## The manifest

One line a fact, tab-separated: `generation`, `text` (the address of the code), `routines` (the digest of the
shared routines), `function <key> <start> <slot> <digest> <class>`, `state <name> <address>`, `import <name>
<address>` and `library <name> <address>` (the C runtime's), `class <key> <id> <layout>`, `enum <key> <values>` (each `name=number`),
`file <path> <digest>`. A reload writes the next one beside it as `<program>.reload_pending`; the program renames it
over `reload_host` once the code is swapped in, so the manifest always describes the code the program runs.

State is matched by name, never by place: each piece of data the lowering makes for state is named where it is made
(`singleton.<class>`, `static.<class>`, `slot.<function>`, `memory.allocations`, `scheduler`, ...). Data that is
neither named state nor a constant (a callback's per-site room) is refused by name when changed code reaches it.

## A reload is refused when

The program keeps all of its code, and the answer says why:

- the program does not compile, with the compiler's error;
- a class the program holds objects of has other attributes or other places for them (its objects would be read
  through a layout they do not have), or an enum's values change other than by adding new ones last (a value's
  number included: the answer names both numbers);
- the shared routines are compiled differently (the program starts using threads, say);
- changed code reaches state that has no name;
- the room kept for new code is full or cannot be reserved;
- a function writes more or fewer object literals of one layout than the running program's.

Class ids are seeded from the manifest, so a class keeps the id its objects carry, and a new class takes the next
one after the largest.
An object literal's class is keyed by what does not move when code is added around it: the class and function
that write it, its attributes' names and types in order, and its place among the literals of that same layout in
that function (`Object_<digest>_<n>`). A reload that adds a literal before another therefore leaves the running
literal's id with the literal that made its objects, instead of handing it to whichever literal now comes first.
A reload that changes how many literals of one layout a function writes is refused, since it could not say which
literal the running objects came from.

## System functions a reload adds

Changed code may call a system function the running program never imported (a lock, a thread's wait). The reload
library gives each such function an eight-byte cell in its data, and its calls go through the cell as the
executable's own calls go through its import table. After the slot writes the library lists the cells: a count,
then for each the cell's address and the names of its system library (`kernel32.dll`, or `ucrtbase.dll` for the C
runtime) and of the function. The swap fills each cell with `LoadLibraryA` and `GetProcAddress` before it writes any
slot, and refuses the reload, naming both, when the system lacks the function. The manifest then lists the cell as
that function's `import` (or `library`) line, so a later reload calls through it too. A program that never reloads
pays nothing: its calls go through its import table as before.

## Crash reports inside reloaded code

A fault report names its place (file, line, class, function) from the place table: one entry for each run of code
that comes from one line, in order of address, closed by an entry at the end of the code that names no place. The
table's second eight bytes hold the address of the newest reload's place record, zero until the program reloads.

A reload library carries a place record for the code it copies: the record before it (the running record when the
reload was compiled, which the manifest keeps as the state `table.places.reload`), where its code starts and ends,
and the entries of every function it copies at their new offsets. One more slot write makes it the newest. The
fault handler walks the records from the newest and reads the table of the one whose code holds the address; an
address in no record and past the executable's code names no place instead of the last function written. The
`spite.function` and `spite.caller` lines name a reloaded frame from the same record (its class and function, as
the place names them), since `<program>.functions` knows only the executable's code, and `at=` gives
`reload+0x<offset>` from the start of that record's code.

## Lines typed at the REPL

A `--repl` build carries the parts above without the watcher (`--repl --hot-reload` adds it): `Spite.ReloadPoint`
then also holds the session `Spite.Session` and the console `Spite.ReadEvaluatePrintLoop`
(`spite_standard_library/common/spite/read_evaluate_print_loop.spite`, and `windows/spite/` for reading the input
without waiting). The start of the program hands the entry instance to the session and starts the console, every
check point asks the console whether a whole line waits, and once the constructor returns the console reads and
runs lines until the input ends.

Each line is a reload. The console writes `<program>.reload_session`: a `var\t<name>\t<type>` line for each
`var` the session keeps, `func\t<count>` and that many lines for each typed function, `load\t<path>` for a file
being loaded, and `line\t<count>` with the line. The compile reads it and writes `Spite.Session`
(`building/reload/session.spite`) as two files of one class, both digested in the manifest like program files.
`.spite/build/spite/session.spite` is the compiler's own code, exempt from the rules like the library: the session
holds one attribute, the entry instance, so its layout never changes: each of the entry's
attributes has a `get_`/`set_` pair reading it through `program`, each of its functions a function calling it, so
a line names them bare; each kept `var` has a `get_`/`set_` pair over `_loop.kept` and `_loop.keep`, which the
compiler builds as a read and a write of a singleton it writes for the name and the class
(`.spite/build/spite/kept_<name>_as_<Class>.spite`, `Reload.KeptValues`), so a kept value has its own type. `.spite/build/spite/typed_lines.spite` is what the person typed,
checked as program code by every rule (`Mapping.LibraryFile.is_typed_lines`; it is never rewritten), and an error in
it names the typed line as its place (`Diagnostics.TypedLines`): the typed functions, and `run_line(): String?`,
which is the line, `var line_value = <line>` and `return "{line_value}"` for an expression, the statements and a `keep` of
each `var` declared at its top for anything else. An expression that answers nothing is run as a statement there.
The compile's answer tells the type of each such `var` (`session var\t<name>\t<type>`, `outputs/session_facts.spite`),
which the console writes into the next session. A line that does not compile leaves the session file as it was.

Without the watcher a line is compiled against the files as the program loaded them: a program file whose digest
differs from the manifest's, and that the line does not `load`, refuses the line, naming the file.

## Not built yet

What the issues list: moving live objects to a new layout, compiling only the changed classes instead of the whole
program (the proof finds them, the compile does not skip the rest yet), the compile on a helper thread, a reload
held while a `Concurrent` waits inside a function it swaps, reflection that follows a reload, a REPL `var` of a
`union`, a `type` or a function, `load` of a file outside the program's folders, and the scratchpad REPL of a
folder with no program.
