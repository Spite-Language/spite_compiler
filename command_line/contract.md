# command_line

The settings a run is given.

## What it answers

`Settings()` reads the compiler's own settings, declared in `environment.spite` like any program's (D1812, D1813, D1815):
the library fills and checks each from its flag or its variable and refuses a word given by position. The
compiler's `Environment` declares the private `_flags`, which the builder fills from the library's `_given_flags()`, for an `Environment`
declaring it, with every flag given; the library then refuses no flag, and `known_flag` checks the ones that name
no compiler setting against the `Build` the program declares (`validators/command_line/known_flag`).

- `folder`: always `.`, the folder the compiler runs in (D1775).
- `flags`: each flag given, a compiler setting with its checked value; `written_flags` and `bare_flags` as written.
  A field of the program's own `Build` with no flag is read from its variable (`PLAYER_COUNT`).
  A compiler setting that is on while `_flags` holds nothing and its variable is unset stops the run: that
  compiler was built by one that does not fill `_flags`, and would otherwise ignore every flag.
- `runs_the_program()`: neither `--check` nor `--build` was given, so the program is run once it is built.
- `high_intermediary_representation_folder`: from `--high-ir=folder`, where the high representation of each class
  is written.
- `low_intermediary_representation_folder`: from `--low-ir=folder`, the same for the low representation.
`Build.program` is the full path of the folder built. The program it runs is given no flags: its settings come from
the environment.

## What it does not do yet

The original's options (`--check`, `--build`, `--executable-path`, the program's own `Build` and `Environment`
settings, and the exact texts it refuses each one with) are issues labelled `tools`.
