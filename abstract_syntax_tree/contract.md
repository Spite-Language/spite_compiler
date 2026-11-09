# abstract_syntax_tree

The step from a file's text to its tree, once per class file.

- `abstract_syntax_tree.spite`: the entry, `AbstractSyntaxTree(path, namespace, text)`; its `run` lexes, parses and answers a `Shapes.SourceFile`.
- `tokens`: what the lexer answers, and the `Unreadable` pieces it could not read as a token.
- `lexer`: the text as tokens; what starts no token is kept as an `Unreadable` and the lexer reads on.
- `parser`: the tokens as a tree; what does not continue the grammar is kept as a `Shapes.Unfit` and the parser reads
  on at the next safe point. A text's holes are read by a parser of their own, kept as a `Hole`.
- `shapes`: the tree, data only (declarations, expressions, statements, types), and the `Unfit` pieces.
- `walk`: the walks over a tree that rules and fixes share.
- `default_guard`, `names`, `unused_names`, `switch_chain`: what a rule of `validators/abstract_syntax_tree` and its fix, or that rule alone, read in a tree; a rule's folder holds only the rule.

The tree holds what was written and where; it decides no error (the rules of `validators/abstract_syntax_tree` do,
`spelling` and `syntax` from the tokens and the kept pieces as soon as a file is lexed and parsed) and writes no text
(`printers/spite` does).
