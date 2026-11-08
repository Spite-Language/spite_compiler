# abstract_syntax_tree

The step from a file's text to its tree, once per class file.

- `abstract_syntax_tree.spite`: the entry, `AbstractSyntaxTree(path, namespace, text)`; its `run` lexes, parses and answers a `Shapes.SourceFile`.
- `tokens`: what the lexer answers, and the `Unreadable` it stopped at.
- `lexer`: the text as tokens.
- `parser`: the tokens as a tree.
- `shapes`: the tree, data only (declarations, expressions, statements, types).
- `walk`: the walks over a tree that rules and fixes share.
- `default_guard`, `names`, `unused_names`, `switch_chain`: what a rule of `validators/abstract_syntax_tree` and its fix, or that rule alone, read in a tree; a rule's folder holds only the rule.

The tree holds what was written and where; it decides no error (the rules of `validators/abstract_syntax_tree` do) and
writes no text (`printers/spite` does).
