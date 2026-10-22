# Optimisations

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
