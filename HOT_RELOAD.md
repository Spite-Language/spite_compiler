# Hot reload

Save a file of a running program: its classes are compiled again into a small library, and the running program
loads it and swaps the new functions in. Objects and singletons stay. What a reload may change is the language's
rule, in [`repl.md`](https://github.com/Spite-Language/spite_documentation/blob/master/repl.md) ("What a reload can change").

Target: a changed function reloads in well under 0.1 s (the original: 1.7 s, most of it a C compiler run).

## The parts

1. **Slots.** In a `--hot-reload` build every call goes through a slot the program can re-point. Other builds
   call directly and pay nothing.
2. **A library beside the executable**, with the changed functions and an `install` that fills their slots. Same
   emitter, a different file around it.
3. **The manifest**: every function's prototype, every class's layout, and every fact the code was compiled
   against (which functions wait, which classes fit a shape, the call effects). A reload compiles against it.
4. **The state**: a hash of each file, so a save that changed nothing is answered at once.
5. **Caches per step and per unit**, keyed by the hash of their input, on disk. Machine code is cached per
   function.

## A reload compiles the whole program when

- a function's parameters or result change (it is a new function, and its callers are stale);
- a class's layout changes (live objects move to the new attributes);
- a recorded fact changes, a generic class changes, or an enum's values change;
- a class the standard library declares, or that another file reopens, changes.

The answer says which of these happened. A fact the compiler does not record is a fact a reload gets wrong
silently, so every new fact goes into the manifest when it is decided.

## A reload is refused when

- the file does not compile (with the same error a full build gives), and the program keeps all its code;
- the change reaches a helper that keeps state of its own, which a new copy would empty.

## Rules

- Load order holds: editing a declaration that a later file replaces changes nothing.
- A `Concurrent` stopped at a wait finishes on the old code; the swap waits for it.
- The reflection tables are swapped with the code.
- One reload at a time: the state is never read half-written.

## The manifest is the reflection model (proposed by Claude, unconfirmed)

The classes a program reflects over (`Spite.Class`, its attributes and functions) are the description of the
program the compiler already builds. A reload compares the new program's description with the running one's
instead of keeping a second, parallel manifest: a changed layout is a changed `Spite.Class`, a changed signature
a changed function of it. To decide when reflection is built: whether those classes can carry what a reload
needs (layouts, recorded facts, slots) without a program that never reloads paying for it.
