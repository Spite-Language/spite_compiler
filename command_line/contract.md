# command_line

The settings a run is given. `Settings()` reads the arguments of the compiler's own process.

## What it answers

- `folder`: the program, the one argument that is not a flag. `.` is the folder the compiler runs in.
- `high_intermediary_representation_folder`: from `--high-ir=folder`, where the high representation of each class
  is written.
- `low_intermediary_representation_folder`: from `--low-ir=folder`, the same for the low representation.
- `unknown_flags`: every other flag, which the entry refuses: `'--flag' is not a compiler option`.

## What it does not do yet

The original's options (`--check`, `--build`, `--executable-path`, the program's own `Build` and `Environment`
settings, and the exact texts it refuses each one with) are listed in `TODO.md` under the outputs.
