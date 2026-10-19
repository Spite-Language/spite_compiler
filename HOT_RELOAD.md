# HOT_RELOAD

How the hot reload has to work in this compiler, and what can go wrong with it. Written for whoever picks
the work up: the mechanism is not hard, the rules around it are where the bugs live.

The reload is a *development* feature. A program built with it runs slower, because every call goes through
a slot a reload can re-point, so only a production build says anything about how fast a program is.

## What it is

Save a file of a running program, and the classes that file declares are compiled again, on their own, into
a small library the running program loads and swaps in. Objects, singletons and everything the REPL changed
stay as they were: only functions change.

The original compiler does this with C, and its numbers are in
`D:/Projects/SpiteLanguage/benchmarks/a_reload_compiles_only_the_classes_that_changed`:

| Step | The original |
|---|---|
| the whole build | 5.2 s |
| a reload of the unchanged files | 0.3 s |
| a reload after a function's body changed | 1.7 s |
| a reload after a class gained an attribute | 4.8 s (the whole program again) |

Most of that 1.7 s is one run of the C compiler, and the rest is reading and checking every class, the
library's included. This compiler has neither cost, so the target is a reload of a changed function in well
under a tenth of a second, and one with nothing changed in milliseconds. That target is why the caches are
per step and per unit, and why the machine code is cached per function: the reload writes the new bytes and
nothing else.

## The mechanism

Five parts. Each is a thing this compiler has to be able to do.

1. **One slot per function.** In a hot reload build every function is called through a slot the program can
   re-point: the program's own, the standard library's, and the helpers the compiler writes. The function the
   rest of the code calls is a one-line forwarder to its slot. A normal build is untouched: direct calls, and
   tree shaking.
   *For us:* the low representation's call is a direct call, so there is nowhere to put new code and a reload
   cannot swap a function at all. The low representation needs a call that goes through a slot, and the
   emitter needs the table of them. Only the builds that ask for it pay for it.
2. **A library, not an executable.** A reload writes `game_reload_1.dll` beside the executable, holding the
   changed classes' functions and whatever those need that the running program lacks, with the types and
   declarations they use. It also writes an `install` the running program calls to put the new code in the
   slots.
   *For us:* the generator writes one PE file today. It needs a second shape: the same emitter, a different
   file around it.
3. **The manifest.** The build writes what the running program holds beside the executable: every function
   with its prototype, its classes and their layouts, and the facts its code was compiled against. A reload
   starts from them, so it compiles the changed code against what the program is actually running, and not
   against a fresh reading of the program.
4. **The state.** The build writes a hash of each of the program's files, so a save that changed nothing is
   answered at once, and a save that changed something is known exactly.
5. **The baseline.** A reload that had to compile the whole program is the next one's baseline: after it,
   the facts, the hashes and the class ids describe the running program better than the build's do. A save
   after a change that compiled everything is fast again.

The running program's side is not ours: the standard library's `hot_reload.spite` watches the folders, spawns
the compiler, loads the library and calls `install`. What it needs from the compiler is the library, the
state and the answer.

## Who does what

| The step | Who |
|---|---|
| watch the program's folders, notice a save | the standard library's `hot_reload.spite` |
| run the compiler with the same options, as `reload` | the standard library's `hot_reload.spite`, through `Process` |
| compare the files with the state, answer `unchanged` | the compiler |
| compile the changed classes into a library, write the state | the compiler |
| load the library, install the new code in the slots | the running program, through the compiler's `install` |
| keep the objects, the singletons and the REPL's changes | the running program, untouched |

## What a reload may change

This is the language's rule, and the compiler enforces it. The table is the original's
(`D:/Projects/SpiteLanguage/docs/repl.md`, *What a reload can change*); ours is the same table.

| You change | What happens |
|---|---|
| a function's body | the next call runs the new body; a call already running finishes the old one |
| a new function on an existing class | the new code calls it, the REPL's `functions` lists it and the prompt can call it |
| a function's parameters or return type | it becomes a new function: the rebuilt class and every class that calls it are rebuilt too |
| a function you deleted | whatever still holds it (a function value, the REPL) keeps its last code; the answer says `removed Monster.roar` |
| an attribute's default value | instances made after the reload get the new default |
| a class's attributes: added, removed, renamed or retyped | every live object of the class moves to the new attributes, components in an `Items`' own memory too; the answer says what each class's objects kept |
| an enum's values: added, removed or reordered | the whole program is compiled again, and every value a running object holds keeps its meaning; a `switch` that meets a value the reload removed halts naming it |
| a file that does not compile | refused with the compiler's error, and the program keeps all of its code |
| a function of a class the program reopens, a class of the standard library or a number | the whole program is compiled again and every function whose code changed is swapped in, the standard library's and the compiler's helpers included |
| `environment.spite`: a setting added, removed or given a new default | the whole program is compiled again, `Environment` moves to its new attributes, and every setting is read again the way it is when the program starts |
| `build.spite`: a field added, removed or given a new default | the whole program is compiled again, and the program's code sees the new value |
| a file deleted | the program is compiled without it, as for any other change |
| a function, attribute or constructor that a later `load` reopens | the reload keeps load order, as a fresh start would: an edit to the earlier declaration changes nothing while the later one replaces it, an edit to the later one goes live, deleting the later one (or its file) brings the earlier one back |
| a new class | its functions are compiled into the new code, and `classes` and `describe` see it |

A refused reload leaves the program exactly as it was, so a save that caught a file half-written is harmless:
the next save reloads.

## The risks

These are the ways a reload goes wrong. Each one is a rule of the language, so each one is a case the compiler
has to decide, and each one has bitten the original at least once.

### The reopening

**The rule** (`D:/Projects/SpiteLanguage/specs/packages.md`): every loaded root merges into the same
namespaces, and a second root with the same folder structure and file name **reopens** the class. A later
`func` or `var` with the same name replaces the earlier one, in load order (the entry folder first, then the
loads in the order they were discovered), a `var`'s replacement type must match, and a new `func`, `var`,
`enum` or `type` not seen before is simply added. An `enum` declared again replaces the earlier declaration
whole: its values are the later list, in the later order, and a value only the earlier declaration listed is
not a value any more. A `--hot-reload` reload replaces it the same way.

**Why it is dangerous for a reload.** A reload is not a fresh start: the running program was built with one
set of declarations, and the reload must not quietly change a class under it. The cases:

- **The load order is the rule, and a reload keeps it.** An edit to the *earlier* declaration of a reopened
  name changes nothing, because the later declaration replaces it. An edit to the later one goes live. This
  surprises people: they edit the file they wrote first and nothing happens.
- **The standard library is discovered before the program**, so a program's own file reopens `Console`,
  `String`, `File` and the rest the same way. A reload of a program's file that reopens a library class is
  therefore a change to a class the whole program shares, and the original compiles the whole program again
  for it.
- **The compiler's own bodies are a reopening too.** The members whose bodies the compiler supplies
  (`Console`'s writing, `Memory.Heap`'s allocator, the dynamic library) are the compiler's own reopening of
  the library's classes. A reload that changed one of them would change every program, and the original
  refuses a change that reaches a helper with state of its own, because a new copy of it would start empty.
- **A `var`'s replacement type must match.** So a reload cannot change an attribute's type by reopening the
  class with a different type: it is an error, not a silent move.
- **The entry class is the one class nothing reopens.** A program file may not be a class of the entry class's
  name, and a file that reopens a class a loaded folder declares keeps every name the loaded folder lacks,
  but where both declare a name, the constructor included, the loaded folder's comes later and stays.
- **One package is one class.** A file outside a version that has the dotted name of one of its classes
  reopens the version it has pinned, so a reload of a package's file can change a class of a version.

**What the compiler must do.** A reload has to answer with the *merged* class, not with the file's own
declaration: the reopening rule is part of reading the program, so the merged class is what the manifest
holds, and a reload compares against that. A reload of a file that reopens a class another file reopens
needs the whole program compiled, and the compiler says why (`compiling the whole program, since outside
HotCounter changed`).

### The layout

**The rule.** A class's attributes are laid out in the object, and the layout is the compiler's decision
(`D:/Projects/SpiteLanguage/specs/memory.md`). A reload that adds, removes, renames or retypes an attribute
changes the layout, and every live object of the class has to move to the new attributes.

**Why it is dangerous.** The running program holds objects. A reload that moved them wrongly loses their
values, their identity, or both. And a class's layout is depended on by other classes compiled against it,
so a change reaches further than the class that changed.

**What the compiler must do.** The layout is decided once, by the build, and kept: a reload reuses the layout
the running program was built with, and a change that would move an object is either refused or paid for in
full (the original's 4.8 s row: the whole program again). The layout is part of the manifest, and the
compiler-supplied helpers that read a class's attributes (its allocation, release and copy, the reflection,
a union's dispatch, a template made for it) are called through slots too, so they move with the class.

### The prototype

**The rule.** A function's parameters and its result are part of its identity: a change to them makes it a
new function.

**Why it is dangerous.** The running program calls the old one. The new one has a different shape, so every
caller compiled against the old one is stale, and a function value held anywhere keeps the old code.

**What the compiler must do.** A changed parameter list is a fact that changed, so the whole program is
compiled again, and the answer says so.

### The facts

**The rule.** Compiling one class depends on the rest: which functions can wait, which classes fit a shape,
which attributes something reads, the call effects that decide whether a borrowed value must be counted, how a
dictionary is keyed, which functions the program made for a class (a setter, a template instance, a
`to_debug`).

**Why it is dangerous.** These are the assumptions the running code was compiled against. If a reload changes
one of them, code in other classes is stale, and nothing in the running program says so.

**What the compiler must do.** The build records them in the manifest, a reload starts from them, and a
change to one of them compiles the whole program instead, and says which fact changed. This is the part
that is easiest to get wrong and hardest to see: a fact the compiler does not record is a fact a reload will
silently get wrong.

### The state a helper keeps

**The rule.** A helper the compiler writes that keeps state of its own (a singleton's cache, a table the
program fills as it runs) has no slot, because a new copy of it would start empty.

**Why it is dangerous.** Swapping it in would silently empty a cache the program is using.

**What the compiler must do.** A change that reaches such a helper refuses the reload, and says what to do
instead: `the change reaches '<name>', which the running program cannot swap: restart the program to take
the change, or undo it`.

### The concurrency

**The rule.** A `Concurrent` that is stopped at a wait holds the state it had.

**Why it is dangerous.** A swap while a task is stopped at a wait would leave that task running code that is
half old and half new.

**What the compiler must do.** The swap waits for the task to return, and the answer says it is waiting:
`the reload waits for '<name>', where a Concurrent is stopped at a wait, and is swapped in once it returns`.

### The reflection and the registries

**The rule.** The reflection's tables of classes, singletons and enums are part of the program's code.

**Why it is dangerous.** A new class, or a class that gained a function, is not in the running program's
tables, so the REPL would not see it and a `switch` over an enum would not know its values.

**What the compiler must do.** The tables are swapped in with the code, and an enum whose values changed
compiles the whole program, because a value a running object holds must keep its meaning.

### The generics

**The rule.** A generic class is a template, and every use of it with a type mints an instance
(`List<Integer>` is `List_of_Integer`). Each instance is a class of its own, with its own layout.

**Why it is dangerous.** A change to the template changes every instance of it, and the running program holds
objects of every instance.

**What the compiler must do.** A change to a generic class is a change to every instance of it, so it is a
change to the facts, so the whole program is compiled again.

### The file that does not compile

**The rule.** A refused reload leaves the program exactly as it was.

**Why it is dangerous.** A save that caught a file half-written is the common case, not the rare one.

**What the compiler must do.** A reload that does not compile is refused with the compiler's error, the
program keeps all of its code, and the answer says so. The compiler's error must be the same one a full
build would give, or the reload is answering a different question than the build.

### One reload at a time

**The rule.** A reload compares with the files and the baseline of the code the program will run, which
swapping a library in writes.

**Why it is dangerous.** Two reloads at once compare against the same baseline and write the same files, and
one of them swaps in code the other did not compile against.

**What the compiler must do.** The state and the baseline are written atomically enough that a reload never
reads a half-written one, and the running program waits for the swap before it compiles the next one.

## What we have to build, in the order

1. **The slots.** The low representation's call goes through a slot in a development build, and the emitter
   writes the table. Without this there is no reload at all.
2. **The caches.** Per step and per unit, keyed by the hash of what went in, on disk and in one binary
   format, and in memory for the compiler that is running. The machine code is cached per function: that is
   the biggest win, because the original pays for a C compiler run and we pay for nothing.
3. **The manifest and the state.** What the running program holds (the prototypes, the layouts, the facts) and
   the hashes of the files, written beside the executable, and read by the next reload.
4. **The reload mode.** The compiler is given the running executable, it reads what the last build recorded,
   it compiles what changed, and it writes the library and the state, or answers that nothing changed.
5. **The library and the install.** The generator writes a second shape of file, with the same layout, and
   the `install` the running program calls.
6. **The decisions.** Which changes are cheap (a body), which are dear (the layout, the prototype, the facts,
   a reopened library class) and which are refused (a helper with state of its own). Each one is a fact the
   compiler records, and the answer says which one changed.
7. **The measurement.** A benchmark of the reload beside the original's, so the claim is a number.

## What is not a lock-out

The rest of the plan can be done in any order: the language, the memory model, the proofs, the errors and the
outputs all stand on their own. The optimisation passes come last, and they are per function, so a reload's
optimisation of the changed class does not change the others.

The one thing to keep in mind while the rest is built: the layout, the facts and the slots are decided by
the compiler, and every one of them is recorded in the manifest. A fact the compiler does not record is a
fact a reload will silently get wrong, so each new fact has to be written down as it is decided.
