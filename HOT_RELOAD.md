# Hot reload

Save a file of a running program: the program compiles it again, writes the functions whose machine code changed
into a block of new code, and swaps them in where it already pauses, at a loop's check point or at the REPL's
prompt. Objects and singletons stay. What a reload may change is the language's rule, in
[`repl.md`](https://github.com/Spite-Language/spite_documentation/blob/master/repl.md) ("What a reload can change"),
and its rules are in [the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/repl.md#live-reload-in-detail).

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
3. **The reloader**, `Spite.HotReload`, Spite the compiler adds to the build (`.spite/build/spite/hot_reload.spite`)
   with `Spite.ReloadPoint`, which the start of the program makes: it watches the program's folders with
   `FileSystemWatcher`, and the check point every loop of the program's own code ends with (one load of a flag a
   helper thread raises every 25 ms) asks it whether a saved file waits. Then it runs the compiler that built the
   program with the program's own flags and `--reload-at=<address>`, and swaps in what comes back.
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

## The manifest

One line a fact, tab-separated: `generation`, `text` (the address of the code), `routines` (the digest of the
shared routines), `function <key> <start> <slot> <digest> <class>`, `state <name> <address>`, `import <name>
<address>` and `library <name> <address>` (the C runtime's), `class <key> <id> <layout>`, `enum <key> <values>`,
`file <path> <digest>`. A reload writes the next one beside it as `<program>.reload_pending`; the program renames it
over `reload_host` once the code is swapped in, so the manifest always describes the code the program runs.

State is matched by name, never by place: each piece of data the lowering makes for state is named where it is made
(`singleton.<class>`, `static.<class>`, `slot.<function>`, `memory.allocations`, `scheduler`, ...). Data that is
neither named state nor a constant (a callback's per-site room) is refused by name when changed code reaches it.

## A reload is refused when

The program keeps all of its code, and the answer says why:

- the program does not compile, with the compiler's error;
- a class the program holds objects of has other attributes or other places for them (its objects would be read
  through a layout they do not have), or an enum's values change other than by adding new ones last;
- the shared routines are compiled differently (the program starts using threads, say);
- changed code calls a system function the program never imported, or reaches state that has no name;
- the room kept for new code is full or cannot be reserved.

Class ids are seeded from the manifest, so a class keeps the id its objects carry, and a new class takes the next
one after the largest.
An object literal's class is keyed by what does not move when code is added around it: the class and function
that write it, its attributes' names and types in order, and its place among the literals of that same layout in
that function (`Object_<digest>_<n>`). A reload that adds a literal before another therefore leaves the running
literal's id with the literal that made its objects, instead of handing it to whichever literal now comes first.

## Crash reports inside reloaded code

A fault report names its place (file, line, class, function) from the place table: one entry for each run of code
that comes from one line, in order of address, closed by an entry at the end of the code that names no place. The
table's second eight bytes hold the address of the newest reload's place record, zero until the program reloads.

A reload library carries a place record for the code it copies: the record before it (the running record when the
reload was compiled, which the manifest keeps as the state `table.places.reload`), where its code starts and ends,
and the entries of every function it copies at their new offsets. One more slot write makes it the newest. The
fault handler walks the records from the newest and reads the table of the one whose code holds the address; an
address in no record and past the executable's code names no place instead of the last function written.

## Code typed at the prompt, and breakpoints

Both are reloads whose answer the program keeps to itself. `eval` and `run` write `<program>.reload_prompt` (the
word, then the code); the compile writes `Spite.PromptCode`, one function `answer(program: <Entry>): String` whose
body is the typed code, to `.spite/build/spite/prompt_code.spite`, digested in the manifest like a program file. A
build writes it with `return ""`, so the REPL calls the same function before and after, through its slot. A
breakpoint writes `<program>.reload_breaks`; the compile has the parser write a call of
`Spite.Breakpoint().pause_at(site)` before the statement starting on each line, after the file's rules are checked, so only the
functions of the files holding one change. `Spite.Breakpoint` is machinery the symbols stage writes, holding the
REPL's stop as a function value. The program removes both files when it starts.

## Not built yet

What `TODO.md` lists: moving live objects to a new layout, compiling only the changed classes instead of the whole
program (the proof finds them, the compile does not skip the rest yet), the compile on a helper thread, a reload
held while a `Concurrent` waits inside a function it swaps, reflection that follows a reload, and a breakpoint's
`locals`.
