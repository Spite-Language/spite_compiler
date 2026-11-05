# symbols

The classes of the program, read a class at a time as names ask for them.

- `symbols.spite`: the entry, `Symbols(map, folder, flags)`; its `run` answers a `symbol_table.spite`.
- `build_condition.spite`: which build conditions hold.
- `library_names.spite` and `machinery_text.spite`: the library functions the compiler knows by name and the text it writes for the machinery.
- `repeated_declaration.spite`, `repeated_declarations.spite` and `disagreement.spite`: the unions and types two classes declare alike.

It reads each class through `abstract_syntax_tree`; what it finds wrong goes to `validators/abstract_syntax_tree` and `validators/mapping`.
