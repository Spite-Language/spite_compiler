# spite_compiler

The Spite compiler, written in Spite. It writes Windows machine code directly: no C anywhere. The language is
specified in [spite_spec](https://github.com/Spite-Language/spite_spec) and [spite_documentation](https://github.com/Spite-Language/spite_documentation), the standard library is [spite_standard_library](https://github.com/Spite-Language/spite_standard_library), and the tests are
[spite_spec](https://github.com/Spite-Language/spite_spec).

## Build it

Clone the repositories side by side under one folder, under their own names:

    gh repo clone Spite-Language/spite_compiler
    gh repo clone Spite-Language/spite_standard_library
    gh repo clone Spite-Language/spite_spec
    bash spite_compiler/scripts/bootstrap.sh --install

The script downloads the seed compiler (the last one this source built itself) into `spite_compiler/.spite/`,
builds the source with it until two builds write the same bytes, and installs that compiler as
`spite_compiler/.spite/spite.exe` (`ARCHITECTURE.md`, "How the compiler is built"). After that the compiler
builds itself, from the folder above this one:

    spite_compiler/.spite/spite.exe spite_compiler --build --executable-path=spite_compiler/.spite/spite_next.exe

The compiler carries every class it adds to a program inside its own executable (`ARCHITECTURE.md`), so a release
is `spite.exe` and the library.

## Run it

    .spite/spite.exe <program folder>
    .spite/spite.exe <program folder> --high-ir=folder --low-ir=folder

The executable goes to `<program>/.spite/build/<name>.exe`, and its exit code is what the entry constructor
answers. `--high-ir` and `--low-ir` write each class's representation, one `.ir` file per class.

A program names everything it loads in its first lines, the standard library by its path from the program's
folder. There is no launcher and no library search:

    func ExitCode(): Integer {
        load "../../../spite_standard_library/common"

## Test it

From the clone of [spite_spec](https://github.com/Spite-Language/spite_spec) beside this one:

    ../spite_compiler/.spite/spite.exe runner --build
    runner/.spite/build/runner.exe
    runner/.spite/build/runner.exe tests/sum

## Read next

`ARCHITECTURE.md` (how it is put together), the [issues](https://github.com/Spite-Language/spite_compiler/issues) (what is left), `HOT_RELOAD.md`, and each folder's
`contract.md`.
