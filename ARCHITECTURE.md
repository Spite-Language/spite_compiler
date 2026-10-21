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
    format                                 printers/spite writes back a changed file, which is read again
    name_resolution                        then validators/name_resolution
    high_intermediary_representation       then validators/high_intermediary_representation
    high_optimization_passes               unit passes, then program passes
    low_intermediary_representation        then validators/low_intermediary_representation
    low_optimization_passes                unit passes, then program passes
    generators/windows_x64
    outputs                                each through its printer

The run stops after the first validators that find an error. No step reaches back into an earlier one.

## Steps never fail

A step that cannot build something puts a marker there and goes on. The validator of that level turns the marker
into the error. A generator given a marker crashes, naming the compiler's fault. So every error text lives in a
validator, nothing is dropped, and one file reports all its syntax errors at once.

## Validators

`validators/<level>/<rule>/validator.spite` holds a class `Validator(input)` answering
`problems(): List<Diagnostics.Problem>`, and `contract.md` holds the rule, its exact error texts, and the
`../SpiteSpec/conformance` test that proves it.

- A rule lives at the earliest level that has the facts it needs.
- A validator reads one representation and never changes it.
- The validators of one level do not depend on each other.
- A unit validator reads one class and is cached with it (a reload runs it); a program validator needs the whole
  program. Their input types differ, so one cannot be run as the other.
- A `Problem` is data: file, line, column, rule, text, and the class and function it is in.
- The low representation's validators find faults of the compiler, not of the program.

## Printers

`printers/<what>/printer.spite` holds a class `Printer(input)` answering `text(): String`. A printer never writes
a file and never changes its input.

- `printers/spite` prints a tree as Spite. It is the formatter, and `--final-classes` uses it on a merged class.
  The tree therefore keeps comments, blank lines and how literals were spelled.
- `printers/diagnostics`, `printers/high_intermediary_representation`, `printers/low_intermediary_representation`,
  `printers/optimization_report`, `printers/machine_code`.

A text that is an identity (a type's key, an instance's name) is not printing: it belongs to the step that owns it.

## Passes

`<level>_optimization_passes/<name>/pass.spite` holds a class `Pass(input)` answering `transformed()`. A unit pass
reads one function or class and is cached by the hash of its input; a reload runs only unit passes. A program
pass needs the whole program (tree shaking, inlining across classes, placement of objects that leave their
function). Each optimisation and each proof is a pass of its own.
