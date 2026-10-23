# SpiteCompiler

The Spite compiler, written in Spite. It writes Windows machine code directly: no C anywhere. The language is
specified in `../SpiteLanguage`, the standard library is `../SpiteStandardLibrary`, and the tests are
`../SpiteSpec`.

## Build it

The old compiler builds this one:

    .spite/spite-0.0.6-windows/spite.exe .spite/spite_compiler --build --executable-path=.spite/spite.exe

`.spite/spite_compiler` is a junction to this folder under a snake_case name. `.spite/library` is a junction to
`../SpiteStandardLibrary`. The compiler carries every class it adds to a program inside its own executable
(`ARCHITECTURE.md`), so a release is `spite.exe` and `library/`.

## Run it

    .spite/spite.exe <program folder>
    .spite/spite.exe <program folder> --high-ir=folder --low-ir=folder

The executable goes to `<program>/.spite/build/<name>.exe`, and its exit code is what the entry constructor
answers. `--high-ir` and `--low-ir` write each class's representation, one `.ir` file per class.

A program names everything it loads in its first lines. There is no launcher and no library search:

    func ExitCode(): Integer {
        load "../../../SpiteCompiler/.spite/library/common"

## Test it

From `../SpiteSpec`:

    ../SpiteCompiler/.spite/spite-0.0.6-windows/spite.exe runner
    ../SpiteCompiler/.spite/spite-0.0.6-windows/spite.exe runner tests/sum

## Read next

`ARCHITECTURE.md` (how it is put together), `TODO.md` (what is left), `HOT_RELOAD.md`, and each folder's
`contract.md`.
