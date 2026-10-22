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

`"{first} meets {second} at the gate."` is one join, not a chain of pairs. The compiler makes the text once and
appends every piece to it in order: a written piece's bytes go straight in, with no text made for them, and a hole's
text is appended and let go. A chain of pairs would make a whole new text at every piece and copy everything joined
so far into it.

```
func greeting(first: String, second: String): String {
    return "{first} meets {second} at the gate."
}
```

The pieces are worked out left to right as written, so anything a hole calls runs in the order the source reads in.

When it does not apply: a join written as calls (`first.sum(second)`) is a call, and a program that replaces
`String.sum` by reopening `String` keeps calling its own. What a user can observe: fewer texts made, under
`--debug-memory`.

## A number joined into text is written in place

`"line {index} of {round};"` reads as turning each number into a text and joining the pieces. Inside a join, an
`Integer` or a `Long` piece is written as digits straight into the text being joined: the compiler counts the
digits, makes room for them and writes them from the last, so no text is made for the number.

```
func label(index: Integer, round: Integer): String {
    return "line {index} of {round};"
}
```

The digits are the ones the library's `to_string()` writes: a `-` for a number below 0, and `0` for zero. When it
does not apply: a number that is the whole text (`"{index}"`), a number of another type, and a program that
replaces `Integer.to_string()` or `Long.to_string()` by reopening the class, which keeps calling its own. What a
user can observe: fewer texts made, under `--debug-memory`.

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
operation, which halts as it would have; a division, a call and a decimal are not worked out. What a user can
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
