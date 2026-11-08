# command_line

The settings a run is given.

`command_line.spite` is the entry: `CommandLine`'s `run()` reads `Settings()`, names the program's folder and entry
(`program_folder`, `program_name`), and removes the last build unless the run is a reload or a `--check`. `connect.spite`
answers `--connect`, handing the port to `validators/command_line/connect_port` and what the socket answered to
`validators/command_line/connection`, `inspection.spite` says whether a run is interactive, `settings_file.spite` reads the `.env` file and
`reload_host_reader.spite` reads a running program's manifest.

## What it answers

`Settings()` reads the compiler's own settings, declared in `environment.spite` like any program's (D1812, D1813, D1815):
the library fills and checks each from its flag or its variable and refuses a word given by position. The
compiler's `Environment` declares the private `_flags`, which the builder fills from the library's `_given_flags()`, for an `Environment`
declaring it, with every flag given; the library then refuses no flag, and `known_flag` checks the ones that name
no compiler setting against the `Build` the program declares (`validators/command_line/known_flag`).

- `folder`: always `.`, the folder the compiler runs in (D1775).
- `flags`: each flag given, a compiler setting with its checked value; `written_flags` and `bare_flags` as written.
  A field of the program's own `Build` with no flag is read from its variable (`PLAYER_COUNT`), then from the
  `.env` file of the folder built (`SettingsFile`, which build conditions read too).
  A compiler setting that is on while `_flags` holds nothing and its variable is unset stops the run: that
  compiler was built by one that does not fill `_flags`, and would otherwise ignore every flag.
- `CommandLine.runs_the_program()`: neither `--check` nor `--build` was given, so the program is run once it is built.
- `writes_high_ir`: from `--high-ir`, a Boolean; the whole program's high representation is written to
  `.spite/build/<name>.high_ir.txt`.
- `writes_low_ir`: from `--low-ir`, the same for the low representation, `.spite/build/<name>.low_ir.txt`.
A reload reads the running program's manifest (`reload_host_reader.spite`) and hands each line, and what cannot be read, to
`validators/command_line/hot_reload`; a program the system cannot start is decided by `validators/command_line/runnable_program`.
A fix found after building restarts the compile on the fixed files: `fixes/fixes.spite` runs the compiler again with the
flags it was given, in the same folder and environment, and ends this run with that run's exit code (D1833).
`Build.program` is the full path of the folder built. The program it runs is given no flags: its settings come from
the environment.

## The flags

`environment.spite` declares every flag once, a line each, `var verbose = false`. Nothing else lists them: `Settings()`
walks `Environment.attributes` and reads each by its type, and `Environment` answers by name what the rest asks
(`flag_names()`, `is_build_option`, `is_output`, `is_the_compilers_own`, `is_read_without_a_library`,
`is_left_out_of_a_reload`, `is_connection`). A flag that no group names is a plain flag of the compiler: read, checked as
its type, and never asked of the program's `Build`. The groups are the private lists of the file, each entry a name
the compiler checks (`Environment.attributes["check"].name` is a compile error for a flag that does not exist), so a
removed or misspelled flag stops the build instead of being ignored. A flag joins a group only to say more about it:
`_outputs` change nothing the program does, `_program_options` are the ones a program reads as `Build.x`,
`_other_build_reads` the two more `Build` reads, `_without_a_library` the two a program with no `Build` takes, and
`_connection` the flags of `--connect`. `scripts/flag_is_one_line.sh` builds a copy of the compiler with one more flag and checks it is read, checked and refused.

## What it does not do yet

The original's options (`--check`, `--build`, `--executable-path`, the program's own `Build` and `Environment`
settings, and the exact texts it refuses each one with) are issues labelled `tools`.
