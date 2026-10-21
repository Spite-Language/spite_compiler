# high_intermediary_representation

The program as values and control flow, once every name answers and every type is known.

## What it takes and answers

It takes the resolved classes and answers a `HighProgram`: every class the program can reach, with its
attributes and functions, every function's body as a `HighBlock` of `HighStatement`s over `HighValue`s.

## Why a second shape

The abstract syntax tree answers where a name was written. The high representation answers what the
program *is*: a value is an `Integer`, a `String` or a reference to a class; a call names the function it
reaches. Optimisation passes read the high representation because a question like "is this call ever
reached" or "does this addition always overflow" has no answer on the syntax tree.

## What is built

A subset, enough to compile a program of whole numbers that calls its own functions, uses `while` and
`if`, and returns a value. Classes hold `Integer` attributes. Nothing else is lowered yet: `String`, lists,
references, unions, reflection and concurrency are all still to come, and each needs its own value kinds
here first.

The `Builder` is the step from the syntax tree to this representation. It takes a class's `SourceFile`, the
substitution of the instance it belongs to, and the answers the name resolution gave, and answers a
`HighClass`:

- every function with a body becomes a `HighFunction` with its parameters, their types *after* the
  substitution, its result type after the substitution, and its body lowered;
- every attribute becomes a `HighAttribute`: its name, how many bytes it takes, where it sits in the
  block, and the value it is made with. The class's `block_size` is the size of the block they make;
- a line it cannot lower stops the run (`validators/high_intermediary_representation/buildable`).

The types it lowers are the whole numbers: a literal, a name, an addition or a multiplication, a
comparison, an `and` or an `or`, and a call. Everything else stops the run until it is written.

## The instance and the class

**Every function of a class takes the instance as its first argument**, and the builder writes it: the
parameters of a `HighFunction` start with `this`, the instance of the class the function belongs to. A
call on an instance passes the instance first, and a call with no receiver inside a class passes `this`.

**A class is a block of memory.** The attributes sit in it at the offsets the builder gave them, and the
size of each one is the size of its type. The size of the whole numbers is known to the compiler
(`high_intermediary_representation/sizes.spite`), and every other class is a pointer, four bytes, until
the library says how big it is.

**A call of a class's own name makes an instance.** The builder lowers it to an `Answer` whose callee and
owner are the class's name, and the lowering makes the block, writes the attributes' defaults into it, and
calls the constructor with the instance as its first argument. A class with no constructor is made from
its defaults alone.

**A call of a generic class names the instance of that class.** `List<String>()` names the instance
`List_of_String`, and the builder lowers the call to that name, for the callee and for the owner, so the
call makes an instance of the class the name resolution monomorphised. A type written with arguments
names the same instance, and the builder asks the name resolution for that one too. The constructor of an
instance is renamed to the name of the instance, because the lowering finds the constructor by the name of
the class it belongs to, and the class of an instance is the instance.

**An attribute is read and written through the instance.** A name that is an attribute of the class reads
`this.attribute` inside a function of the class, and `object.attribute` outside one. The builder lowers
both to an `Attribute` value, or to an `AssignAttribute` statement, and the lowering finds the offset in
the class's layout.

**A call on a `DynamicLibrary` is a foreign call.** The library holds the C library it opened, and the
name of the member is the name of the C function, with a suffix that says what the answer is
(`_as_long`, `_as_double`, `_as_text`). The builder lowers it to a `ForeignCall` value, whose receiver is
the library's `handle` attribute, and whose arguments are the ones the call was written with. The receiver
is not one of them: the C function does not know about the library it came from.

**Where the block lives is not decided here.** The lowering makes it in the frame of the function that
made it, which is right for an object that never leaves that function and wrong for one that does. The
decision is a proof, and each proof is a pass of its own, so the frame is the first one and the heap comes
with the runtime the library asks for.

## The owner of a call

A call names the function it reaches, and the class that owns it. The owner is what tells two functions of
one name apart: `Counter.reset` and `Timer.reset` are two functions, and a call that says only "reset" says
neither.

The `Builder` fills the owner in with what the language lets it tell:

- a call with no receiver reaches a function of the class the file declares, so the owner is that class;
- a call of a class's name makes an object, so the owner is that class;
- a call on a class's name reaches a function of that class, so the owner is that class;
- a call on an instance reaches a function of the receiver's class, and the receiver's class is the class of
  the value the receiver holds.

The class of a value comes from the type the name is declared with, or from the class a constructor call
makes, or from the name the value was copied from, or from the class a call answers. A type parameter that
is not bound names no class, and a dependent type (`x.class`) names none either.

The class a call answers is the result type of the function it reaches. The name resolution answers the
result type of every function of every class it resolves, so the builder asks it for the class a function
of another class answers. A receiver that is such a call names its owner.

A receiver the compiler cannot place names no owner: the answer of a call is not known here, so the class of
`File(path).read()` is not known either. An empty owner is not a guess and not a name: it says the compiler
does not know yet. The owner is what a pass needs to tell two functions of one name apart, and a pass that
is given an empty owner falls back to the name alone.

## The memory of a value

**The library names the memory and the compiler keeps it.** A class that holds memory holds a `Buffer`,
and says how many bytes it needs: `var _buffer = Buffer(1)`. The name resolution reads that number and
the builder lays the room out at the front of the class's block, so the first bytes of the block are the
bytes of the room. A class with a room is a value class: the room is where its value is kept.

**The value is read from the room, and not from `this`.** `this` is the place the value is kept, and never
the value itself, so a method reads its value with the buffer: `_buffer._read_byte_at(0)`. A method of a
value class is therefore made on the *address* of the value: the builder lowers the receiver of such a
call to the value itself, and the lowering finds the address of the attribute or of the place the value
is kept in.

**An argument of a value class is the address of the value, when the value is an attribute of another
object.** The block of a value class is kept inside the object that holds it, the room and the attributes
of the class with it, so an argument that is an attribute of another object is passed as the address of
that attribute, and the callee reads the room there. An argument that is a name of the class the code is
in is a plain number of that class, and it is passed as the number: the callee wants the count, not the
place the room is kept in.

**The methods that read and write a byte have no body, and the compiler writes them.** Reading a byte of
memory is not something Spite can say, so the library declares the method and the compiler writes what it
does. `high_intermediary_representation/memory.spite` holds that knowledge: the class the methods belong
to, and the two names, `_read_byte_at` and `_write_byte_at`. The builder writes the body of such a
method: a `BufferRead` value that reads the byte of the receiver at an offset, or a `BufferWrite`
statement that writes one.

**A crash and an assertion are one statement.** Both stop the program when their condition does not hold,
which is the rule of the language: a `crash` is a guard that stops the program where an `assert` stops the
function. The builder lowers both to a `Crash` statement, which carries the condition and the text the
program prints when it stops. The text names the file and the line, and the program writes it to the
standard error before it leaves.

**An index is a call to `get_at`.** `a[b]` is only a shortcut for `a.get_at(b)`, so the builder lowers it
to a call: the receiver is the value that is indexed, and the index is the argument. The class that owns
the call is the class of the value that is indexed. Writing an index is the same rule the other way
round: `a[b] = v` is a call to `a.set_at(b, v)`, and the builder lowers it to that call.

## The shapes

- `HighProgram`: the classes.
- `HighClass`: a name, its attributes, its functions, and the size of the block its instance takes.
- `HighAttribute`: a name, how many bytes it takes, where it sits in the block, and the value it is made
  with.
- `HighFunction`: a name, its parameters, their types, its result type and its body.
- `HighBlock`: a list of statements.
- `HighStatement`: a union of `Declare`, `Assign`, `AssignAttribute`, `If`, `While`, `Call`, `Crash` and
  `Return`.
- `HighValue`: a union of `Number`, `Name`, `Operation`, `Answer` (a call that answers a value) and
  `Attribute` (an attribute read through an instance).

A `Call` and an `Answer` carry the name of the function they reach and the class that owns it. The first
argument of a call is the instance it is made on: the receiver for a call on an instance, and `this` for a
call with no receiver inside a class.

An `If` holds a condition, a branch to run when it is true, and a branch to run when it is false. The
branch that is false is nothing when the program wrote no `else`.
