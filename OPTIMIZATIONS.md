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
