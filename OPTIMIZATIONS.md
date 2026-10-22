# Optimisations

What the compiler does on its own to make a program faster or smaller, worked out while compiling. Each section
says what the optimisation does, when it applies, when it does not, what a program can observe of it, and shows a
small program. None of them changes what a program prints, returns or crashes with: only its time and its memory.

## A function does not count its own parameters

A function's parameters are held by its caller for the whole call, so the function does not count them: it reads
them as they are and lets nothing go when it returns. The caller holds what it passes: a name of its own (a local
or a parameter), `this`, a singleton, or an object it has just made and lets go after the call.

**When it applies:** to every parameter the function never assigns. A function that writes `parameter = other`
counts that parameter, since the assignment lets go of what it held. A function that runs as a step of a
`Concurrent` work (one that can wait) counts its parameters too, since its frame outlives the call that started it.

**What the caller counts instead:** an argument or a receiver read from a place the call may assign (an attribute
the callee, or anything it calls, writes; a list slot; a back reference; the answer of a wait) is counted by the
caller before the call and let go after it, so the call cannot free it under the callee
([An attribute a call cannot assign is passed without counting](#an-attribute-a-call-cannot-assign-is-passed-without-counting)).

**What a program can observe:** nothing but time. `drop()` runs at the same moment as before, since the count a
call made was never the last one.

```spite
func Naive() {
    var rows = List<Integer>()
    rows.append(3)
    var total = first_of(rows, 0)
}

func first_of(rows: List<Integer>, at: Integer): Integer {
    return second_of(rows, at)
}

func second_of(rows: List<Integer>, at: Integer): Integer {
    var found = rows[at]
    crash found
    return found
}
```

Neither `first_of` nor `second_of` counts `rows`: `Naive` holds it in a local for both calls.

## An attribute a call cannot assign is passed without counting

An argument or a receiver that is an attribute, or a path of attributes (`settings.limits`), is passed as it is
when nothing the call can run assigns any attribute along the path: the object that holds it holds it for the whole
call. The compiler works out, for every function, the attributes it assigns and the functions it calls, and follows
the calls to the end, so the question is answered for everything the call can reach.

**When it does not apply:** when the call, or anything it reaches, assigns an attribute on the path, assigns one
of that name through a shape, calls a function value whose function may (any function the program takes as a value
counts), runs a `drop()` that may (a `drop()` can run wherever a count is let go, so every `drop()` counts), waits
(`Program.sleep`, a join, a blocking read, where other work runs), or hands a function to C that may call it back.
Then the caller counts the argument for the call. A path through a back reference is always counted.

**What a program can observe:** nothing but time.

```spite
var readings = List<Integer>()
var settings = Settings()

func measure(at: Integer): Integer {
    return reading_at(readings, at) + offset_of(settings.limits)
}
```

`reading_at` and `offset_of` assign neither `readings`, `settings` nor `Settings.limits`, so both are passed
uncounted. Ten million calls of `measure` went from 0.35 s to 0.22 s.

## A name holding an item or an attribute is not counted

`var held = this.part`, or a list's own `var held = _read_value(index)`, does not count `held` when nothing after
it in its block can write the slot it came from: no assignment of an attribute on its path and no call that may
write one, no write into a list of that class (`_write_value`, `_forget_value`) and no call that may make one. The
name is then read as it is and let go of nothing when its block ends. This is what makes a list's templates
(`contains`, `index_of`, `join`, `copy`, and the others handed a function that cannot write the list) read their
items without counting them.

**When it does not apply:** when the name is assigned again anywhere in the function, when what it came from is
itself a name that is assigned again, when anything after it in the block may write the slot (by the same rules as
the [attribute passed to a call](#an-attribute-a-call-cannot-assign-is-passed-without-counting)), or in a step of a
`Concurrent` work. Then the name counts what it holds.

**What a program can observe:** nothing but time.

```spite
func contains(value: $element_type): Boolean {
    var index = 0
    while index < _length {
        var held = _read_value(index)
        if held == value {
            return true
        }
        index = index + 1
    }
    return false
}
```

## Storing an object into a list counts it only when it changes the slot

Writing an object into a list's slot compares it with what the slot holds. When it is the same object, nothing is
counted and nothing is written; otherwise the new object is counted and the old one let go, as before.

**When it applies:** to every write of an object, a union, a shape or a function value into a `List`, a
`Vector` or an `Items` slot.

**What a program can observe:** nothing but time.

```spite
var held = names[at]
crash held
names[at] = held
```

Ten million such write-backs went from 0.36 s to 0.23 s.

## Defaults the constructor replaces are never made

`var values = List<Integer>()` written beside a constructor that sets `values = List<Integer>()` itself made the
default list and freed it at once. A constructor that assigns an attribute before anything can read it makes its
objects with a copy of the class's defaults that leaves that attribute out, so the default is never made.

**When it applies:** to an attribute the constructor assigns in its own body, outside any `if` or loop, before
any statement that reads it or that names `this` other than to assign or read an attribute (a call on `this`, or
`this` passed on). The default left out must be quiet: a constant, a text, or an object whose making assigns only
its own attributes from quiet values, calls nothing the compiler cannot see the end of, cannot stop the program
(a check on its arguments that the constants given to it decide is followed), and whose class has no `drop()`. A
class whose defaults name `this`, or read another attribute, is made from all of its defaults.

**What a program can observe:** fewer allocations. A default left out is not made, so nothing it would have made
is ever counted, dropped or freed.

```spite
var values = List<Integer>()
var label = "none"

func Holder(start: Integer) {
    values = List<Integer>()
    values.append(start)
    label = "made"
}
```

`Holder(start)` makes neither the default list nor the default text. Three million holders went from 3.1 s to
1.5 s.


## Arithmetic a range proves is not checked

A `+`, `-` or `*` on whole numbers halts when its answer does not fit its type. Where the compiler proves while
compiling that it always fits, the check is left out and the operation is one machine instruction. The proof is a
range for each operand (`high_intermediary_representation/building/ranges.spite`), the rule of
`../SpiteLanguage/specs/values_and_types.md#a-range-proves-a-check-unneeded`:

- a literal is its own range; a local or a parameter of a whole-number type of at most four bytes has its type's
  range until a `var` or an assignment gives it its value's; a `Long` has no range until one is given to it;
- `count()` of a library `List`, `Dictionary`, `Vector` or `Items`, and `length()` of a `String`, run from 0 to
  2147483647; `x % n`, `x / n`, `minimum`, `maximum`, `clamp`, `to_long` and `to_integer` are bound by their
  operands;
- a comparison narrows the local it compares inside a `while` or an `if` whose condition says so, on each side of an
  `and`, after an `assert` or a `crash` of it, and after an `if` that leaves; `counter + c < bound` narrows `counter`
  by `bound - c` too;
- the two branches of an `if` join, and before a `while` every local its body assigns takes its type's range, except
  a counter only ever stepped up by constants: it keeps the floor it entered with and, under `counter < bound` with
  no step in a nested loop, at most the bound's largest value plus its steps.

```
func total(values: List<Integer>): Long {
    var sum: Long = 0
    var index = 0
    while index < values.count() {
        sum = sum + values[index]
        index = index + 1
    }
    return sum
}
```

`index + 1` is written unchecked: `index` runs from 0 to 2147483646 under the loop's condition. `sum + values[index]`
keeps its check, since `sum` is a `Long` that grows every pass.

When it does not apply: an operand that is an attribute, a list item or a call's answer has its type's range, so an
operation on two of them keeps its check. A `--repl`, `--repl-port` or `--hot-reload` build proves no ranges, since
code may run between two steps. What a user can observe: `--optimization-report` lists every check kept, under
"Overflow checks kept", with the ranges that did not prove it.

## A proven read tests only its bounds

`values[index]` where a bound proves the read (`while index < values.count()`) is a call to the list's `get_at`, which
answers a `T?`, and a test that halts when the answer is missing. For a library `List` whose items are not `T?`
(numbers, `Boolean`, objects), the compiler writes the read in place instead: one unsigned comparison of the index
with the list's length, which halts the same way when the index is below 0 or the list changed, one load of the
item, and for an object the count the call's answer would have taken. `count()` of a library `List`, `Vector` or
`Items`, and `length()` of a `String`, is one load of its length.

```
func rises(values: List<Integer>, threshold: Integer): Integer {
    var count = 0
    var index = 1
    while index < values.count() {
        if values[index] - values[index - 1] > threshold {
            count = count + 1
        }
        index = index + 1
    }
    return count
}
```

The loop calls nothing: `values.count()` is a load, and each read is a comparison and a load.

When it does not apply: a list of `T?` items, of unions or of function values still calls `get_at`; a `List` whose `get_at` or `count` a program replaces by reopening the class calls the
replacement. What a user can observe: nothing but the time; the message of a read outside its list is the same.

## Text joined in one piece

`"{first} meets {second} at the gate."` is one join, not a chain of pairs. The compiler works out every piece
first, left to right as written, adds up their lengths (a written piece's length is known while compiling, a
hole's is read from its text, a number's is counted), makes the text once with exactly that room, and copies each
piece's bytes into it with one block copy (`copy r<n> bytes from r<a> to r<b>` in `--low-ir`, a `rep movsb` in the
machine code). A written piece is copied straight from the executable's data, with no text made for it; a hole's
text is let go once the join is written. A hole's text the join only borrows (an attribute's, a singleton's) is
counted until the join is written when a later piece calls a function, since that call may let it go
(`"{name} then {rename()}"`). A chain of pairs would make a whole new text at every piece and copy
everything joined so far into it.

```
func greeting(first: String, second: String): String {
    return "{first} meets {second} at the gate."
}
```

The same code writes a written text on its own (`"gold"` is one allocation and one copy) and an
[append in place](#text-appended-to-itself-grows-in-place).

When it does not apply: a join written as calls (`first.sum(second)`) is a call, and a program that replaces
`String.sum` by reopening `String` keeps calling its own. What a user can observe: one allocation for the whole
join, and the time.

## A number joined into text is written in place

`"line {index} of {round};"` reads as turning each number into a text and joining the pieces. Inside a join, an
`Integer` or a `Long` piece is written as digits straight into the text being joined: the compiler counts the
digits (and the `-`) before the text is made, so they are part of its one room, and then writes them from the
last, so no text is made for the number.

```
func label(index: Integer, round: Integer): String {
    return "line {index} of {round};"
}
```

The digits are the ones the library's `to_string()` writes: a `-` for a number below 0, and `0` for zero. It
applies inside an [append in place](#text-appended-to-itself-grows-in-place) too (`log = "{log}{index},"`). When it
does not apply: a number that is the whole text (`"{index}"`), which calls `to_string()`, a number of another type,
and a program that replaces `Integer.to_string()` or `Long.to_string()` by reopening the class, which keeps calling
its own. What a user can observe: fewer texts made, and the time.

## Text appended to itself grows in place

`built = "{built}item {index},"`, `text = text + piece` and `joined = joined.sum(separator)` name the text they
assign on their left. When the text is held only by that name (its count is 1 when the line runs), the pieces are
appended to it where it is, with the [one-piece join](#text-joined-in-one-piece)'s code: their lengths are added,
the room is grown once if they do not fit (at least doubled, so a loop of appends copies each byte a constant
number of times), and the bytes are copied in. When something else holds the text too, it is copied first, with
twice its length as room, and the name is given the copy, so what the other holder sees never changes.

```
func words(count: Integer): String {
    var text = ""
    var index = 0
    while index < count {
        text = "{text}word {index} "
        index = index + 1
    }
    return text
}
```

When it does not apply: a piece that names the text itself (`text = "{text}{text}"`), which is an ordinary join, a
`String?` or a symbol, and an assignment to an attribute or a list slot. What a user can observe: the time, and
the text's room, which can be up to twice its length.

## Short text lives inside its `String`

A `String` is a 32-byte object that holds its length and a `Buffer` of its bytes, and a `Buffer` holds a pointer
to its storage. Every text is one allocation: the `String`, then its `Buffer`, then the bytes. A written text, a
join and an append's first text get room for 47 bytes or for the whole text if that is longer; a `String()` (what
`slice`, `split`, a number's `to_string()` and the rest of the library start from) gets the room its default
`Buffer(16)` asks for, at least 47 bytes. Every other `Buffer` (one `Buffer(n)` makes) has room for 47 bytes inside
itself too, so a short buffer is one allocation and not two. When the bytes outgrow the room, they move to storage
of their own, and the room inside is not used again.

```
func labels(count: Integer): List<String> {
    var made = List<String>()
    var index = 0
    while index < count {
        made.append("r{index} of {count}")
        index = index + 1
    }
    return made
}
```

Each label is one allocation of 32 + 48 + 48 bytes and one free. The `String` and its `Buffer` mark in their own
padding (the unused upper bytes of the 32-bit length and count slots) that they were made together. Freeing the
`String` frees the block; when something still holds the `Buffer` (a program that reopens `String` and hands
`_buffer` out), the block stays until that holder lets the `Buffer` go, and that release frees it.

When it does not apply: a program whose `String` keeps an attribute other than `_buffer` and `_length` in its
objects, or whose `String` or `Buffer` has a `drop()` or is held back by a cycle, makes the `String` and its
`Buffer` apart (still with the room inside the `Buffer`), and so does a `String()` whose reopened defaults are
anything but `_buffer = Buffer(n)` with a number written out and `_length = 0`. What a user can observe: one allocation per text, 48
more bytes per `Buffer`, and the time.

## Bytes are copied in one block

The library's text and bytes functions copy runs of bytes with `Buffer._copy_bytes(at, source, source_at,
wanted)`, a function with no body that the compiler writes as one block copy: `rep movsb`, or, when the two runs
overlap with the target after the source, the same copy run backwards. `String`'s `_append_text`, `slice`, `sum`,
`replace`, `split`, `trim`, `to_bytes`, `upper_case` and `lower_case`, and `Buffer`'s `append_bytes`, `copy`,
`read_bytes` and `text` are each one copy per run instead of a call per byte. `equals`, `starts_with`, `ends_with`,
`contains`, `index_of`, `split` and `replace` compare eight bytes at a time (one 64-bit load from each side), and
look for a match only where the first byte matches. A number's `to_string()` counts its digits, makes room once
and writes them from the last, into the text it answers.

```
func shout(line: String): String {
    var words = line.split(" ")
    var joined = words.join("! ")
    return joined.upper_case()
}
```

When it applies: every call of these functions. What a user can observe: the time.

## A number's own value is its register

Inside a number's class, `_value()` reads the number from the `Buffer` the class declares as `_buffer`. The
compiler writes a read at 0 of the number's own type from that room as the number itself, with no `Buffer` made,
so `index.to_string()`, `count.to_long()` and the rest of the numbers' functions cost no allocation. A read of
another type or offset (a number's bytes) still makes the room, and lets it go once read.

```
func digits(count: Integer): String {
    return count.to_string()
}
```

What a user can observe: no allocation for `_value()`, and the time.

## Letting go of an object of a known class is direct

Letting go of an object whose class is not known while compiling calls `_release`, which counts down and, at
zero, finds the object's free function from its class number by a binary search (a few compares, not one per
class). Where the class is known (an attribute or a list's item whose declared type is a class of the program or
the library), the count is taken down in place and the class's free function is called directly, with no search.
A `Spite` class (`Spite.Function`, which holds a function value of another class) is let go through `_release`.

```
func Lists() {
    var names = List<String>()
    names.append("ada")
}
```

Freeing `names` takes each text's count down in place and calls `_free_String` for the ones that reach 0. What a
user can observe: the time.

## Small blocks come from the compiler's own free lists

Every object, list storage, text and task frame used to be one `HeapAlloc` and one `HeapFree` (about 60 ns each on
Mortaro's machine). The generator now writes its own allocator into every program that allocates
(`generators/windows_x64/small_blocks.spite`): a block of up to 1016 bytes takes one of 64 size classes, 16 bytes
apart, and comes from that class's free list; a class whose list is empty carves blocks from a 64 KiB chunk taken
from the system heap, and a freed block goes back on its class's list. Larger blocks are the system heap's, as
before. Each block carries 8 bytes in front of it: its class and whether it is live or free, and in a program with
threads the number of the thread that owns it.

- **The size class is worked out while compiling.** An allocation whose size is a constant (every object, every
  box, every frame) of up to 120 bytes is written in place in a program without threads: a load of its class's list
  head, a test, two moves to unlink the block, its tag, and the stores that clear it, with a call to the shared
  routine only when the list is empty. A size known only at run time, and every allocation in a program with
  threads, calls the shared routine, which works the class out from the size.
- **Freeing is a few instructions in place**: the block's tag gives its class, the block is marked free and pushed
  on its list. A block of the system heap goes back to it.
- **Threads**: in a program with threads every thread keeps its own lists in a block of its own, found through a
  thread slot read straight from the thread's own block (`gs:[0x1480]`), so no allocation takes a lock. A block
  freed on another thread than its owner's is pushed with one compare-exchange onto the owner's returned list,
  which the owner takes back whole, with one exchange, when its own list for a class runs dry. When a thread a
  `Parallel` started finishes, its lists are kept for the next thread that starts, so starting threads again and
  again does not grow the memory.
- **Nothing is silent**: memory is cleared as `HeapAlloc` cleared it (a grown block's new bytes are 0), freeing
  memory twice stops with `the program freed the same memory twice`, freeing or resizing a pointer the allocator
  never handed out stops with `the program freed memory it never allocated` (or `resized`), a size past 2^40 bytes
  stops with `the program ran out of memory`, and so does a failed chunk.

**When it does not apply:** a program that allocates nothing carries none of it; blocks above 1016 bytes are the
system heap's; in a program with threads every allocation and free is a call (no inline fast path yet).

**What a user can observe:** only the time and the memory. Memory freed into a class stays with that class and
with the program: chunks are never given back to the system, so a program's peak of small blocks of one size is
what it keeps. A pointer the program frees and then uses is reused sooner than the system heap reused it, so a
fault of the compiler that reads freed memory shows at once instead of by luck.

```
var count = 0

func Points() {
    var index = 0
    while index < 1000000 {
        var point = Point(index, index)
        count = count + point.x
        index = index + 1
    }
}
```

Each `Point` (two `Integer`s) is its size class's list head popped and pushed back, with no call into the system; measured on
the cases in the report (`objects_that_never_leave_their_function_live_in_the_frame`, `report_over_records`, ...).

## Maths on constants is worked out while compiling

A `+`, `-` or `*` on whole numbers whose operands' ranges are each one value, read from constants, locals and other
such operations, is worked out while compiling and written as its answer. A local given a constant is a constant
where it is read, until something assigns it again (the ranges of
[Arithmetic a range proves is not checked](#arithmetic-a-range-proves-is-not-checked)).

```
func area(): Integer {
    var width = 12
    var height = width * 3
    return width * height + 4
}
```

`area` returns 436 with no arithmetic left. When it does not apply: an answer that does not fit its type keeps the
operation, which halts as it would have. A division, a call and a decimal are left to the lowered program, where
[calls on constants are run while compiling](#calls-on-constants-are-run-while-compiling). What a user can
observe: nothing but the time.
Every optimisation the compiler makes, one section each: what it does, when it applies, when it does not, what a
user can observe, and a small program that shows it. None of them changes what a program prints, returns or
crashes with; they change only its time and its memory.

## Layouts by use (the design)

A class is one class to the program and several layouts to the compiler. The program sees `Player` with its forty
attributes; the compiler sees only what the program does with them, and lays out each object with what its uses
need, so an attribute a use never touches costs it no memory, no default and no release. Attributes that the
uses read together, across classes, sit together in one block that every class lays out the same way, so code
that reads them walks one dense layout whatever the class. The goal of every choice below is the least memory
for what is not needed and data laid out for the CPU cache: dense, aligned, read in order.

Everything here is decided while compiling. A program that has no class to shrink carries nothing of it: no
table, no tag, no check.

### What a use is

The compiler builds the high representation as a worklist, so when it is quiet every function the program can
reach is built and nothing else. A **use** of an attribute is anything in a built function that reads or writes
it:

- an attribute read or write in the program's code;
- a read or write through a union (`shape.name` reads `name` of every class that fills the union);
- the functions the compiler writes for the program: `to_debug()`, `deep_copy()`, the JSON and binary readers and
  writers, reflection walks (`Class.attributes.each(...)`) and templates over attributes. They are built like any
  other function, so their reads count;
- the attributes the generated machine code reads by name (a list's `_buffer` and `_length`, a library's
  `handle`, a callback's `address`, `context`, `_function` and `_cell`, a buffer's `item_count`): these always
  keep their place.

An attribute's default, in the class's `_attribute_defaults`, is not a use: it is what a use would find.

### The steps

1. **Uses per attribute.** One walk over every built function records, per attribute (`Class.name`), whether it is
   written, and every read with where it stands: the receiver of a call, the value of a local, or anywhere else.
   Reads and writes through a union record the union member too.
2. **Untouched attributes have no slot.** An attribute no use touches, whose default is pure (literals, and the
   constructors and functions of the library's collections and texts), gets no slot, and its default is not run.
   Nothing releases it, because nothing was ever stored.
3. **Attributes nothing writes are rebuilt where read.** An attribute that no use writes always holds what its
   default made. When that default is pure and reads nothing of the object, and every read stands where the
   value cannot be changed or kept (a scalar or an enum anywhere; an object only as the receiver of a call that
   does not change its receiver and does not answer it, or as the value of a local used only that way), the
   attribute gets no slot and each read builds the default in place: a number is a constant, a table is built
   where it is looked up. An object that never reads the attribute pays nothing for it.
4. **Shared blocks.** For each union, the members read or written through it that every class filling it holds
   as an attribute of the same type form a block. The compiler places that block at the same offsets in every
   filling class, right after the header, so a read through the union is one load, with no test of the class.
   A class that fills two unions takes the first union's block first and places the second's members at offsets
   free in every filler, or, when no offset is free in all of them, keeps the test of the class for that member.
5. **Dense, aligned slots.** The rest of each class is packed by size: 8 bytes (references, enums, `Long`,
   `Double`), then 4 (`Integer`, `Float`), 2 and 1 (`Boolean`, `Byte`, and the presence byte of a `T?` number),
   each at its natural alignment, so nothing pads and a `Boolean` costs one byte, not eight. Within a size the
   declared order holds, so attributes declared together and read together stay on one cache line.

### Per allocation site (the next step)

The steps above decide one layout per class from the whole program. The full design decides one layout per
**set of objects** that meet: the compiler follows each `Player(...)` it builds to every place the object can
reach (locals, parameters, attributes, lists, unions) and records the attributes read and written there. Sites
whose objects never meet another site's are laid out on their own: a `Monster` made by the level loader that only
the renderer reads carries only what the renderer reads. Where objects of two sites meet (one list, one
parameter, one attribute), the compiler either merges their layouts into the union of both, or compiles the code
past the meeting point once per layout. It chooses by cost: the bytes each object would carry for nothing, times
the objects the site makes in a loop, against the size of the code it would copy. A meeting point reached
through reflection or a function value merges, because its code cannot be copied per layout.

### Objects of one class sit together

Every object today is its own allocation. The layouts decide each class's size while compiling, so objects of
one class made in a loop can come from one run of memory for that class, freed objects of the class reused
first, so a walk over them reads memory in order. A class made at one site and never kept past its loop is a
run the loop owns.

### An `Items`' storage is chosen while compiling

An `Items<T>` holds its items in a block, and the layouts decide the block: the attributes of `T` every use of the
`Items` reads are stored item after item (an array of structures) when the uses read most of each item's
attributes together, and attribute after attribute (one array per attribute) when each walk reads one or two of
them, as an entity system's systems do. The program's code is the same either way.

### What a user can observe

Only memory and time: an object is smaller, and a read through a union takes one load. Reflection still lists
every declared attribute, because it lists the declaration, not the slots. A program built for the REPL, with
hot reload or with `--development` keeps every attribute of its own classes in its declared place, because code
added later may read any of them; only `String` is shrunk there too (see the section on `String`'s words below).

## Untouched attributes have no slot

An attribute that no built function reads or writes, whose default is pure, takes no slot in its object, its
default is not run when the object is made, and nothing releases it. A pure default is made of literals, locals
the default itself declares, and the constructors and functions of `List`, `Dictionary`, `String` and `Buffer`;
a default that calls anything else (a constructor that prints, a function that counts) keeps its slot, so it
still runs once per object.

It applies to the library's classes and to attributes read only from functions the program never reaches: the
program's own attributes must be read somewhere, or the compiler refuses them as never read.

```spite
var console = Console()

func Inventory() {
    load "../../../SpiteCompiler/.spite/library/common"
    load "../../../SpiteCompiler/.spite/library/windows"
    var name = "sword"
    console.print(name.length())
}
```

`String` holds the inflection tables (`irregulars`, `uncountables`) beside its buffer and length. This program
never pluralizes, so no text carries them: a text is 32 bytes, its buffer and its length, and making one runs only
those two defaults.

## Attributes nothing writes are rebuilt where read

An attribute that no built function writes always holds what its default made, so the compiler gives it no slot
and makes the default where the attribute is read, when that cannot be told apart:

- a number, a `Boolean` or an enum: the read is the default itself, a constant when the default is one literal,
  or a call that computes it;
- a text: the read builds the text, unless it is read inside a loop;
- any other object: only when every read is the receiver of a call that does not change its receiver and does
  not answer it (the facts the compiler keeps on every function say which), or is the value of a local used only
  that way, and none of those reads is inside a loop.

It never applies to an attribute written anywhere outside its default, read through a union, read from an
object the read computes (`maker().items`), or whose default is not pure. A singleton's and the entry class's
object attributes keep their slots, because there is one object, so a slot costs once and a rebuild costs at
every read. A table rebuilt where read is built at each read: a function that reads it, called from a loop,
builds it on every call.

```spite
var name = "slime"
var health = 100
var attack = 9
var loot = List<String>()

func describe(): String {
    var carried = loot.count()
    return "{name} {health} {attack} {carried}"
}
```

If nothing writes `name`, `attack` or `loot`, a monster holds only `health`: `attack` reads as the constant 9,
`name` is built where `describe()` reads it, and `loot.count()` counts an empty list made in place.

## Dense, aligned slots

Each class's remaining attributes are packed by size, 8 bytes first (references, enums, `Long`, `Double`), then
4 (`Integer`, `Float`), 2 and 1 (`Boolean`, `Byte`, `Tiny`), each at its natural alignment; the presence of a
`T?` number is one byte, and the object rounds up to 8 bytes. Within one size the declared order holds. A class
whose layout the generated code knows by offset keeps its declared layout: `Buffer`, `ForeignCallback`, the
number classes and the compiler's own `Spite.` classes.

```spite
var alive = true
var health = 100
var flying = false
var target: Monster? = null
```

Declared order would take 8 bytes a slot, 32 after the header; packed, `target` takes 8, `health` 4 and the two
`Boolean`s one each, 16 after the header.

## Attributes read together through a union share one block

When code reads or writes a member through a union (`fighter.attack`, `fighter: Combatant` where `Combatant` is
`Player` or `Monster`), and every class of the union holds that member as an attribute of the same type, the
compiler places it at the same offset in every one of them, before anything else is packed. The read is then one
load, with no test of the object's class. The members a program reads together through one union end up side by
side in every class, one dense block, as an `attacker` would be.

It does not apply to a member some class of the union answers with a function, to a `T?` number, to a back
reference, or when the classes cannot agree on a free offset because another union already placed the member
elsewhere in one of them: that member is read by testing the class, as before.

```spite
union Combatant {
    Player
    Monster
}

func hits(fighter: Combatant): Integer {
    return fighter.attack - fighter.defense
}
```

`attack` and `defense` sit at the same two offsets in `Player` and `Monster`, so `hits` reads two numbers and
never asks which class it was given.

## `String`'s words cost a text nothing

`String`'s irregular and uncountable words are its attributes `irregulars` and `uncountables`, and a program
changes them by reopening `String` and declaring the attribute again. Every text is a `String`, so the compiler
never stores them, or any other attribute of `String` but its buffer and its length, in a text: one no use reads
is left out, and one that is read is rebuilt wherever it is read, as the receiver of a call, in a reflection walk,
through a union or in a loop. A text is 32 bytes whether the program inflects words or not, and `pluralize()`
builds the table once per word it inflects, as a function answering the table would. Each read answers a table
of its own, so changing the table a read answered changes only that copy. A program that writes one of them,
or whose reopened default is more than literals, is refused, because each text would then carry the tables and
making the tables makes texts:

    the attribute 'irregulars' of String would be made with every text, and its default makes texts, so making a
    text would never end: never write it, and make its default only of literals, so the compiler rebuilds it
    where it is read

## What runs after lowering

These run in this order on the low representation, then in the x64 generator:

1. [inlining](#small-functions-are-inlined) (`low_optimization_passes/inlining`), over the whole program;
2. [running calls on constants](#calls-on-constants-are-run-while-compiling)
   (`low_optimization_passes/compile_time_evaluation`), over the whole program;
3. per function, [object placement](#objects-that-never-leave-their-function-live-in-registers-or-the-frame)
   (`object_placement`);
4. per function: [constant folding](#maths-left-on-constants-after-lowering-is-worked-out-too) (`constant_folding`),
   [jump threading](#jumps-to-jumps-go-straight-to-the-end) (`jump_threading`),
   [copy propagation](#a-copy-of-a-value-that-never-changes-is-the-value) (`copy_propagation`),
   [dead code](#a-value-nobody-reads-is-not-computed) (`dead_code`),
   [common subexpressions](#the-same-computation-in-a-block-is-made-once) (`common_subexpressions`), copy propagation
   again, [remainder tests](#a-remainder-by-a-power-of-two-tested-against-zero-is-a-mask) (`remainder_tests`),
   [loop invariants](#what-a-loop-does-not-change-is-computed-before-it) (`loop_invariants`), dead code again,
   [copy coalescing](#a-value-computed-only-to-be-copied-is-computed-in-place) (`copy_coalescing`), and dead code
   again;
5. in `generators/windows_x64`: [block layout](#blocks-are-laid-out-along-the-likely-path),
   [register allocation](#values-live-in-registers) (`allocation.spite`), and instruction selection: the
   [immediates and compares](#constants-are-immediates-and-a-compare-is-the-branch),
   [addressing modes](#an-address-sum-is-the-addressing-mode),
   [division by a constant](#dividing-by-a-constant-is-a-multiplication), the
   [arithmetic checks](#arithmetic-checks-cost-one-jump-on-the-hot-path).

A function that waits (a resumable function, whose values live in a heap frame across a suspension) is left as
the lowering wrote it by every pass, and its values stay in its frame: the frame is sized from its registers
before these passes run, and a value must be in the frame when the function resumes.

## Small functions are inlined

A call to a function that waits for nothing and holds at most 24 instructions (an accessor, a list's `get_at` and
`set_at`, a tiny helper), at most 12 when it calls other functions, or at most 40 when it makes an object or is
passed one the caller made, is replaced by a copy of the function's body. Its parameters become the caller's argument registers when the body never writes
them, and a copy otherwise; its answers are copied into the call's answer registers; its blocks are added at the
end of the caller and the call becomes a jump into them. A call to a function whose whole body is a bare `return`
(an empty `_attribute_defaults`, a constructor's `$defaults` with nothing to set) is removed.

It applies when the callee makes no foreign call, thread or library call, takes and answers no decimal in a
register (only a function handed to foreign code does), and the caller is not resumable, is under 4000
instructions and has inlined fewer than 64 calls. A function the compiler wrote, which has no place in the source,
is inlined too; its blocks report the caller's place. Inlining a callee that calls others is what lets an object
the callee makes and answers, such as `Offset.scaled`'s result or `Point.copy()`'s copy, be
[placed](#objects-that-never-leave-their-function-live-in-registers-or-the-frame) in the caller.

What a user can observe: nothing in a program's output. A crash in inlined arithmetic names the function it was
written in (each copied instruction keeps its owner); a native fault in inlined code reports the inlined
function's place, because each copied block carries that place and the place table gets an entry where the code
changes place. The executable holds the callee's body once per call site, and the callee itself too.

```spite
func Lists() {
    var marks = List<Integer>()
    marks.append(0)
    marks[0] = 1
}
```

`marks[0] = 1` is `set_at`'s bounds check and store, written in `Lists` with no call.

## Objects that never leave their function live in registers or the frame

After inlining, each function's objects are followed from where they are made: every register a copy joins to the
one an allocation writes forms a group. A group **leaves its function** when one of its registers is a parameter, is
written by anything but an allocation or a copy, is stored into memory, is passed to a call (other than its own
release, or a call that [keeps nothing of it](#what-a-call-keeps-nothing-of)), is answered with a presence, waited
on, or used in any other way; reading and writing its attributes at fixed offsets, retaining it and releasing it do
not make it leave. A group that does not leave is placed in one of three ways, the first that fits:

1. **One object at a time, in registers.** When no register of the group still holds an earlier object whenever
   the group makes a new one (a loop that makes one row, one copy or one buffer each pass and lets it go before the
   next), every attribute the function touches is one register, shared by the whole group. A read is that
   register, a write sets it, the allocation sets them all to zero (what fresh memory holds), and the object is
   never made. Its count is a register too when the class releases attributes when it is freed (a row of items):
   a retain adds one, a release takes one away and, when it reaches zero, releases those attributes, exactly as
   freeing the object would have.
2. **Several objects, each in its own registers.** When objects of the group overlap in time (a velocity added to
   itself each pass: `velocity = velocity + pulled` makes the new one while the old is still read) but every copy
   of a register is its last use, so no two registers name one object, and the class releases nothing when it is
   freed, each register of the group gets its own register per attribute and a copy copies them all.
3. **In the frame.** Otherwise, when the class releases nothing when freed and is at most 4096 bytes, and the
   function makes at most one object of the group at a time or makes it outside every loop, the allocation becomes
   room in the function's frame (`FrameRoom`, cleared to zero where it is made) and its address in a register;
   its retains and releases are dropped.

An object of a group placed in registers that is answered by `return` is made at the return, with every attribute
written from its registers and a count of one, so a function that builds its answer through a loop of temporary
objects makes one object, not one per pass.

It does not apply to an object whose class has a `drop`, is held back by back references or frees its attributes
in another way than releasing them, to an object read at an offset that overlaps another read, to one whose
attribute is read both as signed and unsigned, to one of more than 32 attributes in registers, or to anything in a
function that waits. A whole number attribute narrower than 64 bits read back from a register is cut and extended
as the read would have done.

What a user can observe: only time and memory. An object in registers or in the frame is never allocated, so
`--debug-memory` counts fewer allocations and frees; its `drop`-less class has nothing else to run.

```spite
func simulate(steps: Integer): Offset {
    var position = Offset(0.0, 0.0, 0.0)
    var velocity = Offset(1.0, 0.5, 0.25)
    var step = 0
    while step < steps {
        var moved = velocity.scaled(0.001)
        position = position + moved
        step = step + 1
    }
    return position
}
```

`scaled` and `+` are inlined, `moved` and every `position` but the answer live in registers, and the one object
made is the answer, at the `return`.

### What a call keeps nothing of

A call keeps nothing of its argument at a position when, in the called function, the parameter and every copy of it
are only read through, written through or compared: never stored, answered, passed on, retained or released. An
object passed only to such calls can still live in the frame (the third placement above), since nothing can hold
its address after the call returns.

## Maths left on constants after lowering is worked out too

An arithmetic instruction or a comparison whose two operands are constants (a register written once, by a
constant) becomes a constant; a branch on a constant becomes a jump; a block nothing reaches is emptied.

It applies to `+`, `-` (operands below 2^62), `*` (below 2^31), `/` and `%` (by a divisor that is neither 0 nor
-1), and the bit operations, signed and unsigned, when the exact answer fits the instruction's width. When it does
not fit, the instruction is kept, so the program still halts at run time with the same report.

A retain or a release of a register known to hold nothing (the 0 an attribute of a fresh object reads) is removed.

## Calls on constants are run while compiling

A call whose arguments are all known while compiling, and whose function touches nothing but its own memory, is run
by the compiler, and the call is replaced by its answer: a number becomes a constant, and an object (a `String`,
a list, any graph of objects the call made) becomes the instructions that allocate it and write its bytes, so the
program gets exactly the object the call would have made, without running the call. A maths function of the C
library on known operands (`0.5.cosine()`, see [the maths functions are one call into the C
library](#the-maths-functions-are-one-call-into-the-c-library)) is answered the same way, and so is every
instruction left with known operands: a decimal operation, a conversion, a read of a text's bytes or of an object
made in the same block.

```spite
func label(count: Integer): String {
    var plural = "cactus".pluralize()
    return "{count} {plural}"
}

func turn(point: Point) {
    var turned_across = point.across * 0.5.cosine() - point.down * 0.5.sine()
    point.across = turned_across
}
```

`"cactus".pluralize()` is the text `cacti` made in three allocations, with none of the inflection tables built or
searched; `0.5.cosine()` and `0.5.sine()` are the constants whose bits are `0x3f60a940` and `0x3ef57744`.

How it works (`low_optimization_passes/compile_time_evaluation`): each block is followed from its start with a
model of memory in which only the objects the block itself allocates exist. A register is known when it holds a
constant (a register written once, by a constant, anywhere in the function) or what a known instruction computed;
an object stays known as long as everything that touches it is known. A call whose arguments are all known runs in
the compiler's interpreter of the low representation (`machine.spite`), instruction by instruction, with the
machine's own semantics: the same wrapping and the same checks for whole numbers, the same IEEE operations for
decimals, the C library's own functions for the maths, every allocation zeroed as `HeapAlloc` zeroes it. Then:

- when the call changed none of the objects that existed before it, its answer replaces it, and the objects it
  made are written out as allocations and stores (a pointer to another of them becomes its register, a pointer to
  a text the address of that text);
- when it changed objects the block made, and nothing else, the call stays, and the block goes on knowing what the
  call left in them, so `"cactus"` built by its `append_code` calls is known when `pluralize` is called on it.

When it does not apply: the call, or anything it calls, reads or writes a singleton or any memory the block did
not make, calls the system or another library (anything but the maths functions), takes a frame's address, starts
or joins a thread, waits, would halt (an arithmetic check, a `crash`, a division by zero), answers not-a-number,
runs past two million instructions (twenty million for the whole program), or leaves an object it made held by
nothing; and an object the block made stops being known as soon as it is passed to something that is not run, so
nothing an unknown function could have written is ever read. The call is then left as it was. A call that failed
once on the same numbers is not tried again.

What a user can observe: the time, and fewer allocations under `--debug-memory` (a folded call's own work
allocates nothing; the objects of its answer are still allocated where it was). A program whose maths is folded
gets the maths library of the machine that compiles it, which is the one it runs on when both are the same
Windows; `sqrt`, `floor`, `ceil`, `trunc`, `round` are exact everywhere, so only the transcendental functions can
differ, by their last bit, between two versions of the C library.

## A number's own bits are read in place

A number class reads its value through the bytes of its room (`Float._value()` is
`_buffer._read_float_at(0)`), and the room of a number is made only when its bytes are needed. A read of the room
at offset 0, of the number's own width and sign, is the number itself: no `Buffer` is made, written and read back.

```spite
func half_of(value: Float): Float {
    return value.divide(2.0)
}
```

`divide` reads both operands with `_value()`, and each read is the register that holds the number. Before, every
`_value()` allocated a `Buffer` of four bytes, stored the number in it and loaded it again, so every library
function of a number (`sum`, `minimum`, `to_string`, `bits`, the maths) paid an allocation per operand. When it does
not apply: a read at another offset or of another width, and `to_buffer()`, which still copies the bytes into a
`Buffer` the caller keeps. What a user can observe: the time, and no allocation under `--debug-memory`.

## The maths functions are one call into the C library

`sine()`, `cosine()`, `tangent()`, `arc_sine()`, `arc_cosine()`, `arc_tangent()`, `arc_tangent_over(run)`,
`power(exponent)`, `exponential()`, the three logarithms, `floor()`, `ceiling()`, `truncate()` and `round()` on
`Float` and `Double` are bodiless declarations (`_sine()` and the rest) the compiler writes as one call through the
import table to the C library's function (`sinf`, `cos`, ...), with the operands in the decimal registers the
Windows calling convention passes them in. The executable imports `ucrtbase.dll` only when it calls one of them,
and only the functions it calls. `square_root()` is one `sqrtss` or `sqrtsd`.

```spite
func height_at(angle: Float): Float {
    return angle.sine() * 10.0
}
```

Before, each call made a `DynamicLibrary` (three `String`s copied byte by byte), opened `ucrtbase.dll`, looked the
function up and called it through a pointer. When it does not apply: nothing else calls the C library this way;
the system classes still open their library with `DynamicLibrary`. What a user can observe: the answers are the C
library's, bit for bit, as before; the time; and one more imported library in the executable.

## Jumps to jumps go straight to the end

A jump or branch to a block that only jumps on goes to where that block jumps (through at most 16 such blocks),
and a branch whose two targets are the same block is a jump.

## A copy of a value that never changes is the value

A copy `t = s`, where `t` is written only by that copy and `s` is a parameter never written or a register written
once earlier in the same block (with no read of `t` in between), is removed by reading `s` wherever `t` is read.

## A value nobody reads is not computed

A constant, copy, comparison, unchecked arithmetic, decimal arithmetic or address whose answer no instruction
reads is removed, repeatedly until none is left. Checked arithmetic, division, loads, stores and calls are never
removed: each of them can halt the program or change memory.

## A value computed only to be copied is computed in place

`t = a + b` followed in the same block by `x = t`, where `t` is written and read only there and `x` is neither
read nor written in between, becomes `x = a + b`. This is what turns `index = index + 1` into one `add`.

## The same computation in a block is made once

Within a block, an unchecked arithmetic, a decimal arithmetic or conversion, an address of data or of a function,
or a load, that repeats one made earlier in the block on the same registers, with neither register written in
between (and, for a load, no store, call, allocation or other write of memory in between; a retain only changes
the count, at offset 8), copies the earlier answer instead. `a + b` and `b + a` are the same for `+`, `*` and the
bit operations.

Across blocks, the same holds for a computation whose registers, read and written, are each written once in the
function: when it is made on every path to a block (found by following the blocks forward, keeping only what every
path leading in made, and forgetting loads at every write of memory), a repeat in that block copies the answer.
`list.count()` read before a loop and again in the loop's bound test is one load when the loop writes nothing.

It does not apply to checked arithmetic, a division or a comparison (which is better made again just before the
branch that reads its flags), nor across blocks to a register written more than once or in a function of more than
400 blocks.

## What a loop does not change is computed before it

A loop is found from each jump back to a block that dominates it. When the loop is entered from exactly one block
that only goes on to it, an instruction in the loop is moved to the end of that block when every register it reads
is written only outside the loop (or by an instruction already moved), it writes a register nothing else writes,
and it is an unchecked arithmetic, a copy, a decimal arithmetic or conversion, or an address. A load moves too
when it is in the loop's first block (which every pass runs) and nothing in the loop writes memory or calls
(a retain only blocks a load of the count). Each instruction moved runs once instead of once per pass.

It does not apply to a function of more than 400 blocks or that waits, to checked arithmetic, divisions and
comparisons, nor to a load past the loop's first block, since a pass that leaves early would not have made it.

## A remainder by a power of two tested against zero is a mask

`x % 2^k` read only by `== 0` or `!= 0` is `x` with its low `k` bits kept (`and`), signed or not: a whole number is
divisible by `2^k` exactly when those bits are zero. `if index % 2 == 0` is a `test`.

## Blocks are laid out along the likely path

The generator writes a function's blocks in the order of their likely path rather than in the order the lowering
made them: after a block comes the block it jumps to, or the true side of its branch, and the false side is written
once the path that went the other way ends. A loop's exit comes after its body, and the body of an inlined call
right after its call. A jump to the block written next costs nothing, and a branch whose true side comes next is
inverted.

## Values live in registers

Every value of a function that does not wait lives in a machine register when one is free, and in its frame slot
otherwise. Liveness is found over the blocks (a value live into a block is live at the end of every block that
leads there, up to the blocks that write it), and each value lives in one interval, from its first point to its
last in the layout order; a linear scan gives each interval a register.

- The registers given are the seven the Windows x64 calling convention keeps across calls (`rbx`, `rsi`, `rdi`,
  `r12` to `r15`), saved in the frame by a function that uses them and restored at each return, and `r10` for a
  value whose interval holds no call nor any instruction that may call (an allocation, a checked or dividing
  arithmetic, whose crash report calls the console). `rax`, `rcx`, `rdx`, `r8`, `r9` and `r11` stay the scratch
  registers instructions work in.
- When no register is free, the value whose uses weigh least is spilled: each use or write weighs 8 to the power of
  how many loops hold it (at most 4).
- A spilled value lives in its frame slot for its whole life.

What a user can observe: nothing but time; a crash report reads its numbers from wherever the values live.

## Constants are immediates, and a compare is the branch

A register written once by a constant (and that is not a parameter) is never written: each use is the constant
itself, as an immediate operand (`add r, 7`, `cmp r, 300000000`, `mov dword [r + 4], 1`) or loaded into the
register that needs it. A comparison read only by the branch right after it is no value at all: the compare sets
the flags and the branch jumps on them; a branch on a comparison made just before it (with only plain copies in
between) also jumps on the flags. A comparison with zero is a `test`.

## An address sum is the addressing mode

A load or store whose address is a sum written only for it in the same block (`base + constant`,
`base + index`, or `base + index * 1, 2, 4 or 8` with the product written only for the sum) uses the x64
addressing mode instead: `movsxd r, dword [base + index*4 + 16]`, and the sum and the product are not computed.

## Dividing by a constant is a multiplication

A division or remainder by a constant that is neither 0 nor -1 drops the checks for both, which cannot fail. By a
power of two up to 2^30 it is a shift (signed: with the rounding toward zero that `/` has) or a mask; signed, by any
other divisor from 3 to 2^31 - 1, it is a multiplication by a magic number worked out while compiling, a shift and a
sign correction. A signed divisor from -2^31 + 1 to -2 divides by its size and negates the quotient (the remainder
is the same, since it takes the sign of what is divided). An unsigned number of 32 bits or fewer divided by any
other constant from 3 to 2^31 - 1 is multiplied by `2^63 / divisor + 1` worked out while compiling, keeping the top
of the 128-bit product: exact for every such number. A multiplication by a power of two that is not checked is a
shift. An unsigned 64-bit number divided by a constant that is not a power of two keeps the `div`.

```spite
func Sums(): Long {
    var total: Long = 0
    var index: Long = 0
    while index < 1000 {
        total = total + index % 7
        index = index + 1
    }
    return total
}
```

`index % 7` is no `idiv`: a multiplication, two shifts, two additions and a subtraction.

## A proven divisor is not checked

A division or remainder whose divisor's [range](#arithmetic-a-range-proves-is-not-checked) holds neither 0 nor -1
(`crash parts > 0` before `amount / parts`) is lowered unchecked: the generator writes no zero test and no -1 path,
only the division. A division of 32-bit numbers divides in 32 bits (`cdq` and `idiv ecx`), which is faster than the
64-bit `idiv`, whether it is checked or not.

What a user can observe: only time; a divisor the range cannot prove is tested as before and halts with the same
report.

```spite
func shares(amounts: List<Integer>, parts: Integer): Long {
    crash parts > 0
    var total: Long = 0
    var index = 0
    while index < amounts.count() {
        var amount = amounts[index]
        total = total + amount / parts + amount % parts
        index = index + 1
    }
    return total
}
```

## Arithmetic checks cost one jump on the hot path

Checked `+`, `-` and `*` jump on the overflow (or carry, unsigned) flag to the code that writes the report, which
is written after the function's blocks, out of the path that runs. A 64-bit operation works in its target's
register directly, undoing itself in the report's path when it overwrote an operand the report prints; a 32-bit one
works in 32 bits and its overflow flag is the check. A division's zero check jumps out the same way.

## A dictionary hashes a key once, cheaply

The library's `Dictionary` keeps its keys and its values in two lists, in the order the keys were first set, and
over them a table of slots: a power of two of them, each the position of an entry and 32 bits of its key's hash,
never more than half full. Every `get_at`, `set_at`, `contains` and `remove_at` hashes the key once and walks the
slots from the one the hash names; a slot whose hash bits differ is passed without reading its key, so a key is
compared only where its bits already match. Growing the table moves each slot by the bits it keeps, so no key is
hashed again, and an empty dictionary has no table.

A `String` key is hashed by its bytes, eight at a time (one exclusive or and one multiply each, then the bytes
left over), and two keys are compared eight bytes at a time.

```
func count_words(words: List<String>): Dictionary<String, Integer> {
    var counts = Dictionary<String, Integer>()
    var index = 0
    while index < words.count() {
        var word = words[index]
        var seen = counts[word]
        if seen {
            counts[word] = seen + 1
        } else {
            counts[word] = 1
        }
        index = index + 1
    }
    return counts
}
```

When it applies: every dictionary. When it does not: the work around it; a read written twice
(`if counts[word] { total = total + counts[word] }`) still looks the key up twice. What a user can observe: the
time, one more allocation for a dictionary's table once it holds a key, and `remove_at`, which takes time in
proportion to the table, as the specification says. `keys()`, `values()` and `to_debug()` answer in insertion order
as before.

## A dictionary keyed by numbers hashes the numbers

A key that is not text (a whole number, a `Boolean`, an enum value, an object) is hashed from its bits by one
multiply by 6364136223846793005, with no `String` made for it: the library's `Dictionary._key_bits(key)` has no
body, and the compiler answers the key's own register, so an object is hashed by its identity. A `Float` or a
`Double` is hashed the same way once `0.0` and `-0.0` are one key and every not-a-number is one key, the first one
stored being the key `keys()` answers. The slot is the top bits of the product, so keys that differ only in their
high bits (addresses, `Long`s) still spread over the table.

```
func squares(): Dictionary<Integer, Integer> {
    var table = Dictionary<Integer, Integer>()
    var index = 0
    while index < 1000 {
        table[index * 7] = index * index
        index = index + 1
    }
    return table
}
```

When it applies: every dictionary whose key is not a `String`. What a user can observe: nothing but the time.

## A number read from bytes is one load

`Buffer`'s big-endian reads and writes (`read_integer_big_endian_at`, `write_long_big_endian_at` and the rest, of
every width, whole or decimal) are one load or one store of that width with the bytes swapped in the register
(`bswap`, or a rotate by eight for two bytes), as a little-endian one is one load. The library declares
`_read_integer_big_endian_at(at)` and the rest with no body, and the compiler writes each one; nothing is copied to
read a number, where before each read made a `Buffer` of the bytes reversed.

```
func identity_of(record: Buffer, at: Integer): Integer? {
    return record.read_integer_big_endian_at(at)
}
```

When it applies: every big-endian read or write of two bytes or more. When it does not: the public read is still a
call that tests the bounds and answers `null` outside them. What a user can observe: no allocation for a read,
under `--debug-memory`, and the time.

## A dictionary written out and only read by literal keys is folded

A local made from a dictionary literal whose keys are all text or all whole numbers written out, whose values are
all literals of one kind, and that its function only ever reads with a key written out (`points["gold"]`), is
never made: each read is the value written for that key, or `null` for a key the literal does not have. The read
keeps its type, a `T?`, so `crash points["gold"]` and `if` narrow it as they would; after the `crash`, the read is
the value itself.

```
func points_for(golds: Integer, silvers: Integer): Integer {
    var points = {"gold": 50, "silver": 20}
    crash points["gold"]
    crash points["silver"]
    return golds * points["gold"] + silvers * points["silver"]
}
```

`points_for` makes no dictionary and hashes nothing. When it does not apply: a literal with a declared type, a key
or a value that is not a literal (`-5` included), the same key twice, any other mention of the local (a key in a
variable, a write, `count()`, passing it, a second `var` of the same name in the function), a dictionary held in an
attribute, and the interactive builds (`--repl`, `--repl-port`, `--development`, `--hot-reload`), which keep the
dictionary a reader can inspect. What a user can observe: no dictionary, no allocation and no hashing for the
folded ones, and nothing else.

## Thread safety for singletons, the cheapest safe form

In a program that makes a `Parallel`, every singleton the work a `Parallel` runs can reach (following calls from
each function a `Parallel` starts) is made safe for threads in the first of these forms that holds for what its
functions do. A singleton no such work reaches gets none of them, and a program without `Parallel` gets none at all.

1. **Nothing, when it never changes after it is made.** No function of its own but its constructor (and the
   attribute defaults run while it is made) assigns its attributes, no other class assigns them, no shape write
   can reach them, and every attribute is a number, a `Boolean`, an enum, a `String` nothing calls a function on,
   or another singleton. Its functions are compiled as in a program without threads, so a small one is inlined.
2. **Atomics, when what changes is whole numbers or `Boolean`s and each function touches that state once.** Every
   function but the constructor reads one attribute, or writes one, or updates one with `attribute = attribute + x`
   or `attribute = attribute - x` (`x` reading none of its attributes), outside any `while`, and does nothing else
   with `this`; no other class writes its attributes. A read is one load and a write one store, which are atomic
   for an aligned slot. An update is a loop around one compare-exchange: it loads the attribute, computes the new
   value with its overflow check, and stores it only if the slot still holds what it loaded, so an addition that
   does not fit halts before anything is written and no two threads lose an update.
3. **Its own lock, otherwise.** Each function of the singleton that reads `this` takes the singleton's lock for its
   whole call. The lock is a word in the singleton's slot holding the thread that owns it, with a count of how
   deep that thread holds it: a call by the owning thread only adds one to the count, a free lock is claimed with
   one compare-exchange, and a held one is retried after giving the processor up. The thread is read from the
   thread's own block (`gs:[0x48]`), not asked of the system.

**What a program can observe:** only the time. A function that took the lock and one compiled in the first two
forms run as if alone: a reader sees a value from before or after a call, never one half-way through it, and
every update counts.

```spite
var counter = HitCounter()
var settings = Settings()

func run(): Integer {
    var index = 0
    while index < 1000000 {
        var step = settings.step_size()
        counter.record(step)
        index = index + 1
    }
    return index
}
```

With `Settings` only set in its constructor and `HitCounter.record` a single `hits = hits + amount`, `run` reads
the step in place and adds with one compare-exchange, where every call took two locks before. Measured on
`thread_safety_for_singletons_the_cheapest_safe_form` (four `Parallel`s running `run`).

**Not built:** the readers' side shared by functions that change nothing, a read of a locked singleton's attribute
from another class taking the lock, and the walk made again after tree shaking (form 1 decided over the whole
program as written out).

## While no task runs, a singleton's lock is claimed with a plain store

Every thread a `Parallel` (or a helper for a blocking call) starts is counted in one word from just before it
starts until its work has returned and let go of what it held. A call that takes a singleton's lock and finds the
lock free and that count zero claims the lock with a plain store instead of a compare-exchange: with no task in
flight the program's own thread is the only one running program code, so nothing can claim the lock at the same
moment. A task started while the call holds the lock (by the call itself or anything it calls) finds the lock
owned and waits for it as usual, so it never sees the singleton half-way through a call, and starting a thread
publishes the plain store to it. This replaces the stack of skipped locks the language describes: the lock is
still taken, only without the atomic instruction, so nothing needs to be taken again when a task starts.

**When it does not apply:** in a program that makes a `ForeignCallback`, since C may call one from a thread of its
own that is not counted; there every free lock is claimed with a compare-exchange.

**What a program can observe:** only the time. Counting a task is one atomic addition when the thread starts and
one when its work ends, made only in a program where some singleton takes a lock.

```spite
var tally = Tally()

func add_many(count: Integer): Integer {
    var worker = Worker()
    var first: Integer = Parallel(worker.run)
    var index = 0
    while index < count {
        index = tally.add(index)
    }
    return index + first
}
```

With `Worker.run` calling `tally.add` too, `Tally` takes a lock; once the `Parallel` has been waited for, each `tally.add` claims and frees `Tally`'s lock with plain loads and
stores (`while_no_task_runs_a_singletons_lock_is_skipped`).

## A counted loop of calls to one singleton takes its lock once

A `while` outside a singleton whose condition is `counter < bound` or `counter <= bound`, whose last statement is
`counter = counter + n` with `n` a positive whole number written out and that assigns the counter nowhere else,
holds the lock of one locked singleton for the whole loop when every call in it is a call to that singleton's
functions answering a number, a `Boolean`, an enum or nothing, and nothing in it but local `var`s and assignments
of plain values, `if`s, plain `crash`es and arithmetic. None of the singleton's functions it calls, nor anything
they call, may wait, start work, call through a function value or take another singleton's lock. The lock is taken
before the loop's first test and let go after its last, and each call inside goes to the function's body compiled
without the lock (`<function>$unguarded`), which is small enough to be inlined where the locked one was not.

It cannot hang: the loop ends on its own (its counter only grows, and an addition that does not fit halts), it
takes no other lock while it holds this one, and it holds it across no wait.

**What a program can observe:** only the time. Other threads calling the singleton wait for the whole loop instead
of for each call, which is one of the orders they could already run in.

```spite
var tally = Tally()
var rounds = 0

func count_up(): Integer {
    var index = 0
    while index < rounds {
        tally.add(index % 3)
        index = index + 1
    }
    return rounds
}
```

Four `Parallel`s running `count_up` each take `Tally`'s lock once
(`a_counted_loop_of_calls_to_one_singleton_takes_its_lock_once`).

**Not built:** a loop that is not counted testing the task count once before it starts.
