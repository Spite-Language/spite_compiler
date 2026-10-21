# Working on SpiteCompiler

The new Spite compiler, written in Spite. It is the compiler and nothing else: no launcher, no language
documentation, no standard library of its own. It is built by the old compiler until it can build itself.

**Read `README.md` first, then `TODO.md`.** The README says how the compiler is run and what each step is.
The TODO is the list of what is left, in the order it is done, and it is kept up to date as the work moves:
a change that changes what is missing changes it in the same commit.

## Where things live

Each step of the pipeline is a folder, and each folder holds one class per file:

| The folder | What it owns |
|---|---|
| `diagnostics/` | one `Report` per run, and the `Problem` it holds |
| `mapping/` | the folders a program can use, and the namespace each becomes |
| `symbols/` | the class file a written name reaches, and the reading of it |
| `command_line/` | the settings a run is given |
| `abstract_syntax_tree/` | the lexer, the parser, the shapes and the ordering check |
| `name_resolution/` | every type written, and the instance every generic is minted as |
| `high_intermediary_representation/` | the program as values and control flow, and the builder that makes it |
| `high_optimization_passes/` | `fold_constants` and `drop_unreachable_functions` |
| `low_intermediary_representation/` | the program as a flat instruction list, and the lowering that makes it |
| `low_optimization_passes/` | `peephole_jumps` and `fold_away_moves` |
| `generators/windows_x86/` | the machine code, and the PE file around it |
| `validators/` | every error, one rule per folder, each reading one representation (D28) |
| `printers/` | every text written from a representation: the formatter, the reports, the IR listings (D29) |

Each folder holds a `contract.md`: what the step takes, what it answers, and what it does not do. A change
to what a step owns changes its contract in the same commit. The entrypoint, `spite_compiler.spite`, sets the
order of the steps up and nothing else, so the shape of a compilation is one screen.

The other documents are `ARCHITECTURE.md` (the four kinds of folder: steps, passes, validators and printers,
and what has to change to get there), `TODO.md` (what is left) and `HOT_RELOAD.md` (how the hot reload has to
work, and what can go wrong with it). A step never writes an error and a representation never writes text:
the first is a validator's job and the second a printer's.

## The rules the language holds

Everything the old compiler enforces is enforced here too, and every rule is a compile error and never a
warning:

- A statement is one line.
- A call is never passed into another call, and a constructor is never an argument.
- Only `while` loops.
- `assert` and `crash` take no message.
- No abbreviations, and no em dashes.
- A comment is one line holding a link to a heading in a markdown file beside it.
- File and folder names are lowercase words joined by `_`; classes are PascalCase; a single letter is not a
  name.

**Ask of every change: does it keep the compiler free of C, and does it keep the standard library out of
this repository?** The compiler writes machine code, and the standard library is imported from another
repository, so a change that writes C, or that copies a piece of the library here, is a change in the wrong
direction. See `TODO.md` for what the compiler must reach, and the goal at the top of it.

**Anything that can go wrong silently is a bug.** A diagnostic names the file, the line and the fix, and a
step that fails stops the run there: a syntax error dies at the syntax tree and never reaches a later step.

## Writing

- **No em dashes, anywhere.** Not the character, and not two hyphens between spaces standing in for one.
  This covers the code, the comments, the documents and the commit messages. End the sentence, or use a colon,
  a comma or parentheses.
- **The compiler is the formatter**, and it formats the program before it compiles it, so what is compiled and
  every line an error names is the formatted file. Write the one style: the style the compiler writes.
- **The names say what they hold.** A name is what it is, not an abbreviation of it, and not a single letter.
- **Nothing is left over.** A variable that is only written and never read is an error, and so is a function
  nothing calls.

## Commits

**Ask the owner before you commit, and wait for the answer.** This repository is a port, and what a commit
carries is what the port carries, so no commit is made without the owner's authorization. Before you commit,
show these two things:

- **What to test.** The commands that prove the change works, and what each one should answer. For a change
  to the compiler, that is the build, the demo program, and the exit code the program leaves. For a change to
  a document, that is the document itself, and every claim it makes about the code.
- **What to review.** The files the commit touches, and what to look at in them: the rules the change has to
  keep (no em dashes, the naming, one statement per line, no call inside a call), the contract of any step
  whose behaviour changed, and the lines of `TODO.md` that the change makes true, or untrue.

The commit is made after the answer, and not before.

**Always start a commit message with a gitmoji.** This is not optional.

```
✨ add the builder that lowers a class into the high representation
🐛 the lowering gives a place and a register the same number
📝 the to-do list is the work that is left, in the order it is done
♻️ the emitter writes the module a reload loads
✅ the demo program answers 4072
🔥 drop the sample program
⚡ the emitter caches the machine code per function
🚨 the linter refuses a name that is an abbreviation
🏗️ split the generator into the layout and the emitter
🔒 the manifest holds no path the program did not name
⏪ revert: "call through a slot" (breaks the production build)
```

Common ones: ✨ feature · 🐛 bugfix · 📝 docs · ♻️ refactor · ✅ tests · 🔥 removal · ⚡ performance · 🚨 lints ·
🏗️ structure · 🔒 security · ⏪ revert. The subject is the imperative and says what the change does, not
what area it touches.

**Every commit names the model that wrote it**, so a change that breaks something has an owner:

```
Co-authored-by: MiniMax M3.1 Flash <noreply@minimax.io>
```

Name the model you are actually running as, not just the company. A human committing by hand writes their
own:

```
Co-authored-by: Mortaro <christian.mortaro@gmail.com>
```

**Never `git add -A` or `git add .`** while another session may be working. Stage the paths you changed, one
by one, and look at what you staged before you commit. The shared files below are the ones that get lost
that way.

The rules are enforced, not only written down: `scripts/hooks/commit-msg` refuses a message with an em dash,
without a gitmoji, or without the model credit. It is versioned here, so a clone runs it once:

```
git config core.hooksPath scripts/hooks
```

## Branches

**`master` is the release branch, and the work happens on `next`.** Every change starts from `next` and goes
back into `next`, and `next` is merged into `master` only when the TODO lists nothing under what is missing
and a full build passes on exactly what is merged. `master` is never pushed to directly.

The name `main` is not used: the branch is `master`.

## Building and running

Three commands, and the README says what each one does:

```
.spite/spite-0.0.6-windows/spite.exe .spite/spite_compiler --build --executable-path=.spite/spite.exe
.spite/spite.exe ../SpiteSpec/tests/exit_code
../SpiteSpec/tests/exit_code/.spite/build/exit_code.exe
```

The first builds this compiler with the old compiler, the second builds a test program with the compiler
that was just built, and the third runs it. The compiler is written to `.spite/spite.exe` so it is never
mixed up with the old compiler's own.

**A build takes about two minutes, so batch the work.** Make every change you can see, then build once and
read the errors together. There is no test suite here yet (`TODO.md` says so), so the build and the demo
program are the check, and both are quick to run.

## Shared files, when more than one agent is running

`TODO.md`, `README.md`, `HOT_RELOAD.md` and the `contract.md` of any step are written by every session, and
they are lost by a whole-file overwrite. Edit them with a targeted change, matching on the text around the
place, and read the file again immediately before writing it.

A step's own files are its own: a session working on the emitter does not touch the lexer, and one working
on the name resolution does not touch the passes.

**Never `git add -A` or `git add .`** while another session may be working: a commit that sweeps up another
session's work in progress has to be split apart afterwards.

## The project

The compiler is a pipeline, and each step takes the previous step's answer and hands its own answer to the
next one. No step reaches back into another, and a step that cannot do its job says so and the run stops
there.

The goal is in `TODO.md`: the old compiler builds this one, and then this one builds the original
repository's test suite, with the same outputs, the same counts of allocations and frees, and the same
errors with the same texts.
