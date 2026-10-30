# Working on spite_compiler

Read `README.md`, then `ARCHITECTURE.md`, then the [issues](https://github.com/Spite-Language/spite_compiler/issues) (what is left, labelled by category, urgency and what blocks them). Read a folder's `contract.md` before changing it.

## The goal

Port the old compiler (0.0.6) into this architecture: the same language, the same
errors with the same words, the same optimisations, written so a small model can maintain it. The language
is decided; [the specification](https://github.com/Spite-Language/spite_spec/blob/master/specs/README.md) is the rule when anything disagrees.

## Rules

- Everything the language enforces is enforced on this code too: one statement per line, no call inside a call,
  no constructor as an argument, only `while`, no abbreviations, no single-letter names, no em dashes.
- A step never writes an error (a validator does) and a representation never writes text (a printer does).
- Anything that can go wrong silently is a bug: a crash that names its cause or a compile error, never a guess.
- No C, and no standard library code here. A new class in [spite_standard_library](https://github.com/Spite-Language/spite_standard_library) needs Mortaro's yes first.
- Keep markdown short. One fact in one place. What is left is a GitHub issue, never a file: a pull request that finishes one says `Closes #n`, one that finishes part of it comments what is left, and a fault you find and do not fix now is a new issue (label `urgency: silent` when it fails silently, D244).

## Work

- Work on `master`; there is no other branch.
  The default branch is `master`; do not rename it or suggest renaming it.
- Shared files (the files of [mortaros_spite](https://github.com/Spite-Language/mortaros_spite)) are written by every session. Edit them with targeted
  changes that match on surrounding text, never line numbers, and re-read immediately before writing. Never restore
  one from a backup: a whole-file overwrite has already lost a day of decisions once.
- Delegate to a cheaper subagent only when it is cheaper: if the round trips and the cold context cost more quota
  than doing the work inline, do it inline.
- A push whose source the last compiler in `STONES` (`scripts/bootstrap.sh`) cannot build, because it uses syntax
  or library names that compiler cannot read, adds a stepping stone to that list in the same push: the commit that
  teaches the compiler the new form before the source uses it, with the commits of the library, spec and docs
  beside it, so a fresh clone still builds from the release seed (#267). The list goes with the first stable release (D1764).
- Build once per batch of changes (about two minutes), then run [spite_spec](https://github.com/Spite-Language/spite_spec) (see `README.md`).
- A change here or in [spite_standard_library](https://github.com/Spite-Language/spite_standard_library) that changes
  what a program writes, what it answers or an error's words updates, in the same push, the specification page that
  states it (`spite_spec/specs/`) and the docs page that teaches it ([spite_documentation](https://github.com/Spite-Language/spite_documentation),
  `skills/spite/reference.md` included), examples and their output too. Search both for the old name before pushing.
- Every feature or fixed error gets a test in [spite_spec](https://github.com/Spite-Language/spite_spec): `tests/<name>` must pass, `conformance/<name>`
  must fail with the old compiler's exact error text.
- Commit as you go. Ask Mortaro first only for an architecture decision you are not sure of.
- Every decision, Mortaro's or an agent's, is a row in [`DECISIONS.md`](https://github.com/Spite-Language/mortaros_spite/blob/master/DECISIONS.md), the canon for every Spite
  repository, with the next free number; read [`mortaros_notes.md`](https://github.com/Spite-Language/mortaros_spite/blob/master/mortaros_notes.md) first, and put questions only
  Mortaro can answer in [`mortaros_missing_decisions.md`](https://github.com/Spite-Language/mortaros_spite/blob/master/mortaros_missing_decisions.md). This repository keeps no decision log.
- Stage paths explicitly; never `git add -A` while another session works here.

## Commits

A gitmoji, then a lowercase summary of what the change does, then the model that wrote it:

    ✨ the switch statement is lowered

    Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>

Common: ✨ feature · 🐛 fix · ♻️ refactor · ✅ tests · 📝 docs · 🔥 removal · ⚡ performance · 🚨 rules.
`scripts/hooks/commit-msg` enforces it: run `git config core.hooksPath scripts/hooks` once per clone.
