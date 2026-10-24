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

`spite_compiler.spite` lists the steps and nothing else:

    command_line
    mapping                                then validators/mapping
    symbols + abstract_syntax_tree         a class at a time, as names ask for it; then validators/abstract_syntax_tree
    format                                 each file as it is parsed: printers/formatted_source, written back and read again
    name_resolution                        then validators/name_resolution
    high_intermediary_representation       then validators/high_intermediary_representation
    proofs                                 the proofs that decide what is accepted, on the built high representation
    high_optimization_passes               unit passes, then program passes
    low_intermediary_representation        then validators/low_intermediary_representation
    low_optimization_passes                unit passes, then program passes
    generators/windows_x64
    outputs                                each through its printer

No step reaches back into an earlier one.

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

The source is written to the language this compiler checks: its entry file loads `.spite/library/windows`, and
every rule of `../SpiteLanguage/specs` holds in it. The old compiler (0.0.6) cannot build it, so a build from
nothing is a chain, and `scripts/bootstrap.sh` runs all of it:

1. **The seed.** Commit `47767ec` is the last source the old compiler builds. The old compiler builds it into
   `.spite/bootstrap/spite_seed.exe`. Its executables reserve 1 MB of stack, too little for this compiler to
   resolve its own source, so the script sets the seed's `SizeOfStackReserve` (offset 72 of the PE optional header)
   to 256 MB. Only the seed is ever built by the old compiler.
2. **The seed builds the source**, about five minutes (`--check` about three). `.spite/library` must be a junction
   to `../SpiteStandardLibrary`, since the entry file's `load` reaches it through `.spite/spite_compiler`.
3. **The compiler builds itself** until two builds write the same bytes, about seventy seconds each; the compiler
   the seed writes already rebuilds itself byte for byte. That fixed point is the compiler, and
   `bash scripts/bootstrap.sh --install` puts it in `.spite/spite.exe`.

Day to day nobody runs the chain: `.spite/spite.exe` builds the next compiler from the current source
(`.spite/spite.exe .spite/spite_compiler --build --executable-path=.spite/spite_next.exe`), and the next one is
kept when it rebuilds itself to the same bytes. A change the current compiler cannot build is built by the
compiler of the commit before it.

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
- The message says what the old compiler's message says (`../SpiteLanguage/diagnostics`), in this compiler's
  words, and a `../SpiteSpec/conformance` test pins it.

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

`<level>_optimization_passes/<name>/pass.spite` holds a class `Pass(input)` answering `transformed()`. A unit pass
reads one function or class and is cached by the hash of its input; a reload runs only unit passes. A program
pass needs the whole program (tree shaking, inlining across classes, placement of objects that leave their
function). Each optimisation and each proof is a pass of its own.

## Proofs

`proofs/<what_it_proves>/pass.spite` holds a class `Pass(high)` whose `check()` proves one fact over the whole
built high representation and hands what breaks it to its validator (D1072). A proof that decides whether code is
accepted runs here, after every function is built and before any optimisation, so what a program may say never
depends on how well it is optimised; a proof that only makes code cheaper runs where its facts exist and records
them. `PROOFS.md` lists every proof, where it lives, and the ones still made inside a step or a pass. In order:

1. `narrowings_kept_across_calls`: a narrowed attribute is not read past a call that may assign it.

## Memory

- An object lives on the heap and is freed by reference counting (D658); a pass that proves an object never leaves
  its function places it in the frame instead. The lowering writes every count:
  - a value is owned (a new object, a call's answer, a text constant, a box) or borrowed (a read of a local, an
    attribute, a list slot, `this`, a singleton);
  - a place that keeps a value (a local, an attribute, a list slot, a function value's receiver, an answer) retains
    a borrowed one and releases what it held before;
  - an owned value nobody keeps (an argument, a receiver, a tested or discarded value) is released after its use;
  - a caller holds what it passes for the whole call, so a function counts only the parameters it assigns again
    (and every parameter of a step of a `Concurrent` work); the caller counts an argument or a receiver read from
    a place the call may assign, and lets it go after the call (`lowering/assignments.spite` answers what a call
    may assign, following every call to the end);
  - every block releases its locals when it ends or returns; a local declared from an attribute or a list slot
    that nothing after it in its block can write holds it uncounted;
  - `_release` frees an object whose count reaches zero through its class's `_free_<class>`: `drop()` first, then
    a list's items, the attributes that hold objects, and a buffer's bytes.
- A `Buffer`'s room is sized by the compiler (D659): a buffer proven never to grow keeps its bytes inside the
  value that holds it, exactly `size` of them; every other buffer keeps a heap block that grows.
- A class whose only memory is a room of at most 8 bytes, and nothing else, is a number: its value travels in a
  register (`Integer`, `Boolean`, ...), and its room is materialised in the frame when its bytes are read.
