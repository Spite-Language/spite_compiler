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
