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

`var held = this.part`, `var point = points[position]` once the read is proven, or a list's own
`var held = _read_value(index)`, does not count `held` when nothing after it in its block can write the slot it
came from: no assignment of an attribute on its path and no call that may
write one, no write into a list of that class (`_write_value`, `_forget_value`) and no call that may make one. The
name is then read as it is and let go of nothing when its block ends. This is what makes a list's templates
(`contains`, `index_of`, `join`, `copy`, and the others handed a function that cannot write the list) read their
items without counting them, and a loop that reads `var point = points[position]` and only reads its attributes
neither counts nor lets go of each point (`objects_of_one_class_sit_together`: 94 ms before, 64 ms after;
`report_over_records`: 866 ms before, 517 ms after).

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

## An item a call cannot let go is passed without counting

`buckets[customer].append(order)`, after a `crash buckets[customer]` that proves the read, passes the bucket to
`append` as it is in its slot, with no count taken and none let go, when nothing the call can run writes an item of a
list of that class (`_write_value` or `_forget_value` on it, followed through every call, and every `drop()`), the
list itself is a steady path (a name, `this`, a singleton or attributes no call assigns), and the index and the
call's arguments are plain reads: the slot holds the item for the whole call.

**When it does not apply:** to an item read without its `crash` (the read may be missing), to a call that may write
a list of that class or reach a `drop()` that does, to arguments that are calls, and in a function that waits. The
item is then counted for the call as before.

**What a program can observe:** nothing but time.

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

A copy written by the compiler (`copy()` and `deep_copy()` of a class that has none of its own, without a table)
assigns every attribute itself, so it makes its object with no defaults at all: copying an `Order` whose defaults
make a `Customer` and a `List<Line>` makes neither
(`a_deep_copy_is_written_per_class_with_a_table_only_where_a_graph_needs_one`: 37 ms before, 22 ms after).


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
  no step in a nested loop, at most the bound's largest value plus its steps;
- a total assigned once in a loop, at the top of its body, as `total = total + term` (or `total - term`, or
  `term + total`), with a term that is not the total itself, holds before that assignment its range on entering
  the loop plus between none and one fewer than the loop's passes of the term's range, and after the loop as many
  as its passes; the passes are counted by a counter the body steps once, at its top, by a constant, under
  `counter < bound`. So a `Long` total of `Integer` terms over a list's items keeps no check, since the count is an
  `Integer`.

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
is unchecked too: the loop runs at most 2147483647 passes, so before the addition `sum` holds at most 2147483646
items, each an `Integer`, which a `Long` always holds.

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

## A list item read only to test it is not counted

`list[index] is present` on a library `List` or `Vector` of items that cannot be null is the test
`index < count`, compared as unsigned so a negative index is outside too: the item is never read, so it is never
counted and let go. `crash velocities[entity] and healths[entity]` is two such tests, and its report, made only when
one fails, reads the items as before.

What a user can observe: the time. When it does not apply: a list of nullable items (an item there can be missing
inside the bounds), `Items`, a `Dictionary`, and any other function than `get_at`.

## A singleton a function answers is not counted

A singleton lives from its first use to the program's end, so its count never decides when it goes. A function
whose declared answer is a singleton class returns it without counting it, and every call of such a function
(a plain call, a call through a function value, a call in a function that waits, and the read of an attribute
rebuilt where it is read) takes the answer without letting it go afterwards. In
`thread_safety_for_singletons_the_cheapest_safe_form`, `counter.record(step)` reads `counter` through its
rebuilt attribute; that read answered the `HitCounter` counted, so four threads took and gave back the same count
atomically on every call (about 180 ms); now it is one load (about 135 ms).

When it does not apply: a function whose declared answer is a union, a shape or a nullable of anything else, even
when it answers a singleton: its callers count what any member of the type could be. What a user can observe: the
time.

## Letting go of an object counts down in place

A release of an object whose class is not known while compiling is written where it stands: the test for no
object, the count taken down (one atomic subtraction in a program with threads) and, only when it reaches zero, a
call of `_free_by_class`, which finds the free function from the class number. Before, every release was a call of
`_release`, which made the same steps behind a call. The passes before it still see one `_release` call, so it is
written last, after every other pass (`low_optimization_passes/released_in_place`).

What a user can observe: the time, and a larger executable where releases are many.

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

An attribute whose default is a singleton (`var rules = Rules()`) is read as the singleton itself wherever it is
read, inside loops too, and takes no slot, when the singleton's defaults and its constructor only assign its own
attributes from pure values and nothing in the program has a `drop()`: the singleton is the same object at every
read, so only when it is made can move, and making it does nothing a program can see. A singleton's or the entry
class's attribute keeps its slot, and so does every such attribute in a program with a `drop()`, since a `drop()` at
exit may read it after the singleton is destroyed, which the slot's count keeps from happening. See [a singleton is made on first use, by a function of its
own](#a-singleton-is-made-on-first-use-by-a-function-of-its-own).

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
   [counted pairs](#a-count-taken-and-let-go-with-nothing-between-is-never-taken) (`counted_pairs`),
   [common subexpressions](#the-same-computation-in-a-block-is-made-once) (`common_subexpressions`), copy propagation
   again, [proven bounds](#a-bound-a-signed-test-already-proved-is-not-tested-again) (`proven_bounds`), constant
   folding and jump threading again,
   [remainder tests](#a-remainder-by-a-power-of-two-tested-against-zero-is-a-mask) (`remainder_tests`),
   [loop invariants](#what-a-loop-does-not-change-is-computed-before-it) with
   [attributes in registers](#an-attribute-a-loop-updates-lives-in-a-register-until-the-loop-ends)
   (`loop_invariants`), copy propagation again, dead code again,
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

## A crash's report is a cold call

The code that reports a failed `crash` (every value it shows, the `spite: the program stopped` line and the
frames) runs only once, as the program halts, so the compiler moves it out of the function before inlining: every
run of blocks that can only end the program, eight instructions or more, becomes a function of its own
(`<function>$cold<n>`) that takes the values it reads, and the guard calls it. The passing path is unchanged, and
the function holding the guard is as small as it was without it, so it is inlined again.

    func checked_half(value: Integer): Integer {
        crash value >= 0
        return value / 2
    }

is inlined into its caller as a compare, a branch to `checked_half$cold0(value)` and the division. The report reads
the same: the cold function's calls carry no frame line of their own, and the call to it carries the guard's line,
so `spite.frame` lines name the guard's function and its callers as before.

## Small functions are inlined

A call to a function that waits for nothing and holds at most 24 instructions (an accessor, a list's `get_at` and
`set_at`, a tiny helper, a read of a singleton), at most 24 when it calls other functions too, or at most 40 when it
makes an object or is passed one the caller made, is replaced by a copy of the function's body. A call inside a
loop that is passed an object the caller made is inlined up to 128 instructions, when the function is written in
the program (not by the compiler) and makes no object itself: the row a walk fills (`fill_attributes(row, found,
entity)`, unrolled into one function per attribute) then lives in the loop's registers instead of on the heap
(`a_walked_crash_lines_read_is_the_rows_read`). The blocks that can
only stop the program (a failed `crash` calling its [cold report](#a-crashs-report-is-a-cold-call)) are not counted,
and their call to the report does not count as a call, so a guard costs a function nothing toward its size. The
address of a singleton's slot or of a function is copied like any other instruction, so a function that reads a
singleton is inlined too. A function the compiler wrote (the scheduler's, a list's machinery) that calls others is
inlined only up to 12 instructions, and not at all when it takes an address and calls anything but a singleton's
maker, so the frames a call inside it reports stay those of the call it was written for. Its parameters become the caller's argument registers when the body never writes
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

## A call that returns at once on a test is tested in place

A call inside a loop to a function too large to inline, whose first block only reads and compares (loads,
constants, copies, comparisons, unchecked arithmetic, at most twelve instructions, none writing a parameter) and then
returns nothing on one side of its branch, makes that test in the caller: the call runs only on the other side. A
list's `reserve()` called by every `append` is a compare with the capacity, and the call is made only when the list
grows. The function is called as before when it runs, and reads its test again.

**When it does not apply:** to a function the compiler wrote, one that answers a value or waits, or a call outside
any loop. **What a program can observe:** nothing but time.

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

The free function of the class says which attributes it lets go of: each one it reads from the object and either
passes to `_release` or counts down in place and frees with the attribute's class's own free function (how
[letting go of an object of a known class is direct](#letting-go-of-an-object-of-a-known-class-is-direct) writes
it). A row of items (`{position: positions[entity], velocity: velocities[entity]}`) passed to an inlined
`update_each` is therefore registers, with no allocation per pass
(`a_row_of_borrowed_items_lives_in_the_frame`: 753 ms before, 530 ms after).

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

### A row's count is followed while compiling

What a class lets go when it is freed is read from its compiled `_free_` function, whether that releases each
attribute with a call or with the release written in place (a test for null, the count taken down by one and the
object's own `_free_` where it reaches zero), so a row of a `type` holding objects is placed in registers like any
other. Where the count of an object placed in registers is known (one when it is made, one more at each retain, one
less at each release, followed along every path), a retain and a release write the new count and nothing else, and
the release that brings it to zero lets go of the row's attributes in place, with no test.

### What a call keeps nothing of

A call keeps nothing of its argument at a position when, in the called function, the parameter and every copy of it
are only read through, written through or compared: never stored, answered, passed on, retained or released. An
object passed only to such calls can still live in the frame (the third placement above), since nothing can hold
its address after the call returns.

## A list's objects sit inside its storage

A `List` of a class of the program whose objects are only ever put into it fresh and read back from it holds the
objects themselves, one after another in its storage, instead of a pointer to each: `append` copies the new
object's bytes into the next slot, `list[index]` is the slot's address, and the objects of the list sit together in
memory, so a walk over them reads memory in order and loads no pointer. The slot keeps the object's header, with a
count no release can bring to zero, so the code that reads an item is the code that reads any object of the class.

**When it applies:** the whole program is read while compiling, and a list class is held this way when all of these
hold:

- its element is a class of the program, not a singleton, with no `drop()`, held by no back reference, whose
  attributes are all numbers, `Boolean`s or enums;
- every function of the list that is compiled is its making, `count()`, `is_empty()`, `append`, `get_at` (and
  what `append` calls to grow), or a `sum_`, `count_`, `any_` or `all_` template;
- every `append` is given a local made with the class's constructor and read nowhere else
  (`var point = Point(x, y)` then `points.append(point)`), or an object a literal makes in place;
- every `list[index]` is tested (`if`, `crash`), read for an attribute or a call of the class, or kept in a local
  that is only read for attributes, written for attributes or called on, and after which nothing in its block may
  grow or write the list (the rule of [a name holding an item](#a-name-holding-an-item-or-an-attribute-is-not-counted));
- no function of the element class lets `this` go anywhere but its own attributes and its own functions;
- the list is never turned into a shape, a union or a function value, and no function of the list or the class is
  taken as a value.

**What a program can observe:** only time and memory. A local made by a constructor and appended by the very next
statement is made in the list's next slot (the list grows first, then the defaults and the constructor run on the
slot, then the count grows by one), when neither the constructor nor the defaults can write the list's items or
change which list the receiver is; any other object appended is made, copied into its slot and let go of, so
`--debug-memory` counts it. The list's storage is larger by the objects it now holds.

```spite
func sum_points(): Long {
    var total: Long = 0
    var position = 0
    while position < points.count() {
        var point = points[position]
        total = total + point.across + point.down
        position = position + 1
    }
    return total
}
```

With every `Point` made as `var point = Point(index % 1000, index % 30)` and then appended, `points[position]` is an address in
the list's storage (`objects_of_one_class_sit_together`: 64 ms before, 39 ms after; `report_over_records`: 517 ms
before, 433 ms after).

**Not built:** one array per attribute (the layout the attributes a walk reads would want), an element holding
text or objects, an object appended that is read again after, and the list's other functions.

## A list's objects sit in one array per attribute

A list whose objects [sit inside its storage](#a-lists-objects-sit-inside-its-storage) goes one step further when
nothing ever needs one of its items whole: its storage holds one array per attribute, the widest first, each as
long as the list's room, and no header at all. `points[position].down` is a load from the `down` array at
`position`, so a loop that reads one attribute reads only that array, four bytes an item for an `Integer` where the
whole object took twenty-four. `append` copies each attribute of the object into its array, and growing the list
moves each array to its place in the larger room.

**When it applies:** to such a list whose element's attributes are all whole numbers held in their own slots, whose
items are only read and written for attributes (never the receiver of a function of the class, and never summed or
counted through a function member such as `sum_fingerprint`). The list's `get_at` as a function is never called
then; if it were, it would stop the program saying the item cannot be handed out whole.

**What a program can observe:** only time and memory.

```spite
func sum_points(): Long {
    var total: Long = 0
    var position = 0
    while position < points.count() {
        var point = points[position]
        if point.down >= round {
            total = total + point.across + point.down
        }
        position = position + 1
    }
    return total
}
```

`point` is the position, and `point.down` and `point.across` are reads of two arrays.

## A local list of known size lives in the frame

A list literal kept in a local (`var weights = [4, 3, 2, 1]`) that the function only counts and reads by index is
never made: its items are written into room in the function's frame (`FrameRoom`), its `count()` is the number of
items written, and `list[index]` tests the index against that number and loads the item from the room. No list, no
buffer and no count is allocated, so nothing is freed either.

**When it applies:** to a literal of whole numbers (any `Integer`, `Long`, `Byte`... list that is not nullable),
of at most 4096 bytes, kept in a local that is never assigned again, and whose every use in the function is
`count()`, `list[index]` (read, tested with `crash`, `assert` or `if`), or the literal itself. A list passed to a
call, answered, kept in an attribute, appended to, read by any other function of `List`, or held by a function
that waits is made as before. A list of decimals or objects is made as before.

**What a program can observe:** fewer allocations under `--debug-memory`. An index outside the list still stops
the program with the same report.

```spite
func largest_remainder(round: Integer): Integer {
    var remainders = [round % 10, round % 7, round % 13, round % 3]
    var weights = [4, 3, 2, 1]
    var biggest = 0
    var index = 0
    while index < remainders.count() {
        crash weights[index]
        var weighted = remainders[index] * weights[index]
        if weighted > biggest {
            biggest = weighted
        }
        index = index + 1
    }
    return biggest
}
```

Both lists live in the frame: four stores each, a count of 4 and loads at fixed offsets
(`a_local_list_of_known_size_lives_in_the_frame`: 695 ms before, 98 ms after).

## Maths left on constants after lowering is worked out too

An arithmetic instruction or a comparison whose two operands are constants (a register written once, by a
constant) becomes a constant; a branch on a constant becomes a jump; a block nothing reaches is emptied.

It applies to `+`, `-` (operands below 2^62), `*` (below 2^31), `/` and `%` (by a divisor that is neither 0 nor
-1), and the bit operations, signed and unsigned, when the exact answer fits the instruction's width. When it does
not fit, the instruction is kept, so the program still halts at run time with the same report.

A retain or a release of a register known to hold nothing (the 0 an attribute of a fresh object reads) is removed.

## Walks over classes, values and members are unrolled while compiling

A walk whose list is known while compiling is no loop in the program: the compiler writes one call per element.
`Namespace.classes.each(walker)`, with `walker` taking a `Spite.Class`, makes one copy of `walker` for each class
of the namespace's folder, in which the parameter is that class (`Runner<system>()`, `system.has_function(...)`,
`system.name` are all constants); `Enum.values.each(walker)` calls `walker` once per value, with the value as a
constant; and a template's plural (`fill_attributes(row)`, `run_phases_each()`) is one call of the template's copy
for each member it ranges over. `$type.values`, where the generic is bound to an enum, is a constant list of its
values. Nothing of a walk is left at run time: no reflection object is made, no list of classes or values is
kept, and a walker nobody walks is not compiled.

```spite
func Schedule() {
    System.classes.each(add_system)
}

func add_system(system: Spite.Class) {
    var runner = Runner<system>()
    runners.append(runner)
}
```

It applies when the namespace or the enum is named directly (or `$type` bound to an enum) and the walker is a
function of the same class taking one parameter. A list of classes or values reached at run time
(`thing.class.namespace.classes`) is walked as an ordinary list of reflection objects. What a user can observe:
the order of the calls is the order of the folder's files and of the enum's values, the same as the walk at run
time would take.

### A walk over a known function or argument list

`each` over `C.functions` (written directly, or through a local made from `C.functions` or
`C.functions.filter(test)` that nothing assigns again), or over the `arguments` of a function that is itself known
this way, is unrolled when its walker needs the item known: it passes the item to a function whose answer is typed
by it (`made(argument): argument.class`), or walks the item's arguments with such a walker. The compiler writes one
copy of the walker for each function of `C`, in the order `C.functions` lists them, or for each argument, and calls
it with the item the list holds at run time when that item has the name the copy was made for; the item's name is
compared once per item, and a list that holds an item the compiler did not list stops the program naming the walk.
Inside a copy, a call that hands the item to a function typed by it is compiled once for that argument, as a walk
over attributes is.

```spite
func ReflectionWalks() {
    var walked = Runner.functions.filter(walks_each)
    walked.each(run)
}

func run(function: Spite.Function) {
    function.arguments.each(describe_taken)
}

func describe_taken(argument: Spite.Argument) {
    var fresh = made(argument)
}

func made(argument: Spite.Argument): argument.class {
    return argument.class()
}
```

What a user can observe: the filter's test still runs at run time, once per function, and the reflection objects
are made as they would be; a walker that needs nothing known walks the list as an ordinary loop.

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
Measured on `a_word_inflected_while_compiling`, which calls `label` a million times: 4.3 s while the inflection ran
every time, 67 ms with it answered while compiling.

How it works (`low_optimization_passes/compile_time_evaluation`): the pass runs twice, once before inlining (so a
call like `"cactus".pluralize()` is answered while it is still one call, before its body is spread into the
caller) and once after it (for the calls inlining leaves with known arguments); before the first run each function's
constants are folded and its jumps threaded. Each block is followed from its start with a model of memory in which
only the objects the block itself allocates exist, and the model carries on into the next block when that block is
entered only from this one: through a jump, or through a branch whose condition the model knows, which is then
written as a jump (so a text literal, whose room is chosen by a branch on its length, is known whole). A register is known when it holds a
constant (a register written once, by a constant, anywhere in the function) or what a known instruction computed;
an object stays known as long as everything that touches it is known. A call whose arguments are all known runs in
the compiler's interpreter of the low representation (`machine.spite`), instruction by instruction, with the
machine's own semantics: the same wrapping and the same checks for whole numbers, the same IEEE operations for
decimals, the C library's own functions for the maths, every allocation zeroed as `HeapAlloc` zeroes it, and a
copy of bytes from a constant text or from another known object (pointers it copies stay pointers when they sit
on whole words). Then:

- when the call changed none of the objects that existed before it, its answer replaces it, and the objects it
  made are written out as allocations and stores (a pointer to another of them becomes its register, a pointer to
  a text the address of that text);
- when it changed objects the block made, and nothing else, the call stays, and the block goes on knowing what the
  call left in them, so `"cactus"` built by its `append_code` calls is known when `pluralize` is called on it.

When it does not apply: the call, or anything it calls, reads or writes a singleton or any memory the block did
not make, calls the system or another library (anything but the maths functions), takes a frame's address, starts
or joins a thread, waits, would halt (an arithmetic check, a `crash`, a division by zero, a call of a crash's
cold report), answers not-a-number,
runs past two million instructions (twenty million for each of the two runs), or leaves an object it made held by
nothing; and an object the block made stops being known as soon as it is passed to something that is not run, so
nothing an unknown function could have written is ever read. The call is then left as it was. A call that failed
once on the same numbers is not tried again. A function is not ruled out ahead of time for what only its paths
that halt or let go of an object could do (a cold crash report, `_release` and the free functions, which may close
a handle): those are refused when a run reaches them, not because the function could reach them.

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

## A count taken and let go with nothing between is never taken

A `retain` of an object followed, on the only path from it, by a release of the same object (through any copy of
the register that holds it) with nothing in between that can let any object go is removed together with that
release: the count would only have gone up by one and down by one. Nothing in between may call a function, free
memory, release another object, or read or write a count (offset 8 of an object). The path may leave its block
through jumps and through branches whose other side can only stop the program (a failed `crash` or a halted
arithmetic check, with no release on the way), as long as every block it enters has no other way in. The pairs are
found from the last `retain` of a block backwards, again and again, so a count taken twice and let go twice goes
in two rounds, and a pair inside another pair is removed before the outer one.

**When it applies:** to what the lowering counts for a moment: an item read from a list into a row and let go when
the row goes, an argument counted for a call that was inlined, a singleton answered by a function and let go after
one read. With a [row placed in registers](#objects-that-never-leave-their-function-live-in-registers-or-the-frame),
the row's attributes are let go where its count reaches zero, so the item's count and its release meet in one path
and both go.

**When it does not apply:** across any call that is not inlined, across a release of another object (that one could
be the same object, and its release the last but for ours), across a loop's head or any block two paths enter, and
in a function that waits.

**What a program can observe:** nothing but time. `drop()` runs at the same moment, since the count removed was
never the one that reached zero.

```spite
func ticks(positions: Vector<Position>, velocities: Vector<Velocity>) {
    var index = 0
    while index < positions.count() {
        crash velocities[index]
        var moving = {position: positions[index], velocity: velocities[index]}
        mover.advance(moving, 2)
        index = index + 1
    }
}
```

The row is registers, `advance` is inlined, and neither the position nor the velocity is counted: the loop reads
both, moves the position and goes on (`reading_through_a_type_without_counting` went from 0.77 s to 0.12 s).

## A branch its predecessor decides goes straight to its side

A jump, or one side of a branch, that leads to a block which only computes a condition and branches on it goes
straight to the side that block would take, when what the jumping block leaves is enough to decide it: a constant it
wrote last (`missing = 0`), a copy of one, or, on a branch's side, the branch's own condition (false on the false
side; true on the true side when the condition is a comparison). The block jumped over may compute constants,
copies and comparisons that nothing outside it reads, and release a register that is known to be null there.

```spite
crash velocities[index]
```

reads the item, and when the index is out of range writes `0` and jumps to the test of `0 != 0`: that path now goes
straight to the report, so the test is entered only from the path that read an item, and the item's count can meet
its release ([counted pairs](#a-count-taken-and-let-go-with-nothing-between-is-never-taken)). A counted loop's first
test of a constant start (`index = 0`, `index < 200`) is decided the same way.

**What a program can observe:** nothing but time.

## Jumps to jumps go straight to the end

A jump or branch to a block that only jumps on goes to where that block jumps (through at most 16 such blocks),
and a branch whose two targets are the same block is a jump.

## A copy of a value that never changes is the value

A copy `t = s`, where `t` is written only by that copy and `s` is a parameter never written or a register written
once earlier in the same block (with no read of `t` in between), is removed by reading `s` wherever `t` is read. So
is a copy whose every read is later in its own block, with nothing writing `s` before the last of them, whatever
writes `s` elsewhere: `r5 = angle; r9 = r5 + step` reads `angle` itself. Copy propagation runs once more after
[attributes are put in registers](#an-attribute-a-loop-updates-lives-in-a-register-until-the-loop-ends), whose reads
are such copies, and [copy coalescing](#a-value-computed-only-to-be-copied-is-computed-in-place) also moves decimal maths and
conversions into the register they are copied to.

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
The sharing runs again after [what a loop does not change is computed before
it](#what-a-loop-does-not-change-is-computed-before-it), so two loads of one singleton's slot moved out of a loop
from two inlined calls are one register, not two.

It does not apply to checked arithmetic, a division or a comparison (which is better made again just before the
branch that reads its flags), nor across blocks to a register written more than once or in a function of more than
400 blocks. A load the compiler knows never changes (see [a singleton the entry class makes is never tested
again](#a-singleton-the-entry-class-makes-is-never-tested-again)) is not forgotten at a write of memory or a call.

## A value stored is read back from its register

A store `[a + k] = v` stands, for what follows, for a load of the same width and offset from the same `a`: a load
that repeats it, with no write of memory, call or allocation in between and neither `a` nor `v` written again, copies
`v` instead, in a block and across blocks under the same rules as a repeated load. A 64-bit store stands for both a
signed and an unsigned load; a 32-bit store only when `v` is known to fit what the load would give back: a checked
32-bit addition or subtraction of that signedness, a 32-bit load of that signedness, or a constant in range.

```spite
var running = 0

func add_attribute(attribute: Spite.Attribute) {
    if attribute.class == Integer {
        running = running + attribute.value
    }
}
```

Unrolled over the four attributes of a `Stats`, the sum is four additions in registers, each stored, instead of a
chain where every addition waited for the store before it to come back from memory
(`reflection_on_constants_folds_and_unrolls` went from 110 ms to 34 ms, with the next section).

**What a program can observe:** only the time. Every store is still made, so another thread or a later read sees
the same memory.

## An attribute a loop updates lives in a register until the loop ends

Every load and store of an attribute through an object whose class is known exactly where it is read (not a union,
a shape or a type parameter) carries the attribute it reads, its region (`Tally.total`; `--low-ir` prints it as
`in Tally.total`). Two regions never share memory: an object has one class, and two attributes of one class have
their own slots, so a store to `Tally.calls` cannot change what a load of `Tally.total` or `Counter.rounds` reads,
whichever objects the registers hold. A load or store the compiler wrote itself (a count, a list's buffer, a
singleton's lock) carries no region and may touch anything, except a list's count and buffer and a buffer's
storage, which carry the regions `List_of_Float._length`, `List_of_Float._buffer` and `Buffer.$storage`, and an
item of a list or vector of numbers, which carries the region of its class's items (`List_of_Float.[]`): items live
in a buffer's storage, never in an object's slots.

A loop in which every memory access carries a region, and which makes no call, allocation or other write of memory,
keeps each region it stores to in a register when all its accesses go through one register written before the loop
at one offset: the attribute is loaded once before the loop, each read inside is the register, each store writes
the register (narrowed to the attribute's width when the value might not fit it), and it is stored once at each
way out of the loop. It applies when the object is known to be there before the loop runs (the register is the
slot of a singleton made at start, the loop's first block reads through it, or nothing in the loop tests it) and
every way out leads only from the loop or only stops the program. In a program with threads it applies only to the
attributes of a singleton that takes its lock, since those are only touched while the lock is held, and to the
attributes of a class [no other thread touches](#an-attribute-a-loop-only-reads-is-read-before-it); any other
object's attribute is still loaded and stored on every pass. The regions a loop only reads are read once before it,
by the same rule.

```spite
func advance() {
    var step = 0
    while step < 1000 {
        angle = angle + speed * 0.001
        if angle > 6.28318 {
            angle = angle - 6.28318
            turns = turns + 1
        }
        step = step + 1
    }
}
```

`angle` and `turns` live in registers for the thousand passes (`angle` in a decimal register), `speed` is read once
before the loop, and `angle` and `turns` are written once, after it, also when `advance` runs in a
[band](#a-loop-whose-passes-write-only-their-own-item-runs-in-bands).

```spite
func add(amount: Integer) {
    total = total + amount
    calls = calls + 1
    if amount > largest {
        largest = amount
    }
}
```

Called from a counted loop that [holds `Tally`'s lock](#a-counted-loop-of-calls-to-one-singleton-takes-its-lock-once),
`total`, `calls` and `largest` live in registers for the whole loop and are stored once when it ends
(`a_counted_loop_of_calls_to_one_singleton_takes_its_lock_once` went from 42 ms to 22 ms,
`thread_safety_for_singletons_the_cheapest_safe_form` from 8.4 ms to 2.1 ms).

**What a program can observe:** only the time. A loop that stops the program halfway (a crash, an addition that does
not fit) leaves the attribute as it was before the loop, which nothing can read afterwards.

## A block nothing reaches leads nowhere

A block no path from the function's start reaches (an empty block left after a branch was decided, the making of a
singleton proven made) has no successors for the passes that follow blocks and for the register allocator: it is
no loop's back edge, it makes no value live, and it is not counted as a way into the block after it. Before, such a
block falling into a loop's body hid the loop from [what a loop does not change is computed
before it](#what-a-loop-does-not-change-is-computed-before-it), cut the values [shared across
blocks](#the-same-computation-in-a-block-is-made-once), and, laid out after the function's end and falling back
into the middle, made every value live into its successor live to the end of the function and counted every block
between as one loop deeper, so values that fit in registers were spilled. **What a program can observe:** only the
time.

## What a loop does not change is computed before it

A loop is found from each jump back to a block that dominates it. When the loop is entered from exactly one block
that only goes on to it, an instruction in the loop is moved to the end of that block when every register it reads
is written only outside the loop (or by an instruction already moved), it writes a register nothing else writes,
and it is a constant, an unchecked arithmetic, a copy, a decimal arithmetic or conversion, or an address. A load
moves too when it is in the loop's first block (which every pass runs) and nothing in the loop writes memory or calls
(a retain only blocks a load of the count), and an attribute's load under the wider rule of
[an attribute a loop only reads](#an-attribute-a-loop-only-reads-is-read-before-it). Each instruction moved runs once
instead of once per pass. A block no path from the function's start reaches is no part of any loop.

It does not apply to a function of more than 400 blocks or that waits, to checked arithmetic, divisions and
comparisons, nor to a load past the loop's first block that is not an attribute's, since a pass that leaves early
would not have made it. In a program with threads a load without a region never moves: another thread may write
what it reads, and a loop waiting for that write (`while not gate.is_open() { }`) would never see it and spin
forever; a load with a region moves only under the rule of
[an attribute a loop only reads](#an-attribute-a-loop-only-reads-is-read-before-it). A load the compiler knows never
changes and can always be made (the slot of a singleton made at start, an attribute of a steady one) moves from any
block of the loop, whatever the loop writes or calls.

## A remainder by a power of two tested against zero is a mask

`x % 2^k` read only by `== 0` or `!= 0` is `x` with its low `k` bits kept (`and`), signed or not: a whole number is
divisible by `2^k` exactly when those bits are zero. `if index % 2 == 0` is a `test`.

## An if that only adds or picks a value has no branch

An `if` with no `else` whose body only adds to (or takes from) a running number, or sets a variable to a value,
is run without a jump: the test becomes a mask of all ones or all zeros, the amount added is cut by the mask, and a
value picked is mixed in through it (`kept xor ((picked xor kept) and mask)`). A test the processor cannot guess
(`if point.down >= round` over points in no order) then costs nothing when it is wrong.

**When it applies:** to a body of at most twelve instructions reached only from its test, that only computes
(numbers, copies, loads through an object or address the code before the test already read), whose every checked
addition or subtraction adds to the variable it updates, and whose test is a comparison. A body that calls, stores,
divides, makes or lets go of anything, or that the test guards from a fault (a load through what the test checks),
keeps its jump, and so does a function that computes with decimals.

**What a program can observe:** only time. The body's sums still halt on overflow exactly when they would have:
an addition the test skips adds 0.

```spite
var biggest = 0
var index = 0
while index < 4 {
    var weighted = remainders[index] * weights[index]
    if weighted > biggest {
        biggest = weighted
    }
    index = index + 1
}
```

`biggest` is picked through the mask, with no jump.

## Blocks are laid out along the likely path

The generator writes a function's blocks in the order of their likely path rather than in the order the lowering
made them: after a block comes the block it jumps to, or the true side of its branch, and the false side is written
once the path that went the other way ends. A loop's exit comes after its body, and the body of an inlined call
right after its call. A jump to the block written next costs nothing, and a branch whose true side comes next is
inverted.

## Values live in registers

Every value of a function that does not wait lives in a machine register when one is free, and in its frame slot
otherwise. Liveness is found over the blocks (a value live into a block is live at the end of every block that
leads there, up to the blocks that write it), and each value lives in the stretches of the layout where it is
live: in each block, from the block's start (or its first write there) to the block's end (or its last read
there). A linear scan takes the values in the order they start and gives each a register that no value holding it
is live in any of the same stretches, so two values share a register in each other's gaps: a value read only in a
release or a report laid out after the loop does not hold its register through the loop's body.

- The registers given are the seven the Windows x64 calling convention keeps across calls (`rbx`, `rsi`, `rdi`,
  `r12` to `r15`), saved in the frame by a function that uses them and restored at each return, and `r10` for a
  value none of whose stretches holds a call or any instruction that may call (an allocation, a checked or dividing
  arithmetic, whose crash report calls the console). `rax`, `rcx`, `rdx`, `r8`, `r9` and `r11` stay the scratch
  registers instructions work in.
- When no register is free, the value whose uses weigh least for how long it lives is spilled (of the new value
  and each value that is alone in the way on a register): each use or write weighs 32 to the power of how many loops
  hold it (at most 4), and the weight is divided by the number of instructions its stretches cover (plus eight). A
  value made and read at once keeps its register; one that lives across a whole loop and is read once in it goes to
  its slot, where each read is one load.
- A spilled value lives in its frame slot for its whole life.

What a user can observe: nothing but time; a crash report reads its numbers from wherever the values live.

## A decimal lives in a decimal register

A `Float` or `Double` value of a function that does not wait lives in one of the processor's decimal registers
(`xmm3` to `xmm15`) when every instruction that writes it and every one that reads it is decimal maths, a decimal
comparison or conversion, a copy, a constant, a load, a store, a call's argument or answer, or a return (a
parameter too: it is moved into its decimal register as the function starts). Decimal
maths then works on those registers directly (`addss xmm6, xmm7`), with no move through a whole-number register
on either side. `xmm3` to `xmm5` hold a value whose interval holds no call (nor anything that may call); `xmm6` to
`xmm15`, which the Windows x64 calling convention keeps across calls, are saved whole (16 bytes) in the frame by a
function that uses them and restored at each return. A value used anywhere else (a parameter, an operand of
whole-number maths or of an address, a branch's condition) keeps a whole-number register or its frame slot, as do
the values left over when the decimal registers run out; a value read where a whole number is needed (a store, an
argument) is moved there at that point.

A decimal constant read only by decimal maths is a value of its own in a decimal register rather than an immediate
moved in at each use, and [a loop](#what-a-loop-does-not-change-is-computed-before-it) makes it once, before it
starts. A decimal comparison (`<`, `<=`, `>`, `>=`) read only by the branch after it is the branch: `ucomiss` and a
jump on its flags (a comparison with a NaN is false on either side, as unordered compares jump neither `ja` nor
`jae`). `==` and `!=` still make their answer, since they read the parity flag too.

```spite
func scaled_sum(values: List<Float>, shift: Float): Float {
    var total: Float = 0.0
    var index = 0
    while index < values.count() {
        total = total + (values[index] + shift) * 1.5 + 0.25
        index = index + 1
    }
    return total
}
```

`total` lives in a decimal register for the whole loop: each pass is two additions and a multiplication on decimal
registers, and the item is moved in once.

**What a program can observe:** nothing but time; a crash report reads a decimal from wherever it lives.

**Not built:** a load or store of a decimal straight between memory and its decimal register (it passes through
`rax`), and a decimal constant read from the program's data.

## A bound a signed test already proved is not tested again

A read or write of a list's item tests its index against the count unsigned (`index < count` with both read as
unsigned, so a negative index fails too). When that test comes on the true side of a signed `index < count` of the
same two values (the loop's own test, `while index < values.count()`), with nothing writing either value in between,
and the index is never negative, the test is always true and is left out: the read goes straight to the item. The
index is never negative when every write of it is a constant of zero or more, a copy of such a value, or the sum of
two such values that cannot wrap (checked, or proven not to overflow; the library's wrapping sums do not count). A
signed `index >= 0` or `index < 0` of such an index is decided too (a `List.set_at`'s own check).

```spite
func add_up(values: List<Float>): Float {
    var total = 0.0
    var index = 0
    while index < values.count() {
        total = total + values[index]
        index = index + 1
    }
    return total
}
```

`values[index]` compiles to the load alone: the loop's test already proved the index is inside the list.

**What a program can observe:** nothing but time; an index the tests cannot prove is still tested and still halts
with the same report.

## An attribute a loop only reads is read before it

[What a loop does not change](#what-a-loop-does-not-change-is-computed-before-it) moves a load without a region out
of a loop only when nothing in the loop writes memory. A load with a
[region](#an-attribute-a-loop-updates-lives-in-a-register-until-the-loop-ends) moves when every write in the loop is
a store with a region and none of them is to the load's own region: two regions never share memory, so a loop whose
only writes are items of numbers (`into[index] = from[index] * 1.5 + offset`) still reads its lists' counts and
storages once, before it starts.

Such a load moves from any block that every pass runs through (one that dominates the jump back), not only the
loop's first block, when nothing in the loop tests the object it reads from: the object then holds the same value,
and is valid, on every path into the loop, so reading it a pass early cannot fail where the loop would not have. A
loop that tests the object (`if holder != null`, a `crash` on it) keeps the load where it is.

In a program with threads, a region of a class that work on another thread may touch keeps its load in the loop,
whatever the loop writes: a loop waiting for another thread (`while station.pumped() < 1000`) must see each new
value. Such a class is one with a function that a `Parallel` reaches by any chain of calls, or whose attribute such a
function reads or writes; the passes of a loop that
[runs in bands](#a-loop-whose-passes-write-only-their-own-item-runs-in-bands) do not count, since each band touches
only its own elements.

**What a program can observe:** nothing but time.

## Loops and functions start on a 16-byte boundary

The generator pads with no-operation instructions (of up to eight bytes each) so that every function starts at an
address that is a multiple of 16, and every block a later block jumps back to (a loop's head) at a multiple of 32,
the width the processor fetches each cycle: a loop's first 32 bytes are one fetch, whatever comes before it. A loop's body is then
fetched and decoded the same way whatever code comes before it, so a change elsewhere in a program no longer moves
a hot loop across a fetch boundary and changes its time. The padding before a loop head runs once each time the loop
is entered from above. **What a program can observe:** the time, and an executable a few bytes larger per loop.

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

## An unchecked 32-bit sum is one instruction

A 32-bit `+` or `-` the compiler has proven cannot overflow (`index = index + 1` under `while index < count`), and a
32-bit bit operation (`&`, `|`, `^`) of signed numbers, is computed in place in its target's register in 64 bits,
with no sign extension after it: a 32-bit number is held sign-extended (or zero-extended, unsigned), and the 64-bit
sum of two such numbers whose true sum fits in 32 bits is already that same extended number, as is any bit operation
of two sign-extended numbers. The library's wrapping sums (`_wrapping_sum`) are left alone, since they may wrap.

**What a program can observe:** nothing but time.

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

## A serializer's keys are folded into its code

A `JsonWriter` or `JsonReader` given a `keys` map written out where it is set
(`writer.keys = {MeshRecord.attributes['minimum_level_of_detail']: "min_lod"}`) holds no lookup at run time: each
attribute's copy of `write_attribute` and `read_attribute` reads `keys[attribute]` as the text the map gives it, or
as `null` for an attribute the map leaves out, and the copy of an attribute without a key never names the map. The
map itself is still made, and the serializer checks only that it is not empty, so a serializer of the same class
made without a map writes and reads the attributes' own names. Every map set on the same serializer class must be the
same, set before the serializer is compiled, and never changed through an index; otherwise the program does not
compile. What a user can observe: nothing but the keys.

## A type crosses into C as its struct, in the frame

A `type` passed to a foreign function is laid out as the C struct of its attributes, in a room of the calling
function's frame (on the heap in a function that waits, freed after the call), with each attribute at its C
alignment; the call passes the room's address, and C's writes are copied back into the object's attributes when it
returns. A list of numbers passes the address of its own storage, so C reads and writes the elements in place. A
text answer (`_as_text`) is copied into a new `String`; a null pointer stops the program naming the function. What a
user can observe: none of it allocates in an ordinary function, and the object C changed holds C's values after the
call.

## The scheduler is written only for a program that makes work

The scheduler, the handle's functions and the table of calls in a row are low functions the compiler writes,
only when the program makes a `Concurrent` or a `Parallel`; a program that makes neither carries none of them,
not even an import. The table that bounds calls in a row (eight unfinished per site) is sized while compiling,
nine slots for each site the program has plus one, so it never grows; a program without such a site has no table.
A thread's loop is found by its id: the program's first thread compares one word, and only another thread takes
the lock that guards the list of loops.

    var first = Concurrent(slow_read)
    var answer: Integer = first

writes `_scheduler_start` and `_scheduler_wait_for` for this program, and `Spite.Work_of_Integer._settled` for the
join; `--low-ir` shows them.

## A singleton is made on first use, by a function of its own

A read of a singleton is a load of its slot and a test that it is made; making it (the claim of the slot, the wait
for another thread making it, the constructor, the record for its `drop()` at exit) is a function of its own,
`_make_<Class>$<slot>`, written once for each singleton and called only when the slot is empty. A function that
reads a singleton is then small enough to be [inlined](#small-functions-are-inlined), and with the singleton's
attribute [read in place](#attributes-nothing-writes-are-rebuilt-where-read) an object that held it holds nothing
but its numbers, so it lives in registers.

```spite
var rules = Rules()
var number = 0

func weight(): Integer {
    return number % 7 + rules.base
}
```

A loop that makes a `Visit` and asks its `weight()` makes no object, counts nothing and calls nothing once `Rules`
is made (`singletons_made_on_first_use_never_counted` went from 0.53 s to 0.016 s on two threads).

**What a program can observe:** nothing but time. A singleton read through an attribute is made at its first read
instead of when the object holding it is made, which nothing tells apart, since making it does nothing a program
sees; `--debug-memory` counts the same allocations. A fault while making it reports as before.

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
   does not fit halts before anything is written and no two threads lose an update. A singleton a counted loop in
   the work would [hold for the whole loop](#a-counted-loop-of-calls-to-one-singleton-takes-its-lock-once) takes
   the third form instead.
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
functions answering a number, a `Boolean`, an enum or nothing, or to a helper of a class that is not a singleton
which answers one of those and calls nothing, makes nothing, has no loop and calls nothing in C (a `weight_of(index)`
that only computes: `singletons_a_parallel_reaches_take_a_lock` went from 18 ms to 5.9 ms), and nothing in it but
local `var`s and assignments
of plain values, `if`s, plain `crash`es and arithmetic. None of the singleton's functions it calls, nor anything

functions answering a number, a `Boolean`, an enum, nothing, or an object of a class that holds only such values
and has no `drop()`, and nothing in it but local `var`s and assignments of those values, reads of their number
attributes, `if`s, plain `crash`es and arithmetic. Letting go of such an object while the lock is held frees its
memory and runs nothing of the program, so `var transform = transforms.at(row)` followed by
`total = total + transform.across` holds `Transforms`' lock once for the loop, and the inlined `at$unguarded`
reads the item with no count (`a_singletons_reading_functions_do_not_exclude_each_other`, eight `Parallel`s reading
one `Transforms`: 136 ms before, 6.7 ms after). None of the singleton's functions it calls, nor anything
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

A call in the loop to a singleton that takes no lock (one that never changes after it is made, or that no thread
reaches) does not count as a second singleton, so a loop may read settings from one singleton while it updates
another. And a singleton that would be made safe with [atomics](#thread-safety-for-singletons-the-cheapest-safe-form)
is given its lock instead when a counted loop in the work a `Parallel` runs would hold it: one lock taken per loop
costs less than one compare-exchange per call. In `thread_safety_for_singletons_the_cheapest_safe_form` each of the
four workers adds `settings.step_size()` into `counter.record()` a million times; `HitCounter` was updated with a
compare-exchange on every call, four threads fighting over one cache line (144 ms); now each worker takes its lock
once and adds with plain loads and stores (8.4 ms).

**Not built:** a loop that is not counted testing the task count once before it starts.

## A counted loop of reads shares its singleton's lock

A counted loop that [holds a singleton's lock](#a-counted-loop-of-calls-to-one-singleton-takes-its-lock-once) and
calls only functions of it that write none of its state (no attribute of the singleton, of a class it reaches
through its attributes or their type parameters, nor their items, followed through every call they make and every
`drop()`; a write on a path that ends the program, such as the report a failed `crash` builds, does not count) and
reach no other locked function holds the lock shared: it adds one to the singleton's count of readers, and
when no thread owns the lock it runs, or it takes the one back and retries after giving the processor up. The
readers of one singleton then run at once, each loop on its own thread. A function that takes the lock to change
the singleton claims it as before and then waits until no reader is left, so a reader never sees it half-way
through a change and a change never runs beside a reader. A thread that already owns the lock (a reading loop
inside one of its changing calls) takes it again as the owner. The count of readers is a word of the singleton's
slot, and only a singleton some such loop reads makes its changing functions wait for it.

```spite
func run(): Integer {
    var total = 0
    var row = 0
    while row < rows {
        var transform = transforms.at(row)
        total = total + transform.across
        row = row + 1
    }
    return total
}
```

Eight `Parallel`s running `run` read `Transforms` together; `insert`, called between ticks, waits for them
(`a_singletons_reading_functions_do_not_exclude_each_other`).

**What a program can observe:** only the time: readers run in an order they could already run in, and nothing they
read changes while they run. **When it does not apply:** a loop that calls a function writing anything, or one
reaching another lock, takes the lock alone; a single call outside such a loop takes it alone too.

## A loop whose passes write only their own item runs in bands

`orbits.each_advance()` on a `List` of a class of the program runs on several threads at once, one band of the
list for each processor, when every pass writes only its own element: the compiler reads `advance` (and every
function of the class it calls) and finds that it writes only number attributes of the element and its own locals,
reads only number attributes of the element, its locals and literals, and calls only functions of the class that
take and answer numbers. Nothing else may appear in it: no member call, no index, no text, no object made, no
`crash`, no `switch`. It is `parallel_each_` without writing it: the
compiler proves what that form asks the programmer to keep true, and when it cannot, the loop is the loop as written
(`high_intermediary_representation/building/banded_loops.spite`, the library's `List._each_in_bands_member`).

```spite
var angle = 0.0
var speed = 0.0
var turns = 0

func Orbit(seed: Integer) {
    speed = seed % 17 + 1
}

func advance() {
    var step = 0
    while step < 1000 {
        angle = angle + speed * 0.001
        if angle > 6.28318 {
            angle = angle - 6.28318
            turns = turns + 1
        }
        step = step + 1
    }
}
```

`orbits.each_advance()` over 100 000 orbits cuts them into one band per processor; the program's own thread runs the
first band and waits for the others, so whatever comes after the loop (`orbits.sum_turns()`) runs after every pass,
as written.

**When it pays.** Starting a band costs a thread, so the compiler weighs the pass while compiling: each statement 1,
a loop's body times its bound (the literal it is counted to, or 8), a call what its function weighs. A pass that
weighs less than 256 never runs in bands (it is bound by memory, not by the processor). For a heavier pass the
compiler writes the smallest count at which the bands pay, the count times the weight reaching a million; the loop
compares the list's count with it when it starts and runs in order below it.

**Why some of it is at run time.** A list may hold one object twice, and two bands would then write it at once, so
above that count the loop first reads each element's reference count (one load per element) and runs in order when
any element is held anywhere else too. How many processors there are (`GetActiveProcessorCount`, at most 64), how
many elements the list holds and who else holds them are known only when the loop runs; which functions qualify,
what they weigh and the count they need are decided while compiling. A program with no such loop carries none of
it.

**What a program can observe:** the time, and the same output. A pass whose checked arithmetic overflows still
halts the program with the same message, but the frames it reports are those of its band (the function the band
runs and the library's `_each_range_` loop), and when several passes would overflow, the one reported may be another
than the first in the list's order. Not in `--hot-reload`, `--repl` or `--development` builds.

## A counted loop of one banded pass runs its count inside each band

```spite
func advance_ticks() {
    var tick = 0
    while tick < 10 {
        orbits.each_advance()
        tick = tick + 1
    }
}
```

A `while` whose body is only a call that [runs in bands](#a-loop-whose-passes-write-only-their-own-item-runs-in-bands)
and the step of its counter (an `Integer` counted by one up to a literal) starts the bands once: each band runs all
ten passes of its own elements, one element after another, and the counter ends at the bound, as the loop would
leave it. It is built as an `if tick < 10` that runs the passes `10 - tick` times and then sets `tick = 10`
(`high_intermediary_representation/building/statements.spite`, the library's `List._each_in_bands_repeated_member`).
Each pass writes only its own element and reads nothing another pass writes, so an element's ten passes in a row
leave every element as ten rounds over the list would. Below the count at which bands pay, or when an element is
held elsewhere too, the rounds run over the whole list one after another, as written.

**What a program can observe:** the time; a checked operation that overflows reports its band's frames, as in any
band.

## A singleton the entry class makes is never tested again

The entry class's attribute defaults run before any other code of the program: a singleton they make on every path
(`var counter = HitCounter()` in the entry file) is made before the entry function starts. Every function that
cannot run before those defaults end reads such a singleton's slot without testing that it is made, and the load of
the slot is known never to change, so it moves out of loops and is shared across calls and writes. When the
singleton never changes after it is made (no function but its constructor assigns its attributes), the loads of its
attributes are known never to change too.

The functions that may run before the defaults end are found by following calls and function addresses from what
the program's start calls up to and including the defaults, the fault handler and every singleton's destroy at
exit; any function one of them reaches keeps every test. A function value is called only through an address taken
by code that ran before, so following the addresses taken is enough.

```spite
var counter = HitCounter()
var settings = Settings()

func ThreadSafetyForSingletonsTheCheapestSafeForm() {
    var rounds = count_on_four(1000000)
    var name = settings.name()
    var total = counter.total()
    console.print(name, total, "after", rounds, "rounds")
}
```

`Worker.run`, which reads `settings` and `counter` a million times on each of four threads, tests neither: the
loop reads the step once before it starts and finds the counter's slot once.

**When it does not apply:** a singleton made only by some paths of the defaults, or not by the entry class at all
(then [made on first use](#a-singleton-is-made-on-first-use-by-a-function-of-its-own) as before), and every function
the defaults, the fault handler or a destroy can reach. **What a program can observe:** only the time.

A quiet singleton (its defaults and constructor only assign its own attributes from pure values, in a program with
no `drop()`) read in a loop is tested once before the loop instead: making it earlier cannot be seen, and once made
its slot never changes, so the loop reads the slot once. This is not done in a `--debug-memory` build, where making
a singleton a loop that never runs would have made counts one more allocation (`singletons_made_on_first_use_never_counted`
went from 15.5 ms to 13.9 ms).

## A chain of `filter_` steps runs as one loop

`lamps.filter_is_lit().sum_brightness()` makes no list in between: when a `List`'s member template is called on
the answer of a `filter_` template (or of a chain of them), the compiler writes one function on the first list's
class, `_fused_is_lit_then_sum_brightness`, from the last template's body with its loop's step wrapped in an `if`
per `filter_`, and calls that on the first list (`high_intermediary_representation/building/fused_chains.spite`).
The last step may be `filter_`, `count_`, `any_`, `all_`, `sum_`, `each_`, `map_` or `find_by_`. A `map_` may
stand in the middle too: `items.filter_is_active().map_owners().filter_is_adult().sum_age()` is one loop over
`items`, `_fused_is_active_to_owner_is_adult_then_sum_age`, that names each item's owner in the loop
(`var item = fused_item_0.owner`) and filters and sums it there, with no list of owners made. After a `map_` the
last step is `count_`, `any_`, `all_`, `sum_`, `each_` or `map_` (a `filter_` or `find_by_` there answers the mapped
class, so it runs on its own list). A program sees only the order: each element's members run before the next
element's.

```spite
var total = lamps.filter_is_lit().sum_brightness()
```

calls `is_lit` then `brightness` on the first lamp, then on the second (`tests/list_chain_order`), and allocates no
list for the filtered lamps.

Measured on `template_chains_run_as_one_loop`: 102 ms before the `map_` joined the loop, 35 ms after.

**Not built:** a `filter_` or `find_by_` after a `map_`, a passed function (`filter(f)`), chains on a
`Dictionary`'s values, on a `Vector` or on `Items`, and leaving out the unfused step's own function, which is still
compiled.

## A list of lists cleared and filled with new lists keeps their room

```spite
func group() {
    buckets.clear()
    var made = 0
    while made < 32768 {
        var bucket = List<Order>()
        buckets.append(bucket)
        made = made + 1
    }
}
```

A `clear()` of a list of lists followed by a counted loop (the counter a whole number, or declared just before the
loop from a literal, counted by one up to a literal) whose body only makes a new empty list of the item class and
appends it is one call, `List._renew_lists(wanted)` (`high_intermediary_representation/building/statements.spite`,
the library's `common/list.spite`): every item only this list holds is emptied in place and kept, its storage with
it, in the slot the loop would have filled with a new list; an item held anywhere else is replaced by a new list,
and the items past `wanted` are let go. The loop then appends nothing more than it would have, and its counter
ends at the bound. The next fill appends into lists that already have the room they grew to, so no list is made,
grown or freed again. It is built as `if made < 32768 { ... } else { buckets.clear() }`, so a loop that would not
run leaves the list cleared, as written.

**When it does not apply:** anything else between the `clear()` and the loop (but a `var` of a literal), a loop
that does more than make and append, a list made with arguments or of another class than the items, a list of a
union or a shape. **What a program can observe:** the time, and fewer allocations under `--debug-memory`. An item
is let go at the same moment as before (the items of each emptied list in order, then the items past `wanted`), so
every `drop()` runs in the same order; nothing else holds an item that is kept, so nothing can tell it from a new
one. Measured on `a_list_of_lists_filled_again_keeps_each_lists_room`.

## An object let go before anything reads it is never made

```spite
func run(entity_count: Integer) {
    var entity = 0
    while entity < entity_count {
        var row: $row_type = null
        fill_attributes(row, entity)
        system.update_each(row)
        entity = entity + 1
    }
}
```

A row made with `null` holds a new object for each attribute of a class (`Entity()`, `Position()`, ...) until
something assigns it; once `fill_attributes` is inlined and the row lives in registers, each of those objects is
made, put in the row's register, and let go when the fill replaces it, with nothing reading it in between. Such an
object is never made: its register holds null instead, and the release that would have freed it finds null and
does nothing (`low_optimization_passes/unread_objects/pass.spite`).

**When it applies:** to an object whose class frees nothing but its own memory (no `drop()`, no attribute it lets
go), when every register that may hold it, along every path from where it is made, is only copied, retained,
tested for null by a release, counted down and freed by that release, or passed to `_release`, and nothing but its
class and count is written into it. A read of any attribute, a store of it anywhere, a comparison with anything
but null, a call that is passed it, or an answer of it keeps it made. **What a program can observe:** fewer
allocations under `--debug-memory`, and time.

## An object that outlives the function is not counted in it

```spite
func fill_position(row: $row_type, rows: List<Integer>) {
    row.position = Column<Position>().values[rows[1]]
}
```

A singleton the entry class makes is read from its slot with a load the compiler knows never changes (see [a
singleton the entry class makes is never tested
again](#a-singleton-the-entry-class-makes-is-never-tested-again)); so is an attribute of one that never changes.
What such a load answers is held by the slot or the singleton for the whole run, so a function that keeps it in a
local need not count it: every retain of the register (and of its copies) and every release of it are left out
together, and the release's test for null jumps straight past it (`low_optimization_passes/unread_objects/pass.spite`).
`Column<Position>()` read once per entity in a loop costs a load, not a count up and a count down.

**When it applies:** when every register holding the value is written only by that load or by copies of it, and
nothing but a retain, a release, a copy, a comparison, a read through it, a store through it (not of its count) or
a call that is passed it uses it. Storing it, answering it, freeing it or touching its count any other way keeps
every count. **What a program can observe:** only the time. The count of a singleton never reaches zero while the
program runs, with or without these, so its `drop()` runs at the same moment.
