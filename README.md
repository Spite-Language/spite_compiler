# SpiteCompiler

The new Spite compiler, written in Spite. This repository is the compiler and nothing else: no
launcher, no language documentation, no standard library of its own. It reads the standard library from the
old project.

**The compiler is being written again, and only the compiler.** The language is decided and does not move:
the standard library, the tests, the documentation and the decision log stay in
`../SpiteLanguage` until they move to a repository of their own. The old compiler is the thing
being ported, and it is the reference for every rule: every diagnostic it writes, this compiler must write
too, with the same words, at the same line. The ideas for the new one are in
[`new_compiler.md`](../SpiteLanguage/new_compiler.md), and `TODO.md` is the list of what is left, in
the order it is done.

## Do this

Two commands, in this folder. Nothing to think about, and each one says what it did.

**1. Build the compiler.** The old compiler (the one in `.spite/spite-0.0.6-windows/`) builds this one, because
this one is written in Spite. It is written to `.spite/spite.exe`, inside this folder, so it is never mixed up
with the old compiler's own:

    .spite/spite-0.0.6-windows/spite.exe .spite/spite_compiler --build --executable-path=.spite/spite.exe

**2. Run a test with the compiler that was just built.** The tests live in the repository beside this one,
`../SpiteSpec/tests`, one folder per program, and they are run from there:

    .spite/spite.exe ../SpiteSpec/tests/exit_code
    ../SpiteSpec/tests/exit_code/.spite/build/exit_code.exe

The first command writes the executable to `<program>/.spite/build/<name>.exe`, and the second runs it: the
value the program answers is the exit code it leaves (4072 for `exit_code`, 10 for `sum`, 3 for
`two_names`, 21 for `branches`, 14 for `chains`). `TODO.md` says how a test is ported, and when.

Two things to know about the paths. The folder is named `SpiteCompiler`, and a program folder is named in
snake_case, so the build goes through the junction `.spite/spite_compiler`, which is this same folder under
a name the rule allows. And the compiler is built with `--build`, so it is written and not run: the run
would fail, because the compiler cannot compile its own source yet.

**The standard library is named by the program, not found by the compiler.** A program's first line loads
it, with the path relative to the program that holds the load:

```spite
func Example(): Integer {
    load "../../../SpiteStandardLibrary/common"
    load "../../../SpiteStandardLibrary/windows"
```

The programs of the old repository do not do that yet: they relied on the launcher, which is gone. Until
they name the library, the new compiler cannot read them, and `TODO.md` says so.


## How it is run

    spite <path>

`spite .` compiles the folder it stands in, so the path is always written and is never implied. The
program is the folder and its entry file is the file named after the folder. Every other argument is a
setting or an argument for the program being compiled.

While the old compiler builds this one, the program folder must be named in snake_case, because that is a
rule the old compiler enforces and the new one enforces too. `.spite/spite_compiler` is a junction to this
folder that gives it that name; it is not part of the source.

The executable is written to `<path>/.spite/build/<name>.exe`, where `<name>` is the program's folder in
snake_case, and the program answers the value its entry constructor gives as the process exit code. The
programs to try it on live in the repository beside this one, `../SpiteSpec/tests`:

    .spite/spite.exe ../SpiteSpec/tests/exit_code
    ../SpiteSpec/tests/exit_code/.spite/build/exit_code.exe

## What this compiler is

- **It writes machine code.** The low representation is printed to a Windows x86 executable. There is no C
  anywhere in this project: no C is written, no C is read, and no C compiler is needed to build a program.
- **It imports the standard library.** The library lives in another repository
  (`../SpiteStandardLibrary`) and this project does not provide it, change it or keep a copy of
  it. The compiler reads it as a program loads any other folder, and compiles it. The library is not part
  of the language: it is a regular folder a program loads, and anyone can bring their own. The compiler
  names no class of it, and the language gives every library the same way to reach the C library and the
  memory. The library is written again as the compiler needs it, one class at a time, and its own list is
  in [`../SpiteStandardLibrary/TODO.md`](../SpiteStandardLibrary/TODO.md).
- **It reads what the program needs.** The mapping and the symbols read only the classes something names,
  so nothing is read that is not needed.

## How the steps run

`spite_compiler.spite` sets the order up and nothing else, so the shape of a compilation is one screen:

    read the command line
    map every folder the program can use          (mapping)
    resolve and read the classes that are named  (symbols)
    lex and parse the class of the entry file, and each class it names   (abstract_syntax_tree)
    check that a file is ordered                                          (abstract_syntax_tree)
    resolve every type written, and monomorphise every generic           (name_resolution)
    build the high representation                                        (high_intermediary_representation)
    fold constants                                    (high_optimization_passes/fold_constants)
    drop what nothing reaches                         (high_optimization_passes/drop_unreachable_functions)
    lower to instructions                             (low_intermediary_representation)
    thread and shorten jumps                          (low_optimization_passes/peephole_jumps)
    fold away moves                                   (low_optimization_passes/fold_away_moves)
    write the machine code, and the file around it   (generators/windows_x86)

Each step takes the previous step's answer as its input and hands its own answer to the next one. No step
reaches back into another. Each error is written down as soon as the step that owns it finds it, and the
run stops there, so a syntax error dies at the abstract syntax tree and never reaches a later step.

There is no discovery step. `mapping` walks the folders and turns each one into a namespace without
reading a single file, and `symbols` reads only the file of a class that something actually named. A
program that never mentions `JsonWriter` never reads `json_writer.spite`, and never checks it either.

## A program that runs

`../SpiteSpec/tests/exit_code/exit_code.spite` is a whole program. The compiler reads it, monomorphises
nothing in it, folds it, drops what nothing reaches, lowers it, and writes a Windows executable:

    .spite/spite.exe ../SpiteSpec/tests/exit_code
    wrote ../SpiteSpec/tests/exit_code/.spite/build/exit_code.exe

The executable is a 32-bit PE for Windows with two sections, importing `ExitProcess` from `kernel32.dll`. It
computes a sum in a loop, through a call with an argument, and exits with the value it computed: 4072. This
is the first machine code this repository has produced.

## The hot reload

`HOT_RELOAD.md` says how the hot reload has to work and what can go wrong with it: the slots, the library,
the manifest, and the rules of the language that decide what a reload may change (a reopened class, a
changed layout, a changed parameter list, a generic, a helper that keeps state of its own).

`TODO.md` has the work, in the order it is done. The short of it: a reload has to be faster than the
original's, and the three decisions that would lock that out are a call through a slot in a development
build, a layout that is decided once and kept, and a generator that writes a library as well as an
executable.

## Monomorphisation

**Every time a generic or a type is found, it is monomorphised.**

A generic class is a file with a `generic $name` line. It is a template, not a class: none of it is
compiled until it is written with a type. So when `name_resolution` finds a type that names a generic
class, it does not resolve the name and move on. It mints an instance: a copy of that class with its type
parameter bound to the type written at the use.

`List<Integer>` mints `List_of_Integer`. The instance is cached by its class and its arguments, so the
same instantiation is made once however many times it is written. The instance's own types are then
resolved with the substitution in place, and *that* finds more generic classes, which are monomorphised
in turn.

The compiler compiling itself reads 97 classes, and it finds no generic class of its own yet.

## Running the pipeline without a program to compile

    spite low-ir

runs the whole of the back half on a sample program written by
`high_intermediary_representation/sample.spite`, printing each step's answer and finally the instruction
list. It is the fastest way to see what a change to a pass did, and it is how the four passes in this
repository were written and checked.

## The steps

- `diagnostics` — one `Report` per run. Every problem carries its file, line and column, and the run
  stops at the first step that has one.
- `mapping` — `FolderMap` turns folders into namespaces and refuses a folder loaded twice or a folder
  lying inside another. It reads no file contents.
- `symbols` — `SymbolTable` resolves a written name to a class file by searching the enclosing
  namespaces outwards and then each loaded root, reads that one file, and follows only the classes that
  file names.
- `abstract_syntax_tree` — `Lexer`, `Parser`, the `Shapes` classes, `Ordering` (a file is ordered, a name
  is declared once, a constructor is not empty) and `Walk`.
- `name_resolution` — finds every type written in the program, resolves it, and mints a monomorphised
  instance for every generic class it finds. It also answers the two kinds of dependent type, `x.class`
  and `$type.member`, and the class every function of every class answers.
- `high_intermediary_representation` — the program as values and control flow: `Value` of `WholeNumber`,
  `Name`, `Operation` and `Answer`, and `Statement` of `Declare`, `Assign`, `While`, `Call` and `Return`.
  `Builder` lowers a class's file into it, with the substitution of its instance applied.
- `high_optimization_passes` — `fold_constants` and `drop_unreachable_functions`.
- `low_intermediary_representation` — the program as a flat instruction list over virtual registers,
  `Lowering` to build it from the high representation, and `Describe` to print it.
- `low_optimization_passes` — `peephole_jumps` and `fold_away_moves`.
- `generators/windows_x86` — `emitter.spite` turns each instruction into bytes, `pe.spite` lays the file
  out around them, `layout.spite` owns every address in it, `registers.spite` owns the frame.

## What is not built yet

- The backend lowers whole numbers only. `String`, lists, references, unions, reflection and concurrency
  are all still to come, and each needs its own value kinds in the high representation and in the low one
  before it can be lowered. The builder counts what it skips rather than dropping it.
- The `if` statement is lowered, with or without an `else`. The narrowing of a `T?` inside a branch is a
  proof, and the proofs are not made yet, so a value that is maybe nothing is read as if it were there.
- A call names the class that owns the function it reaches, when the compiler can tell it. A call on an
  instance reaches a function of the receiver's class, and the class of a receiver is the class of the
  value it holds: from the type the name is declared with, from the class a constructor call makes, from
  the name the value was copied from, or from the class a call answers. The class a call of another
  class's function answers is the result type of that function, and the name resolution answers it for
  every class it reads.
- The compiler cannot compile itself yet: its own source is far outside the subset. It reads itself, and
  it reports what it cannot lower.
- Caching per step, and the development memory that hot reload needs.

## Where it stands

The compiler builds, runs, maps its folders, reads only the classes something names, lexes, parses, checks
that a file is ordered, and walks the tree. It reads its own source: 97 classes, and only those. It reads
the whole standard library too: 145 classes, every one of them, with no error.

Below that it resolves every type, monomorphises every generic, builds the high representation of those
97 classes, folds it, drops what nothing reaches, lowers it to instruction lists, threads its jumps, folds
its moves, and writes the machine code and the PE file around it. On its own source it stops at the
emitter, which reports the calls it cannot resolve yet: the standard library is not loaded, and a class
with no constructor has none yet.

A class is an object now: its attributes live in a block of memory, a call of the class's name makes one,
and a method takes it as its first argument.

The road from here to a released executable is:

1. The rest of the language, one value kind at a time: `String`, lists, references, unions, reflection
   and concurrency. Each needs its kinds in the high representation, its kinds in the low one, and its
   instructions in the emitter. `switch`, `assert` and `crash` are with them, and the narrowing of a
   `T?` is a proof, and the proofs come after.
2. The imported standard library called out to, so a program can print and read a file. The emitter writes
   a Windows executable that calls `ExitProcess`; it needs the runtime the library asks for, and the
   library reaches the C library through `DynamicLibrary`, so the emitter must be able to call a function
   in a DLL by name.
3. Then this compiler compiling itself, which is the test that the language is complete.

`TODO.md` is the list of what is left, in the order it is done, and what the original repository's test
suite asks of this compiler for it to be done.

The passes are numbered in `spite_compiler.spite`, not in folder names, because a folder cannot be named
`01_something` in Spite: every folder is snake_case and starts with a letter.

## Faults in the language this repository found

Running the compiler on its own source and on the standard library found four faults in the old compiler.
They are fixed in `D:\Projects\SpiteLanguage`, and they are listed here because each one is a rule the
new compiler enforces:

- A function may be declared with no body. `FunctionDeclaration.body` is now nullable.
- A type may start with a lowercase name, as in the answer type `member.class`.
- A union member may be written as a dotted name, as in `Spite.Attribute`.
- The lexer never consumed a closing quote, never accepted `_` starting a name, and its escape path never
  advanced, which hung the compiler on a string.

One fault is left unfixed because it is a fault in code generation rather than in the language: the C
output emits an undeclared `__init_constructed` when two union members share a shape. `Answer` and `Call`
did, so `Answer` holds a `count`. `UnionDeclaration` and `TypeDeclaration` did, so `UnionDeclaration` holds
`member_names` where `TypeDeclaration` holds `members`. A pass in this repository must not write that
shape.

## Writing rules

Everything the old compiler enforces is enforced here too: a statement is one line, a call is never
passed into another call, a constructor is never an argument, only `while` loops, `assert` and `crash`
take no message, no abbreviations, no em dashes, and a comment is one line holding a link to a heading in
a markdown file beside it.
