# TODO

What the new Spite compiler does now, what is left, and in what order. One file, kept up to date as the work
moves. The compiler is written in Spite and is built by the old compiler until it can build itself.

## Why this repository exists

**The compiler is being written again, and only the compiler.** The language is decided and does not move; the
standard library, the tests, the documentation and the decision log stay where they are
(`../SpiteLanguage`) until they move to a repository of their own. What is here is the compiler, and
nothing else.

**Why again.** The old compiler got to be hard to maintain, and hard for a small model to work on, which
is one of the goals the language has: it is one program of 277 files, and a change to one part of it means
reading the rest. The ideas for the new one are written down in
[`new_compiler.md`](../SpiteLanguage/new_compiler.md), and they are these:

- **It is broken into steps, one folder each**, and a step takes the previous step's answer and hands its
  own answer to the next one. No step reaches back into another.
- **Each error is found by the step that owns it**, and the run stops there, so a syntax error dies at the
  syntax tree and never reaches a later step.
- **There is no discovery step.** The compiler maps the folders the program can use and reads only the classes
  something names.
- **Every step's answer is cached**, so restarting a compilation redoes only the work that changed.
- **The compiler is responsible for the hot reload**, so it keeps the development memory it needs, and a
  reload is as fast as it can be.
- **It writes machine code.** There is no C in between: no C is written, no C is read, and no C compiler is
  needed to build a program.
- **The entrypoint sets the order up and nothing else**, so the shape of a compilation is one screen.

**What is being ported, and from where.** The old compiler is the thing being ported, and it is the reference
for every rule:

| What | Where it is |
|---|---|
| the compiler being ported | [`../SpiteLanguage/compiler`](../SpiteLanguage/compiler) |
| the ideas this compiler is built on | [`new_compiler.md`](../SpiteLanguage/new_compiler.md) |
| the language, normative | [`specs/`](../SpiteLanguage/specs) |
| the language, taught | [`docs/`](../SpiteLanguage/docs) |
| the 263 programs that must fail with the same texts | [`diagnostics/`](../SpiteLanguage/diagnostics) |
| the corpus the compiler must pass | [`conformance/`](../SpiteLanguage/conformance) |
| the suite that says whether it does | [`check.sh`](../SpiteLanguage/check.sh) |
| what the old compiler does and does not do | [the table below](#what-the-original-compiler-has-that-this-one-does-not) |

**The old compiler's rules are this compiler's rules.** Every diagnostic it writes is one this compiler must
write too, with the same words, at the same line, and the same `(in Class.Function)`. The list is in **every
error the original reports** below, and the suite that checks them is in **what the original test suite asks
of us**.

## Priority: `spite .` in this folder builds the compiler

Asked and answered: **no, not yet.** What happens today, exactly:

- `spite .` fails, in both compilers. A program folder is named in snake_case (the language's rule, and the
  new compiler's mapping refuses a folder that is not), and this folder is `SpiteCompiler`. The old
  compiler answers `error: '.' holds no program: a program is a folder holding an
  entry file named after it, './SpiteCompiler.spite'`, and the new one answers
  `error: the folder 'SpiteCompiler' is not named in snake_case: every folder of a program is lowercase
  words joined by '_', so rename it 'spite_compiler'`.
- The build goes through the junction, which is the same folder under a snake_case name, and the compiler
  is written to `.spite/spite.exe` so it is never mixed up with the old compiler's own:

      bash ../SpiteLanguage/bin/spite .spite/spite_compiler --build --executable-path=.spite/spite.exe

  That command also *runs* the compiler, and the run fails: the compiler cannot compile its own source
  yet, so the exit code is 1 even though the executable is written. `--build` skips the run.
- The executable's name is the entry file's name in snake_case, `spite_compiler.exe` ✓.

The tasks, in the order they are needed:

- [ ] **The program's own folder.** The rule says a program folder is named in snake_case, and this one is
      not, so the junction is the way in and the command is longer than `spite .`. Either the repository's
      folder is renamed, or the rule is relaxed and both compilers follow it.
- [ ] **The compiler compiles its own source.** That is the whole language, the runtime the imported
      library needs, the memory model, and the errors: the milestones below, in the order they are written.
      Until then `spite .` cannot run the compiler on the compiler, and the run of the built program fails.
- [ ] **A failed step stops the run there, and its errors reach the report.** The entry error was written
      and then the compiler went on to read an empty class, and a second error came out; and the mapping
      kept its own report, so the errors it found (a folder that is not in snake_case, a folder loaded
      twice, a folder inside another, the reserved name) never reached the compiler at all. Both are fixed
      ✓; the same has to hold for every step, so the rule is worth a test of its own.

## Priority: the hot reload is faster than C, from the start

`HOT_RELOAD.md` is the document: how the reload has to work, and every risk in it. This is the short of it.

The original compiler reloads a running program by spawning itself, compiling the changed classes into a
library beside the executable, and having the running program load that library and swap the new code in.
Its own numbers, for a small program of four classes (from
`../SpiteLanguage/benchmarks/a_reload_compiles_only_the_classes_that_changed`):

| Step | The original |
|---|---|
| the whole build | 5.2 s |
| a reload of the unchanged files | 0.3 s |
| a reload after a function's body changed | 1.7 s |
| a reload after a class gained an attribute | 4.8 s (the whole program again) |

Most of that 1.7 s is one run of the C compiler, and the rest is reading and checking every class, the
library's included. A compiler that writes machine code has neither cost, so the reload is faster by the
whole of the C compile, and faster again by not reading what did not change. The target is a reload of a
changed function in well under a tenth of a second, and one with nothing changed in milliseconds.

**Three decisions lock a fast reload out, and they have to be taken before the code that would have to
change later is written.** None of them is a big change now, and each is expensive later:

- [ ] **A call goes through a slot in a development build.** The original writes every call in a
      `--hot-reload` build as a forwarder to a slot, so the new code can be put in the slot and the running
      program calls it without being rebuilt. Our low representation's call is a direct call, so there is
      nowhere to put the new code and a reload cannot swap a function at all. The low representation needs a
      call that goes through a slot, and the emitter needs the table of them. The cost is only in the builds
      that ask for it (the original: *REPL, live reload and debug machinery only in those builds*).
- [ ] **The layout is decided once and kept.** A reload that gives a class a new attribute moves the live
      objects, so the original falls back to compiling the whole program (the 4.8 s row). The layout of
      every class is therefore part of the development memory, not a thing each build decides again: a
      reload reuses the layout the running program was built with, and a change that would move an object is
      refused or paid for in full.
- [ ] **The generator writes a module as well as an executable.** A reload needs a library beside the
      executable, with the same layout, and an `install` the running program calls to put the new code in
      the slots. Our generator writes one PE file, so it needs a second shape: the same emitter, a different
      file around it.

**The caches are the engine of it.** The original caches what the C compiler compiled, so a reload compiles
only what changed. Ours caches each step's answer, per unit, keyed by the hash of what went in, so a reload
redoes only the steps whose input changed:

- [ ] **The cache is per step and per unit.** A class's file, its parsed tree, its resolved types, its high
      representation, its lowered instructions, its machine code and its layout are each cached under the
      hash of what the step before it answered. A change to one file re-runs one file's steps and nothing
      else.
- [ ] **The cache is on disk and in one binary format.** A reload is a separate process (the running
      program spawns the compiler, as the original does), so the cache has to be read from disk, and reading
      it has to be cheaper than doing the work. The development memory the compiler keeps while it runs
      (the program it has read, the layout it has decided) is the same cache, in memory.
- [ ] **The machine code is cached per function.** This is the biggest win: the original's reload pays for
      a C compiler run, and ours pays for nothing but writing the new bytes.
- [ ] **The compiler has a reload mode.** It is given the running executable, it reads what the last build
      recorded (the files it saw and their hashes), it compiles what changed, and it writes the module and
      the state beside the executable, or answers that nothing changed.
- [ ] **It is measured.** A benchmark of the reload, beside the original's, so the claim is a number and not
      an adjective.

**What is not a lock-out.** The rest of the plan can be done in any order: the language, the memory model,
the proofs, the errors and the outputs all stand on their own, and the optimisation passes (last) are per
function, so a reload's optimisation of the changed class does not change the others.

## The goal

Two steps, and the second is the one that matters.

1. **The old compiler builds the new one.** It already does: the new compiler's source is Spite the old
   compiler accepts, and `bash ../SpiteLanguage/bin/spite .spite/spite_compiler`
   builds it. Every change here keeps that true, because the new compiler is written in the language the
   old one compiles.
2. **The new compiler builds the original repository's test suite.** The new compiler compiles every program
   under `../SpiteLanguage`, runs it, and gives what the original compiler gives: the same output,
   the same count of allocations and frees, and the same errors with the same texts.

Step 1 holds today. Step 2 is what the list below is for, in the order it is done.

## What this compiler is

- **It writes machine code.** The low representation is printed to a Windows x86 executable. There is no C
  anywhere in this project: no C is written, no C is read, and no C compiler is needed to build a program.
- **It imports the standard library.** The library lives in another repository (`../SpiteLanguage/library`)
  and this project does not provide it, change it or carry a copy of it. The compiler reads it as a program
  loads any other folder, and compiles it.
- **It reads what the program needs.** The mapping and the symbols read only the classes something names, so
  nothing is read that is not needed.

## The pipeline

`spite_compiler.spite` sets the order up and nothing else, so the shape of a compilation is one screen:

    read the command line
    map every folder the program can use          (mapping)
    resolve and read the classes that are named  (symbols)
    lex and parse each class that was read       (abstract_syntax_tree)
    check that a file is ordered                  (abstract_syntax_tree/ordering)
    resolve every type written, and monomorphise every generic  (name_resolution)
    build the high representation                (high_intermediary_representation/builder)
    fold constants                               (high_optimization_passes/fold_constants)
    drop what nothing reaches                    (high_optimization_passes/drop_unreachable_functions)
    lower to instructions                        (low_intermediary_representation/lowering)
    thread and shorten jumps                     (low_optimization_passes/peephole_jumps)
    fold away moves                              (low_optimization_passes/fold_away_moves)
    write the bytes and the file                 (generators/windows_x86)

Each step takes the previous step's answer as its input and hands its own answer to the next one. No step
reaches back into another. Each error is written down as soon as the step that owns it finds it, and the
run stops there.

## Done

- **The command line.** `spite <path>`, always with the path written. `spite low-ir` runs the back half of
  the pipeline on the sample program and prints the instruction list.
- **The mapping** (`mapping`). Folders become namespaces. A folder loaded twice, a folder inside another, a
  folder or a file not named in snake_case, and the reserved name `Spite` are all errors, and they reach the
  compiler's report. No file is read. A path is resolved before it is compared, so a load written relative to
  the program that holds it is not taken for a folder inside that program.
- **The symbols** (`symbols`). A written name is resolved to a class file by searching the enclosing
  namespaces outwards and then each loaded root, and only that file is read, and only the classes it names
  are followed. A program that never mentions `JsonWriter` never reads `json_writer.spite`.
- **The loads.** A program names the folders it loads in its first line, and the symbols step follows the
  load lines: the folder is mapped, and its classes are found by name. The compiler does not go looking for
  a library, and there is no environment variable that names one.
- **The syntax tree** (`abstract_syntax_tree`). The lexer, the parser, the shapes, the ordering check (a
  file is ordered, a name is declared once, a constructor is not empty) and the walk.
- **The name resolution** (`name_resolution`). Every type written in the program is resolved, the two kinds
  of dependent type (`x.class` and `$type.member`) are answered, and every generic class found is
  monomorphised: `List<Integer>` mints `List_of_Integer`, once however many times it is written. A member
  read on a type parameter is a codegen value, and it is a note, because the original gives the type
  argument at run time and the compiler cannot know it while it reads.
- **The whole standard library reads.** A program that names every class of the library reads all 145 of
  them, with no error: 27 generic classes and 54 monomorphised instances.
- **The high representation** (`high_intermediary_representation`). The program as values and control flow,
  and the builder that lowers a class into it with the substitution of its instance applied. A call names
  the class that owns the function it reaches, so two functions of one name are told apart, and the class
  of a receiver comes from the type its name is declared with or from the class a call answers, which the
  name resolution answers for every class it reads. An `if` is lowered, with or without an `else`.
- **The reopening.** Two files may declare the same class. Every file that declares it is kept, all of them
  are read, and their declarations are merged: a later declaration replaces an earlier one of the same name,
  and the names the later one does not have are kept. The class the rest of the compiler sees is one file.
- **The high passes** (`high_optimization_passes`). `fold_constants` folds the arithmetic it can fold, and
  `drop_unreachable_functions` drops the functions and the classes nothing reaches.
- **The low representation** (`low_intermediary_representation`). The program as a flat instruction list
  over virtual registers, the lowering that builds it, and the describer that prints it.
- **The low passes** (`low_optimization_passes`). `peephole_jumps` threads and shortens the jumps, and
  `fold_away_moves` folds a load into the move that wrote it, when that is safe.
- **The generator** (`generators/windows_x86`). A 32-bit PE for Windows with two sections, importing
  `ExitProcess` from `kernel32.dll`, and the program answering its entry constructor's value as the process
  exit code. The emitter writes the whole number arithmetic, the comparisons, `while`, the calls between a
  program's own functions and `return`. The division is a signed one, the way Go has it.
- **The decisions** (`DECISIONS.md`), one row each, in the order they were made.

### The programs that prove it

The tests live in `../SpiteSpec/tests`, one folder per program, and the compiler writes each one to
`<program>/.spite/build/<name>.exe`.

| The program | What it is | What it answers |
|---|---|---|
| `../SpiteSpec/tests/exit_code` | whole numbers, a loop and a call with an argument | 4072 |
| `../SpiteSpec/tests/sum` | whole numbers and a loop | 10 |
| `../SpiteSpec/tests/two_names` | two classes with a function of one name, a call on an instance and the class nothing reaches | 3 |
| `../SpiteSpec/tests/branches` | an `if` with an `else` inside a loop, and an `if` that answers | 21 |
| `../SpiteSpec/tests/chains` | a call on a value a call answers, and two classes with a function of one name | 14 |
| `../SpiteSpec/tests/whole_library` | every class of the standard library named, so the whole library is read | 0 |
| `../SpiteSpec/tests/receivers` | a receiver that is a call of another class's function, and two classes with a function of one name | 18 |
| `../SpiteSpec/tests/divisions` | a whole number divided and taken the remainder of, in a loop | 210 |
| `../SpiteSpec/tests/objects` | a class with an attribute, a constructor that makes one and a method that takes it | 6 |

    .spite/spite.exe ../SpiteSpec/tests/exit_code
    ../SpiteSpec/tests/exit_code/.spite/build/exit_code.exe

## What the original compiler has that this one does not

The original compiler lives in `../SpiteLanguage/compiler`. This is what each of its parts has
that this compiler does not have yet, and what this compiler does instead.

| The original | What it has | What this compiler has instead |
|---|---|---|
| `source/syntax/` | The lexer, the parser, the printer, and the **formatter** (the compiler rewrites every file in the one style and reads the program again) | The lexer, the parser and the ordering check. No printer and no formatter yet. |
| `source/analysis/` | The class, function, field, parameter, enum, union, template and type information of every class | The name resolution, which answers the types, mints the instances, and answers the class every function of every class answers. The class, function and field information is missing. |
| `source/discovery/` | The whole program discovered before anything is written, `load` from a git repository pinned to a commit, the paths, the versions | The mapping and the symbols, which read only the classes something names. No `load`, no packages, no versions. |
| `source/intermediate/` | The intermediate representation and its passes: the layout and the placements, the ownership and the reference counts, the reachability, the proofs, the reflection lowering, the statement and expression lowering | The high and the low representation, with two passes. The layout, the ownership, the proofs and the reflection are missing. |
| `source/generation/` | The C generator: eighty files that write the C of the whole language, the tree shaking, the inlining, the specialisation, the templates, the member templates, the codegen values | The x86 emitter, which writes whole numbers and the control flow. The C generator is not to be reproduced: this compiler writes machine code. |
| `source/generation/prelude.spite` | The runtime, as C the compiler injects: the allocator, the console, the file and directory calls, the clock, the sockets, the process calls, the dynamic library, the weak references, the typed memory | Nothing yet. The same runtime is needed, as machine code the emitter writes (see below). |
| `source/backend/` | The high-level backend and the Windows executable writer | The PE writer (32-bit, where the original writes 64-bit). |
| `source/translation/` | The C split into translation units, compiled in parallel and cached | Nothing, and nothing is wanted: there is no C, so there are no units. |
| `proof/verification/` | The test harness written in Spite: the job pool, the verifier, the kept compiler | Nothing. The original repository's `check.sh` is the harness today. |
| `launcher/launcher.spite` | The launcher, which loads the library, the system's folder of it and the program's folder, in that order | The mapping loads the program's folder and the library directly. |
| `compiler/build.spite`, `compiler/environment.spite` | The compiler's own settings | Nothing: the new compiler has no settings yet. |

The features that come with those, in the order the original repository's own documentation lists them:

- **The formatter and the linter.** Every compile formats the program first, so what is compiled and every
  line an error names is the formatted file. The linter's rules (the snake_case names, the abbreviations, the
  unused names, the ordering, one statement per line, a call never inside a call, a constructor never an
  argument, the terminal `if`) are compile errors, not warnings.
- **The whole language.** Strings, lists, dictionaries, references and objects, enums, unions, `type` shapes,
  the attributes, the functions as values, the variadics, the operators as functions, the member templates,
  the codegen values, `if`, `switch`, `assert`, `crash`, the nullable narrowing, and every number type with
  its casts.
- **The memory model.** The reference counting, the heap, the placement of an object in a frame or on the
  heap, the weak references, the allocation counting and the report of what leaked.
- **The concurrency.** `Concurrent` and `Parallel`, the scheduler, the thread pool, the locks, the waits.
- **The reflection.** `Spite.Class`, `Spite.Function`, `Spite.Namespace`, the instances, the attributes read
  as values.
- **The packages.** `load` from a git repository pinned to a commit, the namespaces, the reopenings, and two
  versions of one repository at once.
- **The tree shaking and the inspectable build.** A production build keeps only what the program uses; an
  inspectable build keeps everything, for the REPL and the hot reload.
- **The proofs.** What the compiler establishes while compiling: the overflow checks, the bounds, the
  ownership, the call effects, the things it can fold.
- **The build options.** `check`, `build`, `executable_path`, `final_classes`, `optimization_report`,
  `high_ir`, `optimized`, `development`, `repl`, `repl_port`, `hot_reload`, `debug_memory`,
  `trace_asserts`, `target_operating_system`.
- **The outputs.** The executable, the crash report map (`<program>.crashes`), the merged classes
  (`--final-classes`), what could not be optimised (`--optimization-report`), the high representation
  (`--high-ir`).
- **The REPL and the hot reload.** The REPL on a running program, and swapping changed classes into it.
- **The seeds.** The committed fixpoint the compiler starts from: the original keeps C, and this one keeps a
  binary, since it writes machine code.

## The missing, in the order to do it

The milestones below are the work, in the order it unblocks the next. The detail of each is in the three
lists that follow: **every optimisation the original does**, **every proof the original makes**, and **every
error the original reports**. A milestone is done when the items of it are done, not when the list below is
ticked.

**Where the work is now.** The whole standard library reads, the name resolution answers the class every
function answers, and the emitter writes the whole number arithmetic, the division included. The next
thing is the object: a class instance, its attributes, and a method that takes the instance as its first
argument. Everything after it (the strings, the lists, the runtime the library asks for) needs an object
to live in, so it is the one that unblocks the rest.

**The standard library has moved and is written again.** It is in `../SpiteStandardLibrary` now, and it is
written with nothing implicit: a class that needs memory holds a `Buffer`, and the methods the compiler used
to supply are written in the library. The classes move one at a time, as the compiler needs them, and the
list is in [`../SpiteStandardLibrary/TODO.md`](../SpiteStandardLibrary/TODO.md).

### 1. The program runs

Until this is done, only a program of whole numbers with a loop and a call can be built. Everything here is
what the imported library and the original repository's corpus, examples and documentation programs need.

- [ ] **The runtime the imported library needs.** The library declares functions it does not define, and
      the compiler supplies those bodies: the allocator, the console's writing, the file and directory calls,
      the clock, the sockets, the process calls, the dynamic library, the weak references, the typed memory.
      The original supplies them as C in its prelude; we supply them as machine code the emitter writes.
      For now those bodies are keyed by the library's class names, which couples the compiler to the library
      in the old repository. The language has to give every library the same way to reach the C library and
      the memory, so that a library brought from elsewhere needs nothing from the compiler but the language
      (see the decision below).
- [ ] **The foreign calls.** The library reaches the C library through `DynamicLibrary`, naming the C
      function it wants (`library.fopen_as_long(path, mode)`), so a compiled program must be able to call a
      function in a DLL by name, with the calling conventions of the C library. The naming of the answer's
      type is the language's, so any library can use it. The compiler writes the call, the name of the C
      function in the program's data, the address it answers in the program's data so that it is resolved
      once, and the call through that address ✓; the bodies the compiler supplies for the `DynamicLibrary`
      itself (`open_library`, `find_symbol` and `close_library`) are not written yet, and they need the text
      a library's name is written in, which is the text the strings are made of.
- [ ] **A library brought from elsewhere works.** The compiler names no class of the standard library, and a
      program that loads a different one is compiled the same way. The library in the old repository is the
      one loaded for now, and nothing about it is in the compiler.
- [ ] **The memory.** The heap the library allocates from, the reference counting, the freeing of what a
      program takes, and the count the corpus checks (`allocations: N frees: N`). Twenty-seven corpus
      programs pin that count in an `allocations.txt`, so what is allocated and what lives in a frame has
      to be decided as the original decides it, and not only be correct.
- [ ] **The standard library without magic.** The library is written again, one class at a time, as the
      compiler needs it: a class that needs memory holds a `Buffer` and says how much room it needs, and the
      methods the compiler used to supply are written in the library. The list is in
      [`../SpiteStandardLibrary/TODO.md`](../SpiteStandardLibrary/TODO.md).
- [ ] **The objects.** A class is a pointer to its own block: the attributes live in the object, the methods
      take it as their first argument, and the objects are made and released. The original puts an object
      that never leaves its function in the frame and the rest on the heap, and the compiler decides the same
      way, one proof at a time: each proof is a pass of its own, so the frame is the first one and the heap
      comes when the runtime the library asks for is there. The block, the attributes and the method are
      built ✓; the proof that an object never leaves its function, and the heap for the ones that do, are
      not.
- [ ] **The strings**, and the text literals with their holes.
- [ ] **The lists and the dictionaries**, with their templates and their member templates.
- [ ] **The references**, the enums, the unions and the `type` shapes.
- [ ] **The functions as values**, the variadics and the operators as functions.
- [ ] **`if`, `switch`, `assert` and `crash`**, and the narrowing of a nullable.
- [ ] **The number types** and their casts, and the overflow checks the proofs remove.
- [ ] **The proofs.** What the compiler establishes while compiling: the ranges of the numbers, the bounds
      of the reads, the ownership, the call effects. The corpus checks both ways: a program that overflows
      must crash, and a program whose range is proven must not. The list of all of them is in **every proof
      the original makes** below.
- [ ] **The concurrency**, the reflection, the `load` of a package, and the codegen values.

### 2. The errors are the same

The original repository has 263 programs under `diagnostics/`, each with the exact text it must fail with.
The text names the file, the line, the class and the function, and says what to write instead, so the
compiler has to know the library's members and their signatures to answer them.

- [ ] The diagnostics have the same texts, the same `file:line` and the same `(in Class.Function)`. The
      list of all of them is in **every error the original reports** below.
- [ ] The linter's rules are compile errors, as they are in the original: the naming, the abbreviations, the
      unused names, the ordering, one statement per line, a call never inside a call, a constructor never an
      argument, the terminal `if`.
- [ ] **The errors of the compiler itself** (a flag that names no field, a path that is a file, an entry
      constructor that takes arguments) have the same texts. The list of all of them is in **every error the
      original reports** below.

### 3. The outputs are the same

- [ ] **The launcher.** The original compiler reads `launcher/launcher.spite` first and loads the library,
      the system's folder of it and the program's folder in that order. This one maps the folders itself, so
      it must load them in the same order, and load a program's own `build.spite` and `environment.spite`.
- [ ] **The standard library is a folder the program loads**, like any other folder, and the path is the
      program's to choose. The library in the old repository is the one loaded for now, and it is found
      through the environment (`SPITE_STANDARD_LIBRARY`) or the path the program gives.
- [ ] **The build options that choose an output**: `--check`, `--build` and `--executable-path`. The
      original's `--optimized` asks a C compiler for `-O3` and link-time optimisation, which has no meaning
      here; the equivalent for this compiler is its own optimisation passes, and those come last.
- [ ] **Where the outputs go.** `.spite/build/<program>/<program>.exe` in the folder the compiler was run
      from, and nothing beside the program's source unless a path says so.
- [ ] **The crash reports**, and the `<program>.crashes` map from a report's site ids to their lines. The
      corpus checks what a crash prints, and what a fault prints: the faulting place, the last foreign call
      and the frames it walked.
- [ ] **The allocation count** (`--debug-memory`), and what the corpus compares it against.
- [ ] **The optimisation report** (`--optimization-report`), the file that says what could not be
      optimised and why. One corpus program reads it and checks its text, so the compiler's decisions have
      to be the original's: the lists that hold references, the lists and the objects that are not in the
      frame, the copies that are not elided, the overflow checks that are kept, and the waits that hold
      the frame. The list of all of them is in **every optimisation the original does** below.
- [ ] **`--final-classes`**, the printer: the program written back out as Spite, one file per class.
- [ ] **The REPL and the hot reload** (`--repl`, `--repl-port`, `--hot-reload`, `--development`), and the
      development memory they need.

### 4. The compiler proves itself

- [ ] **The formatter.** Every compile formats the program first and reads it again, so what is compiled is
      the formatted file. A file that changed while it was being compiled is left alone and the program is
      read again.
- [ ] **The compiler compiles itself**, and the executable it writes is the executable it is (the fixpoint
      the original proves with generation 3).
- [ ] **The seed.** The original keeps the fixpoint C; this one keeps the fixpoint binary, since it writes
      machine code.
- [ ] **The verification harness**, in the shape of `proof/verification/`: a job pool that runs the corpus,
      the examples, the documentation's programs, the diagnostics, the tests and the benchmarks, and reads
      the answers in a fixed order.

### 5. The rest

- [ ] **The programs of the old repository name the library.** A program's first line loads it, because
      the launcher is gone: `load "<path>/library"` and `load "<path>/library_windows"`. The programs under
      `../SpiteLanguage` (the examples, the corpus, the documentation's programs) do not do that
      yet, so the new compiler cannot read them, and they are the test that says whether it is compatible.
      The old compiler cannot follow that either: it loads the library twice, once through the launcher and
      once through the program, and gives a loaded platform folder the namespace of its own name.
- [ ] **The library is loaded the way the new compiler loads it.** While the old compiler builds this
      compiler, the library is the release's own shape: the Windows part sits inside it, as
      `.spite/spite-0.0.6-windows/library/windows`, and the launcher loads it. The old compiler cannot have
      the program name it, and says so: the compiler's own prelude reopens the library's `Spite` classes, and
      it may only do that when the library was loaded as the library, which is the launcher's doing
      (`'Spite' holds the standard library's own classes, so a file in a 'spite' folder may only reopen one
      of them`). After the bootstrap, the library is the program's to name, in its first line, and the parts
      are:
  - [ ] **A loaded folder reopens a class another folder declares.** Two folders, one class: the one
        loaded later wins, and the members of the earlier are kept. The mapping keeps one class per name
        today, so the shared part of the library is lost when the Windows part is loaded.
  - [ ] **The load order is the order the program says.** The folders a program loads come before the
        program itself, so a program's own file reopens what the library declares, the way the launcher
        loaded the library first. A file that is loaded later replaces the earlier declaration of a name,
        and the earlier keeps the names the later does not have.
  - [ ] **A change to a file that lost the load priority changes nothing.** The declaration that wins is
        the one the program runs, so a save in a file that only loses decides the class is not the class
        that runs, and the reload must leave the code in memory alone. This is the same fact the manifest
        holds, and it is why the fact is written down when the class is compiled.
  - [ ] **A folder named after an operating system is not a namespace.** The Windows part is the library's
        classes again, not `Windows.File`, and only the target system's folder is loaded at all.
  - [ ] **The old compiler's rules about the library go.** "Only the library may read the memory at an
        address" is a rule about a folder name, and it stops when the library is any folder a program
        names.
  - [ ] **This compiler's own entry file names the library**, the way every other program does, when the
        new compiler is the one that builds it.
- [ ] **The cache per step**, so restarting a compilation redoes only the work that changed.
- [ ] **The tree shaking**, and the inspectable build.
- [ ] **The optimisation passes**, ours and not the original's: the register allocation, the folding of the
      constants the proofs reach, the elision of the copies. These come last, after the compiler works, and
      they are for the speed of the programs it writes, not for their behaviour. The list of what the
      original does is in **every optimisation the original does** below.

## Every optimisation the original does

One line each, so none is forgotten. The ones under *Not ours* are about the C the original writes,
and this compiler writes machine code instead. The rest are ours to do, and each one needs the
feature its group names. The original writes each of them down with the case that shows it, in
`../SpiteLanguage/docs/optimizations.md`.

### The tree shaking and the compile-time questions

- [ ] Deciding conditions at compile time
- [ ] Reflection, symbols and registries only where read
- [ ] Reflection on constants folds and unrolls
- [ ] Template chains run as one loop
- [ ] A function taking a `type` is compiled per class
- [ ] A test against a value a list never holds is decided while compiling
- [ ] A table filled once is read as constants
- [ ] A dictionary written out and only read by literal keys is folded
- [ ] Maths on constants is worked out while compiling
- [ ] A binary schema is a constant
- [ ] A word inflected while compiling
- [ ] Identical functions are folded into one

### The memory, the placement and the copies

- [ ] The compiler places memory
- [ ] Reading an address is one machine operation
- [ ] Objects that never leave their function live in the frame
- [ ] A local list of known size lives in the frame
- [ ] A variadic list the callee only reads lives in the caller's frame
- [ ] A list held only by another list lives in its slot
- [ ] A list of lists filled again keeps each list's room
- [ ] Objects of one class sit together
- [ ] A row of borrowed items lives in the frame
- [ ] An `Items`' storage is chosen while compiling
- [ ] A deep copy is written per class, with a table only where a graph needs one
- [ ] A deep copy nothing changes is the original
- [ ] Copies that cost nothing
- [ ] Allocation is the C library's, counted only where read

### The counts

- [ ] Singletons: made on first use, never counted
- [ ] Singletons that hold nothing are static objects
- [ ] Atomic reference counts only with threads
- [ ] Plain reference counts where no thread reaches a class
- [ ] An argument its caller holds is passed without counting
- [ ] An attribute a call cannot assign is passed without counting
- [ ] Storing an object into a list counts it only when it changes the slot
- [ ] An item passed to a call that cannot change its list is not counted
- [ ] A singleton's attribute that never changes is read in place
- [ ] A list's templates read its elements without counting them
- [ ] An item written back to its own slot is not written
- [ ] A list item read only to test it is not counted
- [ ] A write-back of what the slot already holds is not written
- [ ] An item a name holds from its list is not counted
- [ ] Reading through a `type` without counting
- [ ] Objects made for their owner are told apart
- [ ] Counts stay plain for what one of the calls run at once counts

### The text, the numbers and the collections

- [ ] Appending to text in place
- [ ] Text joined in one piece
- [ ] A number joined into text is written in place
- [ ] Short text lives inside the `String`
- [ ] Short symbols are inline text
- [ ] A foreign name is never copied
- [ ] Crash text out of the binary
- [ ] A number's bits are read in place
- [ ] A decimal literal beside a `Float` is a `Float`
- [ ] A proven divisor is not checked
- [ ] Arithmetic is checked in every build
- [ ] Arithmetic a range proves is not checked
- [ ] A loop over plain values reads its count once and its items unchecked
- [ ] A proven read tests only its bounds
- [ ] A number read from bytes is one load
- [ ] A walked `crash` line's read is the row's read
- [ ] Boxing only where a value travels as a shape
- [ ] A function value describes its arguments when asked
- [ ] Defaults the constructor replaces are never made
- [ ] Proofs that survive a call
- [ ] A dictionary hashes a key once, cheaply
- [ ] A dictionary keyed by numbers hashes the numbers

### The threads

- [ ] Concurrency machinery only where it is used
- [ ] Hidden async/await as compile-time state machines
- [ ] Reads in a row overlap
- [ ] A wait in a frame does not hold the frame
- [ ] The thread pool only where a `Parallel` is made
- [ ] Singletons a `Parallel` reaches take a lock
- [ ] Thread safety for singletons, the cheapest safe form
- [ ] While no task runs, a singleton's lock is skipped
- [ ] A singleton no other thread reaches takes no lock
- [ ] A singleton's reading functions do not exclude each other
- [ ] A counted loop of calls to one singleton takes its lock once
- [ ] An attribute read only under its singleton's lock is a plain number
- [ ] A loop of calls to one singleton tests for tasks once
- [ ] Thread safety for singletons, the rest of the plan
- [ ] Calls in a row run at once
- [ ] A loop over a list of different classes runs them at once
- [ ] A loop whose passes write only their own item runs in bands

### The compiler's own machinery

- [ ] REPL, live reload and debug machinery only in those builds
- [ ] A reload compiles only the classes that changed
- [ ] What a `--hot-reload` build carries so its objects can move
- [ ] The fault handler is in every program
- [ ] A crash's report is kept out of the way
- [ ] Smaller ones
- [ ] Other optimisations

### Not ours: the C the original writes

- [ ] Tree shaking the generated C
- [ ] The C is compiled in parallel units, and cached
- [ ] A release build is `-O3` with link-time optimisation
- [ ] A release is inlined in every unit

## Every proof the original makes

One line each, so none is forgotten. A proof is a fact the compiler establishes while compiling, and it
is what lets the compiler fold a check away, keep a value in a frame, or refuse a program it can prove
wrong. The original writes each of them down in `../SpiteLanguage/docs/proofs.md`, and the same
rules hold here: a program that is wrong must be refused, and a program that is right must not pay for
a check nothing needs.

### Presence and control flow

- [ ] Narrowing a `T?`
- [ ] Every side of an `and` narrows
- [ ] An `if` that leaves proves the rest
- [ ] Assigning undoes a proof
- [ ] A call keeps a proof it cannot change
- [ ] Proving what is proven is an error
- [ ] A copy made to narrow is an error
- [ ] A class test narrows its block
- [ ] Every path ends in a `return`
- [ ] A guard `assert` answers only "nothing"
- [ ] A switch covers every case

### Indices and numbers

- [ ] A proven count or bound proves a read
- [ ] A proven read halts outside its list
- [ ] A proven count or bound proves a read of a width
- [ ] An index built from loop counters is proven by one guard
- [ ] A counted loop reads its items unchecked
- [ ] A proven divisor is not checked
- [ ] A divisor written as zero is an error
- [ ] Arithmetic that does not fit halts
- [ ] A range proves arithmetic fits
- [ ] A wider operand is written first
- [ ] Maths on constants is worked out while compiling
- [ ] A dictionary only read by literal keys is never made

### Compile-time questions

- [ ] Conditions decided while compiling
- [ ] Whether a function waits
- [ ] How many arguments a function takes
- [ ] Whether a class fits a `Vector`
- [ ] Whether a function writes a parameter
- [ ] Whether a class keeps state
- [ ] The one class a `type` admits
- [ ] A `crash` that folds false is a compile error
- [ ] Tree shaking: what `main` can reach
- [ ] A reload compiles only the changed classes
- [ ] A reload reaches every object whose attributes it changes

### Memory

- [ ] A buffer freed in its block lives in the frame
- [ ] Objects that never leave their function live in the frame
- [ ] Local and variadic lists in the frame
- [ ] A function value its callee only calls lives in the frame

### Borrowing and lending

- [ ] Borrowed items of a `Vector` or `Items`
- [ ] No borrowed read past a resize
- [ ] Rows of borrowed items
- [ ] An item lent to the caller
- [ ] An item lent to a call
- [ ] A list element lent to a row
- [ ] An argument its caller holds is passed uncounted
- [ ] An attribute a call cannot assign is passed uncounted
- [ ] A singleton attribute that never changes is read in place
- [ ] A list's templates read their elements uncounted
- [ ] An item written back to its own slot is the slot
- [ ] A value followed through calls is the slot it was read from
- [ ] An item a name holds from its list is not counted
- [ ] A list item read only to test it is not counted
- [ ] An item used at once is not counted
- [ ] A list held only in a slot of another list
- [ ] A list only its class fills holds only what it fills
- [ ] A table filled once holds what its setup put in

### Threads and locks

- [ ] Calls that share nothing written
- [ ] Classes in a list that share nothing written
- [ ] Passes that write only their own item
- [ ] An object made for its owner is told apart
- [ ] No other thread counts a class
- [ ] What one of the calls run at once counts
- [ ] Objects of a class made on one thread
- [ ] A copy nothing changes is the original
- [ ] Which singletons a `Parallel` reaches
- [ ] No other thread touches a singleton
- [ ] Read-only and atomic singletons
- [ ] A function that touches no changing state takes no lock
- [ ] Reading functions share the lock
- [ ] A counted loop takes a singleton's lock once
- [ ] A loop that starts no task tests for tasks once
- [ ] No attribute is read past the lock
- [ ] A lock that would wait forever is an error
- [ ] A loop that can never end is an error
- [ ] A poll that nothing steps is an error
- [ ] A write to an object only this function holds must be read
- [ ] A name read from a list, assigned and never read, is an error
- [ ] What a `Parallel` may reach
- [ ] Which calls suspend a `Concurrent`
- [ ] A wait in a frame is started

### Other refusals built on an analysis

- [ ] Unused is an error: a name, parameter or attribute that is only written and never read
- [ ] A constructed object must be kept and used
- [ ] Singletons that make each other in a circle are an error
- [ ] Build settings are constants
- [ ] A value fits a `type`
- [ ] A member template fits
- [ ] A value can be written
- [ ] What crosses into C
- [ ] Reads in a row are independent
- [ ] The short form is proven the same, and the long form refused

## Every error the original reports

The original repository has 263 programs under `diagnostics/`, each with the exact text it must fail
with, and the compiler's own errors about the command line and the outputs. A program that must fail
must fail with the same words, at the same line, so the error is the same one a reader of the original
saw. Each line below is one of them, named by the program that checks it.

### The programs under `diagnostics/`

- [ ] address_forms — a File reads bytes into a Buffer, not into memory at an address: 'read_bytes_at(position, count)' answers a 'Buffer?' of up to 'count' bytes from 'position', and 'read_bytes()' the whole file
- [ ] allocator_after_use — 'spark' was already used, so its allocator can no longer change: an object's allocator is set on the line right after it is made. To move it, copy it and set the copy's: 'var moved = spark.copy()' and then 'moved.memory.allocator = ...'
- [ ] allocator_reads — only an object has an allocator of its own, and this is a value of type Integer, which the compiler places itself
- [ ] allocator_resizes — 'place' is borrowed from 'store.positions', and 'names.append()' on line 12 may move the items of 'store.positions', so 'place' is not read after it: read 'store.positions[index]' again after that line, or keep 'place.copy()', an independent object
- [ ] argument_class — 'Mender.mend' takes 1 arguments, so it has no parameter 1 for 'argument_class' to name: parameters are counted from 0
- [ ] argument_class_name — 'argument_class("repair", 0)' names the class of a parameter of 'Mender.repair', and 'Mender' has no function 'repair'
- [ ] argument_count — '$system_type.argument_count(...)' is decided while compiling, so the name it asks for is written as a literal: '$system_type.argument_count("update_each")', or a pattern such as "<phase>_each"
- [ ] atomic_misuse — 'crash $value_type == Number and $value_type != Float and $value_type != Double or $value_type == Boolean' always halts in Atomic<Float>: its condition is decided while compiling and is false, so the program would stop here every time this function runs: call it only where the condition holds, or change what the condition asks
- [ ] bitwise_on_float — a Float has no function 'shifted_right': the bitwise functions are on the whole numbers, Tiny to UnsignedLong. Cast it first, like 'var whole: Long = value'
- [ ] blank_line — formatted diagnostics/blank_line/blank_line.spite
- [ ] borrowed_name — diagnostics/borrowed_name/borrowed_name.spite:4:9: 'none' cannot name a variable, because Spite reads the word as a mistake anywhere it is used: the empty value is written 'null'
- [ ] borrowed_new — diagnostics/borrowed_new/borrowed_new.spite:4:18: there is no 'new' in Spite: a class is made by calling its own name, like 'Creature("rat")'
- [ ] borrowed_operators — Spite writes 'and' and 'or' as words: there is no '&&' or '||'
- [ ] borrowed_syntax — Spite has no '+=': write 'count = count + value'
- [ ] borrowed_this — diagnostics/borrowed_this/borrowed_this.spite:5:19: a class reads its own attributes by name: write 'name', not 'this.name'
- [ ] bound_proofs_undone — 'spans[at + 2]' may be missing, since every '[ ]' answers a 'T?' (this one is an Integer?), but a Printable is needed: narrow it first with 'crash spans[at + 2]', 'assert spans[at + 2]' or 'if spans[at + 2] { }', or read it where a bound proves it, inside 'while at + 2 < spans.count()'
- [ ] branch_undoes_proof — this value may be null (it is a Target?), so 'name' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] build_setting_type — error: '--workers=many' was given to the compiler, but 'Build.workers' is an Integer: a whole number, like --workers=3
- [ ] bulk_removal — 'remove_where' removes from the collection it is called on, and 'names.filter(is_short)' makes a new one that nothing keeps: call it on the collection itself, with one test that says everything to remove
- [ ] byte_reads — this value may be null (it is an Integer?), so '*' cannot use it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] call_as_argument — 'count_words(source)' is called inside an argument of 'console.print': compute it first into a named 'var' and pass the name
- [ ] call_undoes_proof — this value may be null (it is a Monster?), so 'name' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] cast_by_name — there is no 'Float.from_integer()': a conversion belongs to the value converted, so write 'value.to_float()' on an Integer, or cast by assignment: 'var converted: Float = value'
- [ ] check_proves_nothing — 'tracker' is already narrowed by 'assert tracker' on line 8: remove this check
- [ ] class_and_namespace — diagnostics/class_and_namespace/engine/renderer.spite: error: 'Engine.Renderer' is this class and also the namespace of the folder 'diagnostics/class_and_namespace/engine/renderer': a dotted name means one thing, so rename the file or the folder
- [ ] class_as_value — 'Health' is a class, not a value: write 'Health()' to make one, and give it a name with 'var ... = '; for the class itself, pass it where a 'Spite.Class' is wanted
- [ ] class_keyword — diagnostics/class_keyword/class_keyword.spite:1:1: there is no 'class' keyword: a file is a class, named after the file, and its attributes and functions are written at the top level of that file
- [ ] codegen_values — this class has no 'generic $other_type' line, so '$other_type' cannot be used as a type
- [ ] comment_broken_link — this comment links to 'notes.md#a-heading-that-does-not-exist', but that file has no heading with that anchor
- [ ] comment_inside_function — a comment may not appear inside a function or a declaration body: a line that needs explaining becomes a named function instead. a comment is one line holding only a link to a markdown section, like '# docs/memory.md#cycles', and only outside functions. Ask whether the note is needed: if a reader could work it out from the code, delete it; if it is lasting knowledge, write the section first and link to it; if it warns against a change, a test or a compile error pushes harder than prose
- [ ] comment_missing_file — this comment links to 'nowhere/missing.md', which does not exist (the path is relative to the folder of the file the comment is in, like load)
- [ ] comment_prose_comment — this comment is not a link: a comment is one line holding only a link to a markdown section, like '# docs/memory.md#cycles', and only outside functions. Ask whether the note is needed: if a reader could work it out from the code, delete it; if it is lasting knowledge, write the section first and link to it; if it warns against a change, a test or a compile error pushes harder than prose
- [ ] comment_slash_comment — Spite has no '//' or '/* */' comments: a comment is one line holding only a link to a markdown section, like '# docs/memory.md#cycles', and only outside functions. Ask whether the note is needed: if a reader could work it out from the code, delete it; if it is lasting knowledge, write the section first and link to it; if it warns against a change, a test or a compile error pushes harder than prose
- [ ] common_mistakes — 'Pet' has no attribute 'missing' to assign to
- [ ] computed_receiver — diagnostics/computed_receiver/computed_receiver.spite:6:44: '(start + offset).maximum(...)' calls a function on a value computed in place: name it first ('var named = start + offset') and call 'named.maximum(...)', since only a name calls a function
- [ ] conditions_and_returns — the condition of 'if' is an Integer, but it must be a Boolean: compare it with something, like 'count > 0' or 'name != ""'
- [ ] console_flush — 'Console' does not define 'flush'
- [ ] constructor_as_argument — 'CounterButton(screen.id)' is constructed inside an argument of 'screen.add': a constructor call is never an argument, so make it first on a line of its own, 'var counter_button = CounterButton(screen.id)', and pass 'counter_button'
- [ ] constructor_codegen_list — diagnostics/constructor_codegen_list/weapon.spite:3:12: a function no longer lists codegen values between '<' and '>': declare each at the top of the file on its own line ('generic $damage_type', 'generic $is_magic'), and write 'func Weapon(' here
- [ ] copy_to_narrow — 'watcher' only copies 'tracker' so it can be narrowed: narrow 'tracker' itself ('assert tracker') and use it directly
- [ ] copy_to_narrow_conditions — 'watcher' only copies 'tracker' so it can be narrowed: narrow 'tracker' itself ('assert tracker') and use it directly
- [ ] count_proves_no_key — 'names[0]' may be missing, since every '[ ]' answers a 'T?' (this one is a String?), so 'upper_case' cannot be called on it yet: narrow it first with 'crash names[0]', 'assert names[0]' or 'if names[0] { }'
- [ ] count_undoes_proof — this value may be null (it is a String?), but a Printable is needed: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] declaration_one_per_line — diagnostics/declaration_one_per_line/declaration_one_per_line.spite:2:13: enum declarations separate their entries by lines, not commas: delete the ','
- [ ] declaration_order — a variable comes after the constructor here, but a file is ordered: the singleton line, generic lines, enums, unions, types, variables, the constructor, then functions
- [ ] declaration_walk — 'describe' takes a 'Spite.Attribute', an attribute bound to an instance, and 'health' here is a declaration of 'Monster', which has no value: declare the parameter 'Spite.AttributeDeclaration', or walk an instance's attributes
- [ ] default_answer — this 'assert' would answer a default Integer (0) that a caller cannot tell from a real one: return a value ('if entity >= rows.count() { return -1 }'), make the result 'Integer?', or 'crash entity < rows.count()' if this is a developer mistake
- [ ] default_guard — this 'if' only returns the default 'null', which is how a guard is written: write 'assert not missing' and let the rest run unindented
- [ ] dictionary_type_arguments — a Dictionary names two types, its keys' and then its values', as in 'Dictionary<String, Integer>', and this one names 1
- [ ] dispatched_resizes — 'Position' fits a Vector, so the items of 'Column<Position>().values' are borrowed: 'place' is borrowed from 'Column<Position>().values', and 'console.print()' on line 12 may move the items of 'Column<Position>().values', so 'place' is not read after it: ask for the item again after that line, or keep 'place.copy()', an independent object
- [ ] division_by_constant_zero — 'total / 0' divides by zero, which always halts the program: a whole number cannot be divided by zero, so divide by something else, or leave the step out
- [ ] doubled_underscore — the function '__strike' must be written in snake_case: lowercase words joined by one underscore each, with at most one '_' in front to make it private
- [ ] dropped_construction — 'Report("the door opens")' makes a 'Report' and drops it: a constructed object must be kept and used, so a class whose construction is the whole point should be a function instead; turn 'Report' into a function of the class that needs it, or keep the object in a variable that is read
- [ ] duplicate_function — 'DuplicateFunction' declares 'twice' twice: a later file may reopen a class and replace a function, but one file declares each name once
- [ ] empty_collection_guard — this 'if' only returns the default 'List<String>()', which is how a guard is written: write 'assert not text.is_empty()' and let the rest run unindented
- [ ] empty_constructor — formatted diagnostics/empty_constructor/holder.spite
- [ ] empty_folder_range — 'add_system_wave' is 'add_system' for a class 'system_wave', but the folders named for 'System' hold only 'system_greet'
- [ ] endless_locked_loop — 'Window.run' holds Window's lock for the whole call, since a Parallel reaches Window, and this loop never ends, so every other call on Window would wait forever: move the loop into a class that is not a singleton, and call Window from it
- [ ] endless_parallel_work — 'Parallel(counter.count_forever)' runs 'Counter.count_forever' on the thread pool, and this loop never ends and never waits, so the work never finishes and keeps its thread for good: return from the loop once the work is done, or run the loop on the program's own thread
- [ ] entry_class_reopened — diagnostics/entry_class_reopened/bundle/entry_class_reopened.spite: error: 'EntryClassReopened' is the program's entry class (diagnostics/entry_class_reopened/entry_class_reopened.spite), so no other file may be a class of that name: rename this file, or the program's folder and its entry file
- [ ] entry_constructor_arguments — 'EntryConstructorArguments' is the entry constructor, and it takes no arguments: a program reads its run-time settings through Environment() (declared in its environment.spite, given on the command line beside the compiler's flags), what its build decided through Build(), and the raw command line through Arguments(), anywhere
- [ ] enum_from_text — text is not a Mood until it is read as one, and text that names none of its values has none to give: read it with 'to_mood()', which answers 'Mood?', null when the text names none of its values, and narrow it, or declare the value 'Mood?'
- [ ] enum_numbers — 'user' and 'guest' both have the number 8 in enum 'Role': a value's number is its identity, so give one of them another
- [ ] enum_reopening_replaces — 'fog' is not a value of this enum
- [ ] enum_value_templates — 'filter_draft' could read 'stage' or 'review', whose enums both list 'draft': write the comparison as a Boolean member of Post, or pass a function
- [ ] environment_setting — 'Environment.workers' is a setting, read from the program's command line (--workers=value) or its environment (WORKERS), so it is declared with only a literal default, and the literal is its type: 'var workers = false' (Boolean), 'var workers = 0' (Integer) or 'var workers = ""' (String)
- [ ] equals_keys — a Dictionary keyed by 'Badge' finds each key by identity, one object one key, but 'Badge' declares 'equals', so an equal 'Badge' would not be found: key the dictionary by what 'equals' compares, a number or a String
- [ ] every_attribute — 'count_attributes' calls 'count_attribute' once for every attribute, so 'count_attribute' has to return nothing
- [ ] failed_constructor — there is no generic class 'Asset.Pak' here: a name is looked up in this class's own namespace, its folder, each parent folder, then the whole program
- [ ] falling_end — 'sign_of' answers a String, but when 'value < 0' is false (line 28, an 'if' with no 'else') it reaches its end without a 'return', so a caller would get a String nobody wrote: end that path with 'return <value>', or with 'crash' if it cannot happen
- [ ] file_scope_statement — diagnostics/file_scope_statement/file_scope_statement.spite:3:1: a file holds declarations and nothing else: move this statement into a function, or into the class's constructor
- [ ] flag_given_twice — error: '--optimized' is given twice: a flag or a setting is given once
- [ ] flag_value — error: '--optimized=maybe' was given to the compiler, but 'Build.optimized' is a Boolean: --optimized, --optimized=true or --optimized=false
- [ ] folded_build_crash — 'crash build.serve' always halts: its condition is decided while compiling and is false, so the program would stop here every time this function runs: call it only where the condition holds, or change what the condition asks
- [ ] folded_crash — 'crash $slot_type.fits_vector()' always halts in Slot<List<String>>: its condition is decided while compiling and is false, so the program would stop here every time this function runs: call it only where the condition holds, or change what the condition asks
- [ ] folder_name — diagnostics/folder_name: error: the folder 'BadFolder' is not named in snake_case: every folder of a program, a package's own folder included, is lowercase words joined by '_', so rename it 'bad_folder'
- [ ] foreign_call_mistakes — a Console cannot cross into C: a foreign function takes numbers, Boolean, enum values, text and a type whose attributes are all numbers
- [ ] foreign_callback_mistakes — 'named' is called by C, which passes numbers and addresses: 'argument 1' is a String, so take it as a number, a Boolean or a Memory.Address (text C passes is read with 'terminated_text()')
- [ ] foreign_library_mistakes — 'fixture' has no extension: name the library file exactly as it is on disk, like "user32.dll" or "libc.so.6" (a wrapper for another platform names that platform's file)
- [ ] format_flag — error: '--format' is not a compiler option: every compile formats the program's own files first, and nothing turns that off: '--check' formats and checks a program without building it
- [ ] format_setting — 'Build.format' cannot be declared: every compile formats the program's own files first, and nothing turns that off: '--check' formats and checks a program without building it
- [ ] found_item_borrows — 'found' is borrowed from 'velocities', and 'velocities.append()' on line 9 may move the items of 'velocities', so 'found' is not read after it: read 'velocities[index]' again after that line, or keep 'found.copy()', an independent object
- [ ] from_conversion — 'Celsius.from_integer' makes a Celsius from another value, and a conversion belongs to the value converted: declare 'to_celsius()' on the class it converts from, or take the value in the constructor
- [ ] function_owner — 'Spite.Function<String, String>' has no attribute 'owner'
- [ ] function_reflection — '$system_type.has_function(...)' is decided while compiling, so the name it asks for is written as a literal: '$system_type.has_function("run_each")', or a pattern such as "<phase>_each"
- [ ] function_shape_default — 'held' is a Weapon, a type that requires the function 'strike', so '= null' has no default to make: no object can supply a function it does not have. Make its type nullable, with a '?', and narrow it before use, or give it a real object in the constructor
- [ ] function_value_mistakes — a Spite.Function<Nothing> cannot be used where a Spite.Function<String, String> is needed
- [ ] function_waits_paradox — whether 'Looper.update_each' can wait was answered false here, before the functions that ask 'function_waits' were compiled, and it is true once they are: it reaches one of them, or a function value made in one, so its answer would decide itself, so ask from a function that 'Looper.update_each' does not reach
- [ ] generic_class_in_comparison — diagnostics/generic_class_in_comparison/generic_class_in_comparison.spite:5:15: expected ':' followed by the field's value but found '='
- [ ] generic_constraint_not_a_type — '$count_type' is constrained by 'Integer', which is not a 'type': a constraint names a 'type' the class given must fit, like 'generic $count_type: Printable'
- [ ] generic_constraints — 'Pet' does not fit type 'Printable', which 'Shelf' requires of $item_type: it has no function 'to_string'
- [ ] grouped_operand_text — '2.0 * (first + second)' is a multiplication in Float, since arithmetic takes the left side's type, and the right side is a Double, which would be cut to fit: write the Double first ('(first + second) * 2.0'), or store the right side in a Float first if it fits one
- [ ] hand_copy_of_library — 'Matrix4.set_product', added by this reopening, rewrites this Matrix4 from two Matrix4 values, which the library's '*' already answers: write 'target = left * right' (the answer is built in target's place)
- [ ] hidden_class — diagnostics/hidden_class/physics/plugin.spite: error: the class 'Physics.Plugin' hides the class 'Plugin' (diagnostics/hidden_class/plugin.spite): inside 'Physics' the name 'Plugin' would mean this class, so give one of them a clearer name
- [ ] hole_values — the hole '<stage>' of '<stage>_all' matches only the values of an enum named for it, and there is no enum 'Stage': declare 'enum Stage' listing the names it may match, one per line
- [ ] index_reads — 'names[0]' may be missing, since every '[ ]' answers a 'T?' (this one is a String?), so 'upper_case' cannot be called on it yet: narrow it first with 'crash names[0]', 'assert names[0]' or 'if names[0] { }', or prove the count first, 'crash names.count() > 0'
- [ ] indexable_unproven — 'ruler[index]' may be missing, since every '[ ]' answers a 'T?' (this one is an Integer?), but an Integer is needed: narrow it first with 'crash ruler[index]', 'assert ruler[index]' or 'if ruler[index] { }'
- [ ] inline_singleton — 'Build' is a singleton: bind it once beside the attributes, 'var build = Build()', and use 'build.target_operating_system'
- [ ] inline_singleton_attribute — 'Build' is a singleton: bind it once beside the attributes, 'var build = Build()', and use 'build.target_operating_system'
- [ ] internal_class — diagnostics/internal_class/spite/internal/floor.spite: error: Spite.Internal.Floor is internal to Spite and cannot be used outside the standard library: read bytes with Buffer or BinaryReader, describe foreign data with a plain type, and leave threads to the compiler
- [ ] internal_use — Spite.Internal.Memory is internal to Spite and cannot be used outside the standard library: read bytes with Buffer or BinaryReader, describe foreign data with a plain type, and leave threads to the compiler
- [ ] io_system_writes_row — 'crash not $system_type.function_writes_parameter("last_each", 1)' always halts in Runner<Quitter>: its condition is decided while compiling and is false, so the program would stop here every time this function runs: call it only where the condition holds, or change what the condition asks; 'Quitter.last_each' writes its parameter 'quitting' at diagnostics/io_system_writes_row/quitter.spite:5: 'quitting.quit.requested = true'
- [ ] items_borrows — 'Velocity' fits a Vector, so the items of 'velocities' are borrowed: 'velocity' is borrowed from 'velocities', and 'velocities.append()' on line 13 may move the items of 'velocities', so 'velocity' is not read after it: read 'velocities[index]' again after that line, or keep 'velocity.copy()', an independent object
- [ ] items_nullable_unproven — 'names[index]' may be missing, since every '[ ]' answers a 'T?' (this one is a String?), so 'upper_case' cannot be called on it yet: narrow it first with 'crash names[index]', 'assert names[index]' or 'if names[index] { }', or read it where a bound proves it, inside 'while index < names.count()'
- [ ] joined_maybe_boolean — this is a Boolean? used by a condition, which would only test that it is there, not that it is true: prove it is there first ('crash index < flags.count()' proves 'flags[index]') or switch over it
- [ ] joined_text — diagnostics/joined_text/joined_text.spite:5:34: text written down is not joined with '+': put the value inside it, like "hello {name}". Two values are still joined with '+'
- [ ] json_key — 'MeshRecord.json_key_maximum_distance' would name the JSON key of 'maximum_distance', and JsonReader and JsonWriter do not read a function for it: a key that is not an attribute's name is given to the serializer in a map keyed by the attribute, '{MeshRecord.attributes['maximum_distance']: "..."}'
- [ ] json_split — there is no 'Json': it is two classes, 'JsonWriter<T>()' whose 'write(value)' makes the text, and 'JsonReader<T>()' whose 'read(text)' answers a 'T?'
- [ ] json_unwritable — JsonWriter cannot write 'Owner': 'Owner.pet' is the union Pet, and JSON does not say which member a value is. JsonWriter handles classes, lists, dictionaries, enums, Symbols, numbers, Boolean, String and 'T?', so keep what it sees to those, or give it a class of its own that holds only them
- [ ] known_fact_checked — 'first' is already narrowed by 'crash first' on line 7: remove this check
- [ ] left_over_after_block — diagnostics/left_over_after_block/left_over_after_block.spite:12:7: 'console' is left over after the '}' that closes this statement: a statement ends with its line, so remove it, or put it on a line of its own if it is a statement
- [ ] left_over_after_return — diagnostics/left_over_after_return/left_over_after_return.spite:10:22: 'attribute' is left over after the end of the statement: a statement ends with its line, so remove it, or put it on a line of its own if it is a statement
- [ ] lent_arguments — 'streamed_rows' is the plural of 'streamed_row', but 'streamed_row' walks nothing: its 'argument' is not a word of its name, so it is a helper compiled for the one symbol passed to it, not a template with a plural. Name it 'streamed_argument' and call 'streamed_arguments(...)'
- [ ] lent_element_guard — this 'assert' would answer a default Layout (an object with every attribute at its default) that a caller cannot tell from a real one: return a value ('if row >= column.values.count() { return Layout() }'), make the result 'Layout?', or 'crash row < column.values.count()' if this is a developer mistake
- [ ] lent_escapes — 'Justify' fits a Vector, so the items of 'Column<Justify>().values' are borrowed: 'justify' is borrowed from 'Column<Justify>().values' and cannot be kept in the attribute 'kept': keep 'justify.copy()', an independent object
- [ ] lent_results — 'Layout' fits a Vector, so the items of 'Column<Layout>().values' are borrowed: 'layout' is borrowed from 'Column<Layout>().values' and cannot be kept in the attribute 'kept': keep 'layout.copy()', an independent object
- [ ] lent_to_calls — 'mouse' is borrowed from 'mice' and lent to 'grow' for its call, and 'input.grow()' on line 21 may move the items of 'mice': a function lent a borrowed item may not append to or remove from the collection it is borrowed from, directly or through what it calls; change the size of 'mice' before or after the call
- [ ] library_class_namespace — diagnostics/library_class_namespace/color/palette.spite: error: 'Color' is a class of the standard library and also the namespace of the folder 'diagnostics/library_class_namespace/color': a dotted name means one thing, so rename the folder
- [ ] library_function_mistakes — 'sort_by(counts.get_at)': 'counts.get_at' returns an Integer?, but 'sort_by' needs it to return something ordered, a number or a String, and a value that may be null has no place in the order: pass a function of your own that narrows it and returns the plain value
- [ ] literal_does_not_fit — 300 does not fit in a Byte, whose numbers run from 0 to 255: store it in a wider type, or use a number that fits
- [ ] load_as_value — diagnostics/load_as_value/load_as_value.spite:2:18: 'load' is a keyword that starts a line of its own, like 'load "folder"': it is not a function, and it has no value
- [ ] load_folder_name — diagnostics/load_folder_name/load_folder_name.spite: error: the folder 'Engine-Plugin' is not named in snake_case: every folder of a program, a package's own folder included, is lowercase words joined by '_', so rename it 'engine_plugin'
- [ ] load_function — diagnostics/load_function/load_function.spite:7:6: 'load' is a keyword and cannot name a function: give it a name that says what it loads, like 'load_texture'
- [ ] load_parentheses — diagnostics/load_parentheses/load_parentheses.spite:2:9: 'load' is a keyword, not a function: write it without parentheses, 'load "level"'
- [ ] load_unknown_condition — this 'if' holds a 'load', so the compiler decides it, and it cannot decide this condition: around a 'load' a condition reads only Build fields (through 'var build = Build()' beside the attributes), text, whole numbers, true and false, joined by ==, !=, and, or and not
- [ ] loaded_folder_namespace — unknown identifier 'Garnish'
- [ ] local_singleton — 'Build' is a singleton, bound here as a local: bind it once beside the attributes, 'var build = Build()', so every singleton the class uses is at the top of its file
- [ ] locked_wait — 'Columns.despawn_all' waits for 'Parallel(remover.run)' while it holds Columns's lock, since a Parallel reaches Columns, and what 'remover.run' runs calls 'Columns.remove_row', which takes that lock: each would wait for the other forever. Wait for the Parallel outside Columns's functions, or do not call Columns from its work
- [ ] lone_hole — '"{counter.click_count.clicks}"' is a text of one value and nothing else: assign the value directly, 'counter.label.text = counter.click_count.clicks'
- [ ] long_line_construction — 'CounterButton("a label long enough to carry this line past the formatter width")' is constructed inside an argument of 'world.create_entity_from_bundle': a constructor call is never an argument, so make it first on a line of its own, 'var counter_button = CounterButton("a label long enough to carry this line past the formatter width")', and pass 'counter_button'
- [ ] lost_writes — 'resized.width' is written here and 'resized' is never read after it: 'resized' is a 'Layout' only this function holds, so the write is lost when it is let go. Use what was written, return 'resized', keep it in an attribute or a list, or drop the write
- [ ] maths_constant_assigned — 'Float.pi' is a constant, and a constant is get-only: nothing can assign it
- [ ] maths_constant_on_value — 'pi' is a constant of the class Float, not of a value: write 'Float.pi'
- [ ] maths_other_spellings — Float has no function 'sqrt': Spite spells it 'square_root', since no name is abbreviated
- [ ] maybe_boolean_conditions — this is a Boolean? used by a condition, which would only test that it is there, not that it is true: prove it is there first ('crash index < flags.count()' proves 'flags[index]') or switch over it
- [ ] maybe_in_arithmetic — 'scores[position]' may be missing, since every '[ ]' answers a 'T?' (this one is an Integer?), so '+' cannot use it yet: narrow it first with 'crash scores[position]', 'assert scores[position]' or 'if scores[position] { }', or read it where a bound proves it, inside 'while position < scores.count()'
- [ ] member_template_mistakes — 'sum_name': the member 'name' of 'Repository' is a String, but 'sum_' needs it to return a numeric type
- [ ] memory_access — 'write_long' reads or writes the memory at an address, which only library/ does: use a class of the standard library, or 'TypedMemory<T>' for values of any type
- [ ] missing_switch_case — this switch over 'Held' has no case for File: a switch over a union covers every member, so a member added later cannot be forgotten; add the cases, or end with '_:' for the rest
- [ ] named_like_library — diagnostics/named_like_library/geometry/vector3.spite: error: the class 'Geometry.Vector3' is named like the standard library's class 'Vector3': use 'Vector3', reopening it to add what it lacks, or give this class a clearer name
- [ ] namespace_nullable — 'ns' only copies 'NamespaceNullable.namespace' so it can be narrowed: narrow 'NamespaceNullable.namespace' itself ('assert NamespaceNullable.namespace') and use it directly
- [ ] naming — the enum 'job_kind' must be written in PascalCase: capitalised words with no underscores
- [ ] narrowed_name_reassigned — this value may be null (it is a Box?), so 'label' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] nested_if_else — this 'if'/'else' is inside a branch of another 'if'/'else': move it into a function named for what it decides, or, when both test which member of a union or which value of an enum a value is, use one 'switch'
- [ ] new_spite_class — diagnostics/new_spite_class/spite/gadget.spite: error: 'Spite' holds the standard library's own classes, so a file in a 'spite' folder may only reopen one of them: 'Spite.Gadget' is not one, and a new class of your own belongs in a namespace of your own
- [ ] null_comparison — 'null' is not a value to compare against or pass around: narrow the value instead, with 'if value { } else { }', 'assert value', 'crash value' or 'switch value { <Type>: ... Null: ... }'
- [ ] null_default_locals — the variable 'count' is declared 'Integer', not 'Integer?', so '= null' would make a default Integer rather than nothing: write 'var count: Integer? = null' for none yet, narrowed before use, or 'var count = 0' for a default
- [ ] null_defaults — the attribute 'target' is declared 'Monster', not 'Monster?', so '= null' would make a default Monster rather than nothing: write 'var target: Monster? = null' for none yet, narrowed before use, or 'var target = Monster()' for a default, or keep '= null' and assign it at the top of the constructor
- [ ] number_memory — 'Integer' declares 8 bytes of memory, and the compiler lays it out as int32_t, which is 4
- [ ] number_memory_read — '_memory' is the memory Integer is kept in, and the compiler keeps the value itself there: write 'this'
- [ ] number_memory_spelling — a value states its size as 'var _memory = Memory.Bytes(bytes)', with the bytes written out: the compiler places that memory, and a number's is a register
- [ ] number_type_mistakes — 'Boolean' does not fit type 'Number', which 'Summer' requires of $number_type: it has no function 'sum'
- [ ] old_ampersand — Spite has no '&' operator: bits are functions on the whole numbers, write 'value.bits_and(mask)' (and 'and' for a condition)
- [ ] old_break — diagnostics/old_break/old_break.spite:7:13: Spite has no 'break': a loop stops in its own condition, like 'while index < count and not found', and a step it skips sits under an 'if'
- [ ] old_declaration_equal — diagnostics/old_declaration_equal/old_declaration_equal.spite:1:10: a declaration takes no '=': write 'enum Job {' with one entry on each line
- [ ] old_do — diagnostics/old_do/old_do.spite:5:15: Spite has no 'do': an 'if' on a value that may be null narrows it in place, 'if value { ... } else { ... }', and inside the block 'value' is the value itself
- [ ] old_let — diagnostics/old_let/old_let.spite:4:5: Spite has no 'let': a variable is declared 'var name = value', always with a default, and there is no 'const'
- [ ] old_list_names — List has no method 'add', which does not say where: write 'append' to add at the end, or 'prepend' at the start
- [ ] old_nullable_spelling — diagnostics/old_nullable_spelling/old_nullable_spelling.spite:1:31: 'Nullable<T>' was replaced by a '?' suffix: write 'Monster?' for a value that may be null
- [ ] old_reference_type — Spite has no '&Type': every class, list and text is passed by reference already, so write the type alone
- [ ] old_shift — diagnostics/old_shift/old_shift.spite:5:26: Spite has no '<<': bits are functions on the whole numbers, write 'value.shifted_left(count)'
- [ ] old_type_spellings — 'Int' is spelled 'Integer'
- [ ] operator_function_call — 'set_height' is what writing 'height' calls: write 'point.height = 4'
- [ ] overlapping_load — 'load "kingdom/physics"' and the load at diagnostics/overlapping_load/overlapping_load.spite:4 both reach the files of 'diagnostics/overlapping_load/kingdom/physics', which lies inside 'diagnostics/overlapping_load/kingdom', so those files would be loaded twice: load only 'diagnostics/overlapping_load/kingdom', whose subfolders are already its namespaces
- [ ] own_template_borrows — 'values.item_at(items, best)' is borrowed from 'values' and cannot be returned: return 'values.item_at(items, best).copy()', an independent object
- [ ] package_attributes — the attribute 'color' is never read: remove it
- [ ] parallel_function_reach — 'Parallel(tally.count_up)' runs 'record' on another thread, so it may reach only the attributes of its own 'Tally' that hold values, its locals and singletons: 'marks' holds a List<Integer>, which another thread may share. Give the work what it needs as numbers or text of its own, or make an object for the work alone that nothing else holds or touches after 'Parallel(...)'
- [ ] parallel_handover — 'crafter' was handed to 'Parallel(crafter.craft)', which keeps its 'recipe_ids' on another thread, so it is not used after that line: make another 'Crafter' for what follows, or read the task's result
- [ ] parallel_reach — 'parallel_each_follow' runs 'follow' on many elements at once, so it may reach only its own 'Boid' attributes that hold values, and its locals: 'leader' holds a 'Boid?', which another element may share. Copy what the pass needs into a number or text attribute first, or write 'each_follow' to run it on one thread
- [ ] parallel_shared_value_writes — 'Parallel(add_one)' writes 'total' of this 'ParallelSharedValueWrites' on another thread while this thread may write it too, so one write would be lost: move the work into a class of its own and hand a new one over ('var worker = Worker(...)' then 'Parallel(worker.work)'), answer the value from the work and read the task's result, or keep it in a singleton, which is made safe for threads
- [ ] parallel_shared_writes — 'counter' was handed to 'Parallel(counter.bump)', which writes its 'count' on another thread, so it is not used after that line: make another 'Counter' for what follows, or read the task's result
- [ ] parameter_write_question — 'Mover.move' takes 2 arguments, so it has no parameter 2 to ask about: 'function_writes_parameter' counts parameters from 0
- [ ] passed_functions — there is no 'map(function)': collect a member of each element with 'map_<member>()', and a value computed from each element by giving the element's class a read-only attribute (a 'get_<name>()' with no setter) and writing 'map_<name>()'
- [ ] passed_symbol — 'announce' is compiled once for each 'phase' of 'Symbol<$system_type.phase_all>', so its 'phase' can only be the symbol of a template over that same range, passed by name from inside it, as in 'announce(phase)'
- [ ] path_narrow_assignment — this value may be null (it is a Box?), so 'label' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] path_narrow_else — this value may be null (it is a Namespace?), so 'name' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] path_narrow_loop — assigning to 'outer.inner' inside this loop undoes a narrowing made before the loop, and the next pass would read it unproven: narrow it inside the loop instead
- [ ] plain_get_at — 'get_at' answers 'Integer', but it is what '[ ]' calls, and every '[ ]' answers a 'T?' that is narrowed before use: declare it to answer 'Integer?', and answer null when nothing is at the index
- [ ] plain_items — 'Vector<Integer>' holds plain values, and a List keeps numbers, Boolean, enums and Memory.Address flat just as it did, so a list of them has one spelling: write 'List<Integer>'
- [ ] plain_symbol_on_list — 'total_member' is a template on List, whose own attributes are its buffer, so a plain 'Symbol' answers nothing: write 'member: Symbol<$element_type>' to name a member of the element
- [ ] plural_templates — 'collect_name' answers every 'name', so it is written in the plural: 'collect_names'
- [ ] print_without_to_string — 'Crate' does not fit type 'Printable': it has no function 'to_string'
- [ ] proven_element — 'codes[index]' is already proven by the loop condition 'index < codes.count()', so this 'crash' proves nothing: remove it
- [ ] proven_index_check — 'skipped[index]' is already proven by the loop condition 'index < skipped.count()', so this 'crash' proves nothing: remove it
- [ ] read_only_attribute — 'number' is read-only: 'Badge' answers it through get_number() and has no set_number(value)
- [ ] receiver_call_undoes_proof — 'names[0]' may be missing, since every '[ ]' answers a 'T?' (this one is a String?), but a Printable is needed: narrow it first with 'crash names[0]', 'assert names[0]' or 'if names[0] { }', or prove the count first, 'crash names.count() > 0'
- [ ] reflection_names — the function 'functions' has a name reflection gives every object: 'value.functions' lists its functions, and one of its own would hide it. Name it something else, like 'table_functions'
- [ ] reflection_read_only — 'name' is read-only: 'Class' answers it through get_name() and has no set_name(value)
- [ ] removed_executable_flag — error: '--executable' is not a compiler option: 'spite program --build' builds the executable without running it, and 'spite program' builds it and runs it
- [ ] removed_run_flag — error: '--run' is not a compiler option: 'spite program' builds the program and runs it, 'spite program --check' only checks that it compiles, and 'spite program --build' builds it without running it
- [ ] removed_translation_units_flag — error: '--translation-units' is not a compiler option: the compiler chooses how many C files it compiles a program from
- [ ] removed_tuning_flag — error: '--tune-for-this-machine' is not a compiler option: a default or --hot-reload build is tuned for the machine that builds it, and an --optimized build, the one shipped, runs on any machine
- [ ] reopened_vector_borrows — 'first' is borrowed from 'other', and 'other.append()' on line 4 may move the items of 'other', so 'first' is not read after it: read 'other[index]' again after that line, or keep 'first.copy()', an independent object
- [ ] repeated_branch_call — 'source.slice(0, end_index)' is computed in both branches: compute it once before the 'if'
- [ ] replaced_items — 'layout' was read from 'layouts[0]', so assigning it here changes only 'layout', and nothing reads 'layout' after: 'layouts' still holds the old item. Write 'layouts[0] = made' to replace the item, or give the new value a 'var' of its own
- [ ] reserved_signature — 'drop' is called by the compiler when the last reference to an object goes, so it is declared exactly 'func drop()'
- [ ] reserved_spite_namespace — diagnostics/reserved_spite_namespace/reserved_spite_namespace.spite: error: 'spite' is reserved for the built-in Spite namespace: name the folder something else
- [ ] return_type_colon — diagnostics/return_type_colon/return_type_colon.spite:5:30: a return type is written '(): Integer': add the ':' after the parameter list
- [ ] returned_local — 'whole' is declared only to be returned on the next line: write 'return scaled.round()', since 'return' already makes the value the function's Integer
- [ ] returned_text — '$value_type.returned_text("json_key_level")' reads the text a function of 'Label' returns, and it has no function 'json_key_level': ask '$value_type.has_function("json_key_level")' first, and read the text only in the branch where it is true
- [ ] returning_guard — this 'if' only returns: write 'assert not name.is_empty()' and let the rest run unindented
- [ ] same_named_types — a List<Recipes.CookTask.Buildable> cannot be used where a List<Recipes.Cookbook.Buildable> is needed
- [ ] separator_flag — error: '--' is not a separator: a program's settings are given beside the compiler's flags, kebab-case like them: spite program --optimized --player-name=Bob
- [ ] setting_named_like_flag — 'Environment.optimized' and 'Build.optimized' are both '--optimized' on the command line: a program's settings and the compiler's flags share one set of names, so one of them needs another name
- [ ] setting_value — error: '--volume=loud' was given, but 'Environment.volume' is an Integer: a whole number, like --volume=3
- [ ] several_mistakes — this class has no function 'missing_function'
- [ ] shadowed_function — the attribute 'greeting' has the name of a function of this class, and a function is a value passed by its name: give the attribute a name of its own
- [ ] shape_function_mismatch — 'Silent' does not fit type 'Renderable': it has no function 'render'
- [ ] shape_mismatch — formatted diagnostics/shape_mismatch/shape_mismatch.spite
- [ ] shape_parameter_name — diagnostics/shape_parameter_name/shape_parameter_name.spite:2:19: a shape names the types it needs, not the names they are given: write 'Integer' where 'scale: ...' is, since a class satisfies it whatever it calls its parameters
- [ ] singleton_arguments — 'starting_name' is not a literal: a singleton's arguments are literals the compiler reads, because each distinct argument list is its own instance of 'Registry', made the first time it is asked for
- [ ] singleton_circle — singleton 'Columns' binds 'World', which binds 'Column<Entity>', which binds 'Columns': singletons initialise each other in a circle, so one of them has to reach the other some other way, such as by binding it in the class that uses both
- [ ] singleton_function — a class says it is a singleton with a 'singleton' line at the top of its file, not with a function: delete 'is_singleton()' and write 'singleton' as the file's first line
- [ ] snapshot_argument_writes — 'crash not $system_type.function_writes_parameter("<phase>_each", argument.index) or not argument.class.any_attribute_fits_vector(Entity)' always halts in Refuser<Mover>: its condition is decided while compiling and is false, so the program would stop here every time this function runs: call it only where the condition holds, or change what the condition asks; 'Mover.update_each' writes its parameter 'moving' at diagnostics/snapshot_argument_writes/mover.spite:7: 'moving.position.left = moving.position.left + moving.entity.id'
- [ ] sparse_rows — 'row' borrows items from 'Column<Position>().values' for the call it is passed to, and 'keeper.spawn_while_moving()' on line 11 may move the items of 'Column<Position>().values': a function that is handed a row may not append to or remove from the vectors it borrows from, directly or through what it calls
- [ ] spinning_loop — this 'while true' never ends: nothing inside it returns, asserts or crashes, and it calls nothing, so the program would spin here for good: leave it with a 'return' ('if done { return }'), or loop 'while' a condition
- [ ] spite_link_outside_final — this comment links to 'helper.spite', a .spite file, and only a file '--final-classes' wrote may link one, to name the file that supplied a declaration: anywhere else a comment links a markdown section
- [ ] store_through_nullable — 'boxes[3]' may be missing, since every '[ ]' answers a 'T?' (this one is a Box?), so 'label' cannot be assigned through it yet: narrow it first with 'crash boxes[3]', 'assert boxes[3]' or 'if boxes[3] { }', or prove the count first, 'crash boxes.count() > 3'
- [ ] structural_index_undone — 'glyphs[code - 32]' may be missing, since every '[ ]' answers a 'T?' (this one is a String?), so 'upper_case' cannot be called on it yet: narrow it first with 'crash glyphs[code - 32]', 'assert glyphs[code - 32]' or 'if glyphs[code - 32] { }', or read it where a bound proves it, inside 'while code - 32 < glyphs.count()'
- [ ] switch_chain — these 3 'if's each compare 'index' with a value and return, which is what a 'switch' says: write 'switch index { 0: return "monday"  1: return "tuesday"  2: return "wednesday"  _: return "later" }'
- [ ] switch_rest_case — the cases 'Cat' and 'Dog' do the same thing: write it once, as the last case '_:'
- [ ] switch_single_case — this switch only asks what class 'creature' is: write 'return creature == Fish'
- [ ] symbol_for_text — 'world' in single quotes is a symbol, and text is wanted here: text is always written in double quotes, so write "world"
- [ ] target_in_build — 'Build.target_operating_system' cannot be declared by a program: the standard library for the target system is loaded before the program, so the target is given to the compiler, --target-operating-system=linux (or windows, or mac), and is the system doing the compiling otherwise
- [ ] target_operating_system — error: '--target-operating-system=beos' names no operating system the library has a folder for: windows, linux or mac
- [ ] template_attribute_spelling — 'attribute: Spite.Attribute<...>' would be bound to one instance, and a template is made once for each member of the class, with the instance as its own argument: write 'attribute: Spite.AttributeDeclaration<...>'
- [ ] template_function_clash — the template 'store_attribute' makes 'store_row' for the attribute 'row' of 'RowView', which is already a function of 'Row': rename the function or the template
- [ ] template_walk — this 'while' walks every element of 'items' only to call 'restock' on each: write 'items.each_restock()'
- [ ] terminal_if — this 'if' is the last thing the function does and has no 'else', so it only checks that 'maybe_name' is there: write 'assert maybe_name' and let the rest of the function run unindented
- [ ] text_is_to_string — Integer turns into text with 'to_string()', a cast like 'to_integer()': write 'to_string()'
- [ ] text_items_passed — 'each' passes each item to a function, which a Vector never does: keep the values in a 'List<String>' to pass them on
- [ ] text_to_number — text is not an Integer until it is read as one, and text that is not a number has none to give: read it with 'to_integer()', which answers 'Integer?', null when the text is not a number that fits, and narrow it, or declare the value 'Integer?'
- [ ] type_mistakes — this value may be null (it is a Pet?), so 'name' cannot be read from it yet: narrow it first with 'if value { }', 'assert value' or 'crash value'
- [ ] type_size_mistakes — 'Labelled.size' is the size of the C struct a type is at a foreign call, and only a type whose attributes are all numbers is one
- [ ] unclosed_text — this text never closes: a piece of text is written on one line, and a line break inside it is written as the two characters backslash and n
- [ ] underscore_flag — error: '--repl_port' is written '--repl-port': flags and settings are kebab-case on the command line, and the field they set is 'repl_port'
- [ ] underscore_setting — error: '--player_name' is written '--player-name': flags and settings are kebab-case on the command line, and the field they set is 'player_name'
- [ ] union_value_members — 'String' cannot be a member of union 'Message': a union holds objects whose class a switch tests, and a String is a value; make the member a class of your own that keeps it in an attribute
- [ ] unkeyable_types — a Dictionary cannot be keyed by 'Integer?': a key is a number, a Boolean, a String, an enum value or an object of a class
- [ ] unknown_compiler_flag — error: '--serve' is not a compiler option, and this program declares no setting 'serve' (its Build declares check, build, executable_path, c_source, c_path, final_classes, optimization_report, high_level_report, high_ir, optimized, development, repl, repl_port, hot_reload, debug_memory, trace_asserts, operating_system, target_operating_system, program). To decide it when compiling, reopen Build in the program's build.spite with 'var serve = ...'; to read it when the program runs, declare it in environment.spite with 'var serve = ...'
- [ ] unknown_type_in_shape — unknown type 'Server.Component.Eye': did you mean 'Component.Eye'?
- [ ] unknown_type_suggestion — unknown type 'Eye': did you mean 'Component.Eye'?
- [ ] unstepped_poll — this loop reads 'napping.finished' and calls nothing, so nothing steps 'napping' between two reads and it never finishes: read its value instead ('var done: T = napping' waits for it), or call something that waits in the loop
- [ ] unused_attributes — the attribute 'forgotten' is never read: remove it
- [ ] unused_names — formatted diagnostics/unused_names/unused_names.spite
- [ ] upper_is_upper_case — text has no 'upper()': write 'upper_case()', which names what it does without abbreviating
- [ ] value_switch — this switch over 'light' has no case for 'amber': a switch over an enum covers every value, so a value added later cannot be forgotten; add the cases, or end with '_:' for the rest
- [ ] variadic_mistakes — this call passes a whole List<String>, but the last parameter is written with '...', so it takes the values one by one: pass the elements themselves, separated by commas
- [ ] variadic_not_last — diagnostics/variadic_not_last/variadic_not_last.spite:7:34: '...lines' takes every argument from here on, so it is the last parameter: move it to the end
- [ ] vector_borrows — 'velocity' is borrowed from 'velocities', and 'velocities.append()' on line 11 may move the items of 'velocities', so 'velocity' is not read after it: read 'velocities[index]' again after that line, or keep 'velocity.copy()', an independent object
- [ ] vector_items — 'Holder' cannot be an item of a Vector: its attribute 'scores' is a List<Integer>, and a Vector holds each item inline, so every attribute is a number, a Boolean, an enum or a String (keep 'Holder' in a 'List<Holder>', or keep 'scores' somewhere else)
- [ ] vector_reserve_borrows — 'velocity' is borrowed from 'velocities', and 'velocities.reserve()' on line 11 may move the items of 'velocities', so 'velocity' is not read after it: read 'velocities[index]' again after that line, or keep 'velocity.copy()', an independent object
- [ ] vector_rows — 'row' borrows items from 'world.positions' for the call it is passed to, and 'keeper.spawn_while_moving()' on line 14 may move the items of 'world.positions': a function that is handed a row may not append to or remove from the vectors it borrows from, directly or through what it calls
- [ ] vector_template_walk — this 'while' walks every element of 'crates' only to call 'seal' on each: write 'crates.each_seal()'
- [ ] walk_with_function — this 'while' walks every element of 'names' only to call 'say_hello' with each: write 'names.each(say_hello)'
- [ ] walked_rows — 'row' borrows items from 'world.position' for the call it is passed to, and 'keeper.spawn_while_moving()' on line 11 may move the items of 'world.position': a function that is handed a row may not append to or remove from the vectors it borrows from, directly or through what it calls
- [ ] weak_across_threads — 'Parallel(tree.grow)' runs on another thread, and what it runs reaches 'Branch', which is a Weak or is held by one: a Weak is kept in one table that is not shared between threads, so a Weak and the objects it holds stay on the program's own thread. Hold the object itself in the work, or keep the Weak out of what the Parallel reaches
- [ ] whole_number_rotation — an Integer has no function 'square_root'
- [ ] wider_bitwise_operand — 'flags.bits_and(mask)' works in a Byte, since a bitwise function takes its receiver's type, and 'mask' is a Long, which would be cut to fit: store the receiver in a Long first ('var wide: Long = flags'), or store 'mask' in a Byte first if it fits one
- [ ] wider_comparison — 'count < total' compares in Integer, since a comparison takes the left side's type, and the right side is a Long, which would be cut to fit: write the Long first ('total > count'), or store the right side in an Integer first if it fits one
- [ ] wider_right_operand — 'count * total' is a multiplication in Integer, since arithmetic takes the left side's type, and the right side is a Long, which would be cut to fit: write the Long first ('total * count'), or store the right side in an Integer first if it fits one
- [ ] written_handle_type — the type of a 'Parallel' handle is never written: it is worked out from the function it runs, so write 'var total = Parallel(count)'
- [ ] written_not_read — 'total' is never read: remove it

### The compiler's own errors

- [ ] 'game/game.spite' is a file, and a program is named by its folder: spite game
- [ ] 'game' holds no program: a program is a folder holding an entry file named after it, 'game/game.spite'
- [ ] '--check' only checks that the program compiles and '--build' builds its executable: give one of them
- [ ] '<path>' is left from an earlier build and could not be removed (is it still running?): a build removes it first, so a failed build never leaves the old one to run
- [ ] '--run' is not a compiler option: 'spite program' builds the program and runs it, 'spite program --check' only checks that it compiles, and 'spite program --build' builds it without running it
- [ ] '--executable' is not a compiler option: 'spite program --build' builds the executable without running it, and 'spite program' builds it and runs it
- [ ] '--executable-path' says where the executable goes, and '--check' builds none: leave out --check to build it
- [ ] could not write '<path>'
- [ ] '--tune-for-this-machine' is not a compiler option: a default or --hot-reload build is tuned for the machine that builds it, and an --optimized build, the one shipped, runs on any machine
- [ ] '--translation-units' is not a compiler option: the compiler chooses how many C files it compiles a program from
- [ ] '--repl_port' is written '--repl-port': a flag is kebab-case, and it sets the Build field 'repl_port'
- [ ] '--volume=loud' was given, but 'Environment.volume' is an Integer: a whole number, like --volume=3
- [ ] '--serve' is not a compiler option, and this program declares no setting 'serve' (its Build declares check, build, ...). To decide it when compiling, reopen Build in the program's build.spite with 'var serve = ...'; to read it when the program runs, declare it in environment.spite with 'var serve = ...'
- [ ] '--optimized=maybe' was given to the compiler, but 'Build.optimized' is a Boolean: --optimized, --optimized=true or --optimized=false
- [ ] --repl-port takes a port number from 1 to 65535: spite program --repl-port=4000
- [ ] '--operating-system' cannot be given: Build.operating_system is the system doing the compiling (windows). To write the program for another system, give --target-operating-system=linux (or windows, or mac)
- [ ] '--program' cannot be given: the program is the folder named on the command line, 'spite folder', and Build.program is set from it
- [ ] '--' is not a separator: a program's settings are given beside the compiler's flags, kebab-case like them: spite program --optimized --player-name=Bob
- [ ] '--optimized' is given twice: a flag or a setting is given once
- [ ] '--format' is not a compiler option: every compile formats the program's own files first, and nothing turns that off: '--check' formats and checks a program without building it
- [ ] the formatter refuses it, and a program compiles only once formatted: <reason>
- [ ] 'Build.format' cannot be declared: every compile formats the program's own files first, and nothing turns that off

## What the original test suite asks of us

`bash ../SpiteLanguage/check.sh` is the suite. It is the definition of "done" for this compiler,
and each of its jobs is a thing this compiler must be able to do.

| The job | What it runs | What this compiler must do |
|---|---|---|
| The generation | The compiler compiles itself, twice, and the two are the same | Compile its own source, and the executable it writes is itself. |
| The corpus | Every program under `conformance/stage1` to `stage6` builds, runs, prints exactly `expected_output.txt` and frees everything it takes | Build and run every program of the corpus, with the same output and the same count of allocations and frees. |
| The examples | The same, for the programs under `examples/` | The same. |
| The documentation | Every titled program in `docs/`, `specs/` and `README.md` builds, runs and prints its `output` block; every `error` block fails with its `diagnostic` text | The same. |
| The diagnostics | Every program under `diagnostics/` fails with exactly `expected_errors.txt` | The same texts, with the same file and line. |
| The tests | The package under `tests/` runs, where a test is a function that crashes | The same. |
| The benchmarks | Every case under `benchmarks/` builds, and the Spite, the naive C and the expert C print the same answer | The same answer. The committed `generated.c` is the original compiler's C, so that half of the check does not apply here. |
| The compiler's memory | The compiler compiles itself once more with `--debug-memory` and frees everything it takes | The same. |
| The other systems | Each system's folder in `library/` compiles, and the programs that ask the system for what this one does not run | The same, once there is a backend for those systems. This compiler writes Windows x86 only, so the job is out of reach until then. |
| The reloads, the final classes, the launcher | The fast reloads, `--final-classes` and the launcher all work | The same. |

## The tests

The tests live in their own folder, `../SpiteSpec`, with a `tests` subfolder in it, so that they ship
as a repository of their own with the tests up to date, instead of mixed in with the compiler. This
repository is the compiler and nothing else.

**The shape.** One folder per program under `tests`, named after what the program is, and each program
stands on its own: it shares no file with another test, so a test can be read, changed or moved without
touching the rest. `../SpiteSpec/tests/exit_code/exit_code.spite` is the shape.

**The format.** A program names the standard library in its first line, because there is no launcher any
more and the compiler does not go looking for a library:

```spite
func ExitCode(): Integer {
    load "../../../SpiteCompiler/.spite/spite-0.0.6-windows/library"
    load "../../../SpiteCompiler/.spite/spite-0.0.6-windows/library_windows"
```

**How the tests are ported.** A program is ported when the part of the language it needs works, and not
before: the port is the work, and the program is what shows the work is done.

- [ ] The program is moved into `../SpiteSpec/tests/<name>/`, one folder of its own, and nothing it
      shares with another program comes with it.
- [ ] It is updated to the new format: the first line names the library, the entry class is the program's
      own, and anything the old compiler needed the launcher for is written in the program itself.
- [ ] It is run from there, with the compiler this repository builds, and the answer it gives is the answer
      the old compiler gives.
- [ ] The programs of the old repository keep their own copies while the old compiler is still the one
      that builds this compiler. They are the corpus the new compiler is held to, and each one is ported
      as the part of the language it uses lands.
- [ ] A part of the language is done when the programs that use it are ported and answer the same, not when
      the code for it is written.

## The rules

Everything the old compiler enforces is enforced here too:

- A statement is one line.
- A call is never passed into another call, and a constructor is never an argument.
- Only `while` loops.
- `assert` and `crash` take no message.
- No abbreviations, and no em dashes.
- A comment is one line holding a link to a heading in a markdown file beside it.

## The decisions this repository has made

- **The generator is 32-bit x86 for Windows** and writes a PE file directly. There is no C in between, and
  no C compiler is needed to build a program.
- **The standard library is imported**, not provided. It lives in another repository and this project holds
  no copy of it and changes nothing in it.
- **The standard library is not part of the language.** It is a regular folder a program loads, and anyone
  can bring their own: the compiler names no class of it, and the language gives every library the same way
  to reach the C library and the memory. The library in the old repository is the one loaded for now, and
  the compiler is written against it. The one place the two are still tied is the bodies the library leaves
  out, which the compiler supplies by the library's class names; that is what the runtime item above is
  about.
- **The program's exit code is the value its entry constructor answers.** A constructor that answers nothing
  leaves the exit code at 0. The original sets the exit code by calling `Program().exit(code)`, and that is
  not lowered yet.
- **The calling convention is cdecl**: the arguments are pushed right to left, the caller clears them, and
  `eax` answers a value.
- **The image is written for the address 0x400000** and has no relocations, so the loader must put it there.
- **A virtual register is a place the machine code decides later**: a stack slot, a real register, or a value
  folded away entirely. Nothing above the low representation may assume where one lives.
- **The program is read before it is written.** The mapping and the symbols read only the classes something
  names, so nothing is read that is not needed.