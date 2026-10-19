# example

A whole program, and the test that the compiler is worth something.

`example/example.spite` sums the numbers from one to five in a loop and answers the sum.

    func Example(): Integer {
        var total = 0
        var index = 1
        while index < 5 {
            total = total + index
            index = index + 1
        }
        return total
    }

It is the smallest thing that has a local, an arithmetic operation, a comparison, a loop and a value
that leaves the program.

## How it is compiled

    spite example

The compiler reads `example/example.spite`, resolves its types, builds its high representation, folds
what it can, drops what nothing reaches, lowers it to instructions, threads its jumps, folds its moves,
and writes the machine code and the PE file around it:

    wrote example/.spite/build/example.exe

The executable is a 32-bit PE for Windows with one section and an import of `ExitProcess` from
`kernel32.dll`. It runs, and its exit code is the sum:

    example\.spite\build\example.exe
    echo %ERRORLEVEL%     10

## What it does not do

- A class is a pointer to its own block in the real language. The backend has no objects yet, so a
  `var` and an attribute are both a place in the frame.
- The exit code comes from the value the entry function answers. A Spite program normally sets its exit
  code by calling `Program().exit(code)`, and that is not lowered yet: the backend knows whole numbers,
  and it does not know the program object.
- A call that passes an argument works: `examples/exit_code` has one, and the program answers 4072.
