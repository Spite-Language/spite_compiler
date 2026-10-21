# Architecture

How the compiler is put together, and what has to change to get there from what is built today. `TODO.md` is
the list of the work, and this page is the shape the work is building. The rules here are decisions D28, D29
and D30; the changes under [What else has to change](#what-else-has-to-change) are proposed by Claude and not
confirmed yet.

## Four kinds of folder

Everything in the compiler is one of four things, and each one has a folder of its own:

| Kind | It takes | It answers | It may write a problem | It may write text |
|---|---|---|---|---|
| a step | the representation before it | a new representation | no | no |
| a pass | a representation | the same kind of representation, transformed | no | no |
| a validator | one representation | the problems it finds in it | yes, and only it | no |
| a printer | one representation | text | no | yes, and only it |

So a step builds, a pass transforms, a validator judges and a printer shows, and none of them does another's
job. A representation is data and nothing else: it holds no function that writes it as text, and no function
that decides whether it is an error.

## The folders

    spite_compiler.spite                  the order of the steps, and nothing else
    command_line/                         the settings a run is given
    diagnostics/                          Problem and Report: data only
    mapping/                              step: folders into namespaces
    symbols/                              step: a written name into the class file it reaches
    abstract_syntax_tree/                 step: tokens and the tree
    name_resolution/                      step: every type resolved, every generic monomorphised
    high_intermediary_representation/     step: the typed program as values and control flow
    high_optimization_passes/             passes over the high representation
    low_intermediary_representation/      step: instructions over virtual registers
    low_optimization_passes/              passes over the low representation
    generators/
        windows_x64/                      step: machine code and the file around it
    validators/
        mapping/
            snake_case_names/
            folder_loaded_twice/
            ...
        abstract_syntax_tree/
            syntax/
            ordering/
            one_statement_per_line/
            call_inside_a_call/
            switch_chain/
            list_of_bytes_written/
            ...
        name_resolution/
            unknown_name/
            generic_argument_count/
            ...
        high_intermediary_representation/
            types/
            narrowing/
            switch_covers_every_case/
            unused_names/
            list_of_bytes_made/
            ...
        low_intermediary_representation/
            everything_lowered/
    printers/
        spite/                            the formatter: a tree printed as Spite
        diagnostics/                      a report printed in the error format
        high_intermediary_representation/ --high-ir
        low_intermediary_representation/  --low-ir
        optimization_report/              --optimization-report
        machine_code/                     the instructions written, with the function each belongs to

## Validators

**A validator is the one place an error is decided** (D28, decided by Mortaro). Each one is a folder holding
one rule, and the folder is named after the rule:

    validators/abstract_syntax_tree/switch_chain/validator.spite
    validators/abstract_syntax_tree/switch_chain/contract.md

The class is `Validator(input)` and it answers `problems(): List<Diagnostics.Problem>`. The input is the
representation the rule reads, and nothing else: the validator of a type rule takes the high representation,
the validator of a syntax rule takes the tree. A validator never changes what it is given, never computes
something a later step needs, and never reads a representation of another level.

`contract.md` holds the rule in a sentence, the exact text of each error it writes, the link to the heading of
the language's specification that states the rule, and the program under `diagnostics/` that proves it.

**A rule lives at the earliest level that holds the facts it needs**, because an error dies as soon as it can
be found (new_compiler.md). A file that is not in snake_case is the mapping's; a statement on two lines, a call
inside a call, a nested `if`, a chain of `if`s that is a `switch` and a `List<Byte>` written in a type are the
tree's; a name that reaches nothing and a generic with the wrong count of arguments are the name resolution's;
a type that does not match, a narrowing, a switch that misses a case, a name never read and a `List<Byte>` the
compiler would make are the high representation's. The low representation's validators find no error of a
program: they check that every step above did its job, and a problem there is a fault of the compiler, said
as one.

**A validator reads one unit or the whole program, and its input says which.** A unit validator takes one
class and is cached with it, so a reload runs it on the classes that changed and on nothing else. A program
validator takes the whole program (a function nothing calls, a reopening that replaces a method of the
standard library) and runs once every class is read. The two take different types, so the entry file cannot
run a program validator during a reload by mistake. Passes are split the same way
([below](#what-else-has-to-change)).

**The entry runs the validators of a level right after the step that builds it**, adds what they find to the
report, and stops when the report holds an error. The validators of one level do not depend on each other, so
they run in any order, and later at the same time. The report sorts its problems by file and line, so what is
printed never depends on the order they ran in.

**A `Problem` is data**: the place (file, line, column), the name of the rule, the text, and the class and
function it is in. The text is the validator's, because the specification gives it word for word. How a problem
is laid out on a line (`path:line: error: text (in Class.Function)`) is the diagnostics printer's.

## Steps never fail: they mark what they could not do

**A step that cannot build part of its answer puts a marker there and goes on** (D30, proposed by Claude,
unconfirmed). The marker says what was there and why it could not be built, and the validator of that level
turns every marker into its error:

| Step | Marker | Its validator |
|---|---|---|
| the lexer | a token it cannot read | `validators/abstract_syntax_tree/syntax` |
| the parser | a line it cannot parse, with what it expected | `validators/abstract_syntax_tree/syntax` |
| the mapping | a folder that is not there, or a file that cannot be read | `validators/mapping/...` |
| the name resolution | a name that reaches nothing | `validators/name_resolution/unknown_name` |
| the builder | a statement or value it cannot lower | `validators/high_intermediary_representation/everything_built` |
| the lowering | an instruction it cannot write | `validators/low_intermediary_representation/everything_lowered` |

Why this way:

- **Every error text is in a validator**, so the question "what is an error" has one answer, in one folder.
- **Nothing is dropped.** Today the builder counts what it cannot lower (`skipped`) and goes on, and the
  executable is written without those statements. A marker cannot be lost: its validator refuses it, and a
  generator given one crashes naming the fault of the compiler.
- **One file answers all its errors at once.** A statement is one line, so the parser starts again at the next
  line, and a reload or an editor sees every syntax error of a file, not the first.

## Printers

**Nothing turns a representation into text but a printer** (D29, decided by Mortaro). Each one is a folder, its
class is `Printer(input)`, and it answers `text(): String`. A printer never writes a file (the entry writes what
a printer answers, where the settings say) and never changes what it is given.

**The formatter is the Spite printer.** `printers/spite` takes a tree and prints it as Spite, in the one style.
Every compile parses a file, prints it, writes it back when the text changed, and reads it again, so what is
compiled and every line an error names is the formatted file. `--final-classes` is the same printer given the
merged class: the reopenings of a class are merged as a tree, and the tree is printed, one file per class.

For that to work the tree keeps everything the printer needs to write the file back: the comments, the blank
lines between groups, and how a literal was spelled. The proof is two checks on every file the compiler reads:
printing a parsed file twice gives the same text, and parsing the printed text gives the same tree.

**Every other text is a printer too**: a report in the error format, `--high-ir`, `--low-ir` (which replaces
`spite low-ir` and `LowIntermediaryRepresentation.Describe`), `--optimization-report` from what the passes
record, and a listing of the machine code. The counts the entry prints today (the classes read, the instances
minted, the functions lowered) are a printer's, and are printed only when a setting asks for them.

## What moves

The validators and the printers are cheap to separate now, because there is little of each. What is there
today:

**Errors written by steps, which move into validators:**

| Where | Errors |
|---|---|
| `mapping/folder_map.spite` | 11 |
| `generators/windows_x86/emitter.spite` | 10, every one at `"", 0, 0` with no place |
| `abstract_syntax_tree/ordering.spite` | 9 (the whole file is a validator already) |
| `abstract_syntax_tree/lexer/lexer.spite` | 7 |
| `name_resolution/resolver.spite` | 4 |
| `symbols/symbol_table.spite` | 2 |
| `abstract_syntax_tree/parser/parser.spite` | 1 |

The emitter's ten are not a program's errors: each is something an earlier step should have refused or marked
(a call it cannot resolve, a foreign answer type not written yet), so each becomes a marker or a validator one
level up, and the emitter keeps only the crash for a marker it is given.

**Text written by representations, which moves into printers:** `written()` on `Token`,
`IdentifierExpression`, `LiteralExpression`, `TextLiteral`, `TextPiece`, `NamedType`, `GenericArgument`,
`ResolvedType` and `TypeUse`; `Instance.written_arguments()`; `summary()` on `Ordering`, `Resolver` and
`SymbolTable`; `Resolver.notes_text()`; `Problem.written()` and `Report.written()`;
`LowIntermediaryRepresentation.Describe`; and the entry's `high_shape`.

Where one of those texts is used as an identity and not shown (a type's written form as a key, the name of a
monomorphised instance), it is not a print: it becomes an identity of its own, kept by the step that owns it
(`name_resolution/mangle.spite` already is one), and a printer may show it.

## The entry

`spite_compiler.spite` reads as the list of what happens, with the validators beside the step they judge:

    the command line
    mapping                                   then validators/mapping
    symbols and abstract_syntax_tree, a class at a time, as names ask for them
                                              then validators/abstract_syntax_tree (unit)
    format: printers/spite writes back a file that changed, and it is read again
    name_resolution                           then validators/name_resolution
    high_intermediary_representation          then validators/high_intermediary_representation (unit, then program)
    high_optimization_passes                  unit passes, then program passes
    low_intermediary_representation           then validators/low_intermediary_representation
    low_optimization_passes                   unit passes, then program passes
    generators/windows_x64
    the outputs the settings ask for, each through its printer

## What else has to change

These came out of the review of 2026-10-21. Each is proposed by Claude and not confirmed, and each is cheaper
now than later.

1. **The high representation is typed.** Every value carries its resolved type as an object, not a string,
   and the builder answers it while it builds (the old repository's D618). Today the builder guesses the class
   of a receiver from how a name was declared or copied (D9, D11), and a call it cannot place names no owner.
   The type rules, the narrowing and the 263 diagnostics need types to stand on.
2. **Every node carries its place.** From the tree down to the instructions, each node holds its file, line
   and column, so a validator at any level names where the problem is.
3. **The representations use unions and enums, not strings.** An instruction's `kind`, an operation's
   `operator`, a parameter's type and a call's owner are strings today, so a pass cannot be checked to handle
   every case, and a misspelling is a silent miscompile.
4. **The generator writes 64-bit code for Windows** (`generators/windows_x64`, the Windows x64 calling
   convention). 32-bit x86 has eight registers, no 64-bit `Long`, and is not the target of the Linux port that
   follows. Mortaro's words in D3 say only that the compiler writes no C, and the 32 bits are not in them, so
   this supersedes that part of D3 only.
5. **The low representation is in SSA form, in basic blocks.** Today every value lives in a four-byte slot of
   the frame. Inlining, the placement proofs, the range proofs, keeping a `Buffer` value in a register and the
   register allocation all need a control flow graph of single assignments.
6. **Passes come in two kinds, unit and program**, with the same split as the validators. A unit pass reads
   one function or one class, is cached by the hash of its input, and is what a reload runs. A program pass
   (dropping what nothing reaches, inlining across classes, the placement of an object that leaves its
   function) needs the whole program and runs in a full build. Every function has a stable identity, so a
   cache has a key.
7. **An object lives on the heap until a pass proves it can live in the frame.** Today the frame is the
   default and D26 copies a returned object into the caller, which leaves a pointer to a dead frame wherever
   the object was kept, and makes two objects of one. The frame is a proof (D12), so it is the optimisation,
   not the default.
8. **How an argument is passed depends on the parameter's type only.** D25 passes an address or a number
   depending on where the caller's value came from, and the function called cannot tell which it was given.
9. **The language decisions made here go to the language.** D8 to D11 and D17 to D27 are unconfirmed, and
   several are the language's semantics (D20, D25, D26); they belong in the specification once Mortaro
   decides them. D10 says a type argument is given at run time, which contradicts the monomorphisation this
   compiler does.

## The order

1. **Representations hold data only, and the printers are their own folders.** Mechanical, and small today.
2. **The validators**: the folder, the contract, the markers, and the errors above moved into them.
3. **Places on every node**, and **unions instead of strings** in both representations.
4. **The typed high representation**, and the validators of types on it.
5. **The Spite printer and the formatter**, with the tree keeping its comments, and `--final-classes`.
6. **The 64-bit generator, the SSA low representation, and the two kinds of pass.**
7. **The heap as the default**, and the frame as the first placement proof.

The language comes after these, one value kind at a time, as `TODO.md` lists it.
