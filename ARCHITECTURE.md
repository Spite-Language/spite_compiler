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

No step reaches back into an earlier one.

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
- A rule that needs the whole program runs once the program is complete; a rule about one class runs per class,
  and a reload runs only those.
- The message says what the old compiler's message says (`../SpiteLanguage/diagnostics`), in this compiler's
  words, and a `../SpiteSpec/conformance` test pins it.

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
