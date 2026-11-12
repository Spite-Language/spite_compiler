# fixes

What the compiler changes in a program's own files instead of refusing them, and the restart that follows.

- `fixes.spite`: the writer, `Fixes.Fixes`; its `run` writes each file a fix changed through `printers/spite` and restarts
  the compile on the fixed files.
- `move.spite`: a file or folder `run` renames once every file is written, through a passing name when only the case changes.
- `later_change.spite`, `renaming.spite`: what `fixes.spite` does for a fix found while the proofs still read the blocks, a statement replaced or a name renamed; a rename only changes names, and the tree it leaves is for printing.
- `tokens`, `abstract_syntax_tree`, `symbols`, `after_building`: the layers, by when their facts exist.

A layer holds one folder per rule, `<rule>/fix.spite` with the class `Fix`, and reaches them through its entry: `tokens/every_fix.spite`, `abstract_syntax_tree/every_fix.spite`, `symbols/every_fix.spite` or `after_building/every_fix.spite`.
A fix changes the representation it is given and answers a `fixed:` problem for each change; it writes no file.
Its rule's validator decides whether the fix can be done, and the fix acts on that answer (`is_fixable()`) and only rewrites (D2005): no function here answers a `Boolean`, and what a fix needs to rewrite it asks its rule. `compiler_rules_are_validators` refuses a fixer that decides.
The step that asked the rule tells what it answers a mistake (`answer.tell()`, or `Context.tell` after building), right after asking, as it does for every rule; neither a rule nor a fix stops the compile.
