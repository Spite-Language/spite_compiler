# command_line

The settings a run is given. `Settings()` reads the arguments of the compiler's own process.

## What it answers

- `folder`: the program, the first argument that is not a flag, or `.`, the folder the compiler runs in, when none is given.
- `given_arguments`: every other argument, in order. `passed_arguments(environment)` answers the ones the
  program is run with: each word that is not a flag, and each flag naming a setting its `Environment` declares.
- `runs_the_program()`: neither `--check` nor `--build` was given, so the program is run once it is built.
- `high_intermediary_representation_folder`: from `--high-ir=folder`, where the high representation of each class
  is written.
- `low_intermediary_representation_folder`: from `--low-ir=folder`, the same for the low representation.
Any other flag stops the run (`validators/command_line/known_flag`). A run that names no folder builds the
folder it is run from (D1775).

## What it does not do yet

The original's options (`--check`, `--build`, `--executable-path`, the program's own `Build` and `Environment`
settings, and the exact texts it refuses each one with) are issues labelled `tools`.
