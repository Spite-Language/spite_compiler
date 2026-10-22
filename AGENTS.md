# Working on SpiteCompiler

Read `README.md`, then `ARCHITECTURE.md`, then `TODO.md`. Read a folder's `contract.md` before changing it.

## The goal

Port the old compiler (`../SpiteLanguage/compiler`) into this architecture: the same language, the same
errors with the same words, the same optimisations, written so a small model can maintain it. The language
is decided; `../SpiteLanguage/specs` is the rule when anything disagrees.

## Rules

- Everything the language enforces is enforced on this code too: one statement per line, no call inside a call,
  no constructor as an argument, only `while`, no abbreviations, no single-letter names, no em dashes.
- A step never writes an error (a validator does) and a representation never writes text (a printer does).
- Anything that can go wrong silently is a bug: a crash that names its cause or a compile error, never a guess.
- No C, and no standard library code here. A new class in `../SpiteStandardLibrary` needs Mortaro's yes first.
- Keep markdown short. One fact in one place. `TODO.md` is one line per thing left; delete it when done.

## Work

- Work on `master`; there is no other branch.
- Build once per batch of changes (about two minutes), then run `../SpiteSpec` (see `README.md`).
- Every feature or fixed error gets a test in `../SpiteSpec`: `tests/<name>` must pass, `conformance/<name>`
  must fail with the old compiler's exact error text.
- Commit as you go. Ask Mortaro first only for an architecture decision you are not sure of.
- Every decision, Mortaro's or an agent's, is a row in `../MortarosSpite/DECISIONS.md`, the canon for every Spite
  repository, with the next free number; read `../MortarosSpite/mortaros_notes.md` first, and put questions only
  Mortaro can answer in `../MortarosSpite/mortaros_missing_decisions.md`. This repository keeps no decision log.
- Stage paths explicitly; never `git add -A` while another session works here.

## Commits

A gitmoji, then a lowercase summary of what the change does, then the model that wrote it:

    ✨ the switch statement is lowered

    Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>

Common: ✨ feature · 🐛 fix · ♻️ refactor · ✅ tests · 📝 docs · 🔥 removal · ⚡ performance · 🚨 rules.
`scripts/hooks/commit-msg` enforces it: run `git config core.hooksPath scripts/hooks` once per clone.
