# symbols

The classes of the program, read a class at a time as names ask for them.

- `symbols.spite`: the entry, `Symbols(map, folder, flags)`; its `run` answers a `symbol_table.spite`.
- `mention_reading.spite`: a class read whose mentions still wait to be read (`../ARCHITECTURE.md#mentioned-classes-are-read-from-a-stack`).
- `build_condition.spite`: which build conditions hold.
- `library_names.spite` and `machinery_names.spite`: the library functions and classes the compiler knows by name.
- `preloads.spite`, `preloaded_volume.spite` and `volume_table.spite`: the volumes the program's `preload` lines make, and their files as the sorted table the lowering lays out.
- `repetition.spite`, `repeated_declarations.spite` and `disagreement.spite`: the unions and types two classes declare alike.

`SymbolTable.read_the_standard_library()` adds the folder of the system compiled for, from the library
`command_line` chose (`Mapping.StandardLibrary`), as the first root after the program's, before the entry is read.
A `load` of that library is not followed: `validators/mapping/library_load` answers it fixable and
`fixes/symbols/library_load` removes it; a `load` of another library is that rule's mistake.

It reads each class through `abstract_syntax_tree`; what it finds wrong goes to `validators/abstract_syntax_tree` and `validators/mapping`.
