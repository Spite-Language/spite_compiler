# generators/windows_x86

The last step: machine code, and the file around it.

## What it takes and answers

It takes a low representation and answers bytes: a Windows PE executable file, written to disk, that runs.

## The split

- `pe.spite` lays the file out. It owns the headers, the section table, the import table and where every
  label lands, because those are all questions about the shape of the whole file and answering them one
  instruction at a time would mean writing the file twice.
- `emitter.spite` turns one instruction into bytes. It owns the encoding of each instruction, the register
  numbers, and how the machine's calling convention lays arguments down.
- `registers.spite` is the one place that knows which machine register a virtual register becomes.
- `layout.spite` owns every address in the file: the image base, the sections, and the import table.
- `fixup.spite` is a patch to make once every instruction is written and the places they land are known.

## What is built

A 32-bit PE for Windows, two sections, importing `ExitProcess` from `kernel32.dll`, with the program
computing a whole number and answering it as the process exit code. That is the smallest thing that is
really a Windows program rather than a demonstration.

`examples/exit_code` is the program that proves it: it computes 4072 with a loop and a call, and the
executable it is written to leaves that as the exit code.

## What is not built

- Calling out to the standard library, so nothing prints and nothing reads a file yet.
- The 64-bit machine, and every machine but this one.
- Relocations and a relocatable image. The file is fixed at the address it is written for, which is
  allowed and is what the small programs the compiler builds to test itself need.
- Registers. Every virtual register lives in a stack slot, so every value is written and read through
  memory.
- Anything above the subset `low_intermediary_representation` lowers.

## The calling convention

The Windows 32-bit convention on `cdecl` is what the emitter follows: arguments pushed right to left onto
the stack, the caller clearing them, `eax` answering a value, `esp` holding the frame. A Spite class is a
pointer to its own block, so a method takes the instance as its first argument, exactly as the old
compiler's generated C did.

## The frame is the usual one: `ebp` is the frame pointer, the parameters are at `[ebp + 8]` and up, and the
values the function made live below it, each at its own slot.

## The object and its attributes

A class's instance is a block of memory, and the block lives in the frame of the function that made it.
Its address is a value like any other, so it is held in a slot and passed to a method as the first
argument.

An attribute is at an offset from that address, so reading one is a load through the address in the
register: `mov eax, [base]`, then `mov eax, [eax + offset]`. Writing one is the same with the value in
`eax` and the address in `ecx`: `mov [ecx + offset], eax`. The block itself is addressed with `lea`, which
is what gives the frame slot its address.

The whole-number division is a signed one, the way Go has it: the quotient is truncated toward zero and
the remainder keeps the sign of the dividend. The machine's `idiv` does exactly that, and the sign of the
dividend is put in the high half of it with `cdq` first. The `cdq` is the byte `0x99`: the byte `0x63` is
the `arpl` instruction in this mode, and the machine would read the two together and never divide at all.

## How a call finds the function it reaches

A call names the function it reaches and the class that owns it, and the emitter looks the two up
together: the class that owns it and its own name. The class of the caller is not a candidate, because a
call on an instance reaches a function of the receiver's class and not one of the caller's.

When the owner is not known yet, the emitter looks the name up on its own, and a name that two classes
have is an error: the call cannot say which one it means, and the compiler will not guess.
