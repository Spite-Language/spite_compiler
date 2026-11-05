# outputs

Every text and file the compiler writes once the program is built.

- `outputs.spite`: the entry, `Outputs(command_line, symbols, model)`; its `run` writes the texts, then runs the generator and writes the executable.
- `final_classes.spite` and `final_classes_folder.spite`: the merged classes `--final-classes` writes.
- `reload_facts.spite`: the classes and frames a reload host is told.
- `relative_paths.spite`: the link from one folder to another.

It writes what the printers answer and the generator's bytes; it decides no error.
