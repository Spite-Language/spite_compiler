# Decisions

Every decision about this compiler, in the order it was made. A decision lives twice: in the document that
teaches that part of the compiler, which is where the rule is, and as a row here, which says when it was made,
by whom and why. A decision that exists only in a conversation will be re-litigated.

**The log is append-only.** A row is never edited, renumbered, reordered or removed. A decision that changes an
earlier one is a new row that names the one it supersedes ("superseding D1"), and the document that teaches
the rule is changed to match.

**How to add a row:** append one line at the end of the table: `| date | **Dnnn** (decided by Mortaro): what was
decided, in a sentence or two, and why |`, with the next free number. A proposal an agent makes is written
"(proposed by Claude, unconfirmed)" and never recorded as decided; a row that only builds a decision says so,
"(implements D157; ...)". Then put the rule itself into the document that teaches it, in the same commit. With
more than one agent running, edit this file only by appending, match on the surrounding text rather than on line
numbers, and re-read it immediately before writing it (`AGENTS.md`).

## Decision log

| Date | Decision |
|---|---|
| 2026-10-19 | **D1** (decided by Mortaro: "the first line of the program should be a load to the standard library instead of the auto search, very explicit"): **a program names the standard library in its first line, and the compiler follows the load lines.** The compiler does not go looking for a library, and there is no environment variable that names one: a program says which folders it loads, the compiler reads them, and a name that resolves to nothing is a crash. The library is a folder like any other, so anyone can bring their own, and the compiler is the same for all of them. |
| 2026-10-19 | **D2** (decided by Mortaro: "the idea of a Launcher goes away, the user program is the entrypoint and it loads the standard library + its os environment"): **there is no launcher.** The user's program is the entrypoint, and it loads the standard library and the folder of its operating system itself. The compiler does not read a `launcher/launcher.spite` and does not load anything the program did not ask for. |
| 2026-10-19 | **D3** (decided by Mortaro: "our compiler will NOT deal with any C code"): **the compiler writes machine code.** A 32-bit PE for Windows, written by the emitter, with no C in between: no C is written, no C is read, and no C compiler is needed to build a program. The standard library is imported from another repository and is not part of this one. |
| 2026-10-19 | **D4** (decided by Mortaro: "for now its okay that the user cannot reopen methods from standard library he mostly only needs to add methods to the standard library anyway"): **a class may be reopened, and the standard library's own methods keep the priority.** A later declaration replaces an earlier one of the same name, and the names the later one does not have are kept, so a program may add to a class of the standard library. For now it may not replace the methods the standard library declares: the standard library's declaration of a name is the one that runs, and a program that declares the same name is refused rather than silently losing. |
| 2026-10-19 | **D5** (decided by Mortaro: "a class that 'lost load priority' should not replace the current in memory code"): **the declaration that wins the load order is the one the program runs, and a change to a file that lost is not a change to the class that runs.** The load order decides which declaration of a name is the class's, and that fact is written down when the class is compiled, because the hot reload compares a save against it: a save in a file that only loses leaves the code in memory alone. |
| 2026-10-19 | **D6** (decided by Mortaro): **the program's exit code is the value its entry constructor answers.** A constructor that answers nothing leaves the exit code at 0. The original sets the exit code by calling `Program().exit(code)`, and that is not lowered yet. |
| 2026-10-19 | **D7** (decided by Mortaro: "create a new folder under D:/Projects called SpiteSpec and inside it a tests subfolder, for each thing we test we move a program there update it to the new format and run those examples from there, so later it gets shiped as its own repo with up to date tests instead of mixed things"): **the tests live in their own repository, `D:/Projects/SpiteSpec`, and not in the compiler's.** This repository is the compiler and nothing else. One folder per program under `tests`, named after what the program is, each standing on its own, and each ported to the new format when the part of the language it needs works. |
| 2026-10-19 | **D8** (proposed by MiniMax M3.1 Flash, unconfirmed): **a function is named by the class that owns it and its own name, and a call names the class that owns the function it reaches.** `Counter.reset` and `Timer.reset` are two functions, so a call that says only "reset" says neither, and the reachability pass cannot tell the two apart. A call whose owner the compiler cannot tell yet names no owner at all, and the passes that need one fall back to the name alone, which keeps every function of that name. |
| 2026-10-19 | **D9** (proposed by MiniMax M3.1 Flash, unconfirmed): **the class of a receiver is the class of the value the receiver holds, and the builder answers it.** The builder knows the class of a name from the type the name is declared with, from the class a constructor call makes, and from the name a value was copied from. The name resolution is the step that resolves types, but it answers the types of declarations, not the class of a receiver in the middle of a body, and the builder is the step that reads the body. |
