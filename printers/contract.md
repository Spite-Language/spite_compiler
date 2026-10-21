# printers

Every text the compiler writes from a representation. A printer is a folder holding one class,
`Printer(input)`, that answers `text(): String`.

## What a printer may do

- Read the one representation it is given, and nothing else.
- Answer text.

## What a printer never does

- Change what it is given.
- Write a file: the entry writes what a printer answers, where the settings say.
- Decide what is an error: that is a validator's ([`../ARCHITECTURE.md`](../ARCHITECTURE.md#validators)).

And the other way round: no representation has a function that writes it as text. A text that is an identity
and not something shown (the key of a type, the name of a monomorphised instance) belongs to the step that
owns it, not to a printer.

## The printers

| Folder | It takes | It writes |
|---|---|---|
| `diagnostics` | a `Diagnostics.Report` | each problem as `file:line: error: text`, then each note as `note: text` |
| `high_intermediary_representation` | one `HighClass` | the class, its attributes and its functions, one statement a line (`--high-ir=folder`) |
| `low_intermediary_representation` | the name of a class and its `LowFunction`s | each function and its instructions, one a line (`--low-ir=folder`) |

To come: `spite` (a tree printed as Spite: the formatter, and `--final-classes`), `optimization_report` and
`machine_code`.

## The format of the two representations

They are for people reading what a pass did, and nothing reads them back, so they may change with any commit.
The high one writes a value the way Spite would, with every operation in parentheses so the order is seen, and a
call with the class that owns it: `ExitCode.double_value(this, (total + index))`. A call whose class the builder
could not tell says so: `reset(this), its class unknown`. The low one writes `rN` for a virtual register and `pN`
for a place in the frame, and a jump names the index of the instruction it goes to.
