# name_resolution

The step that answers one question: for every name the program writes, which class, function,
attribute, parameter or local holds it.

It is the step the old compiler calls discovery and resolution together, split apart. Everything after it
needs to know what is reachable, and reachability is only knowable once a name is answered.

## What it takes and answers

It takes the `SourceFile` of every class the `symbols` step read, and answers:

- a `ResolvedType` for every type written anywhere in the program,
- a `Monomorphised` instance for every generic class the program writes with type arguments,
- the class every function of every class answers, so a receiver that is a call of another class's
  function names its class,
- the class every generic call of every class names, so the builder lowers the call to the instance.

## The rule it follows

**Every time a generic or a type is found, it is monomorphised.**

A generic class is a file with a `generic $name` line. It is a template, not a class: nothing of it is
compiled until it is written with a type. So when the resolver finds a type that names a generic class,
it does not resolve the name and move on. It *mints an instance*: a copy of that class with its type
parameter bound to the type written at the use.

`List<Integer>` mints `List_of_Integer`. `List<List<Integer>>` mints `List_of_List_of_Integer`. The
instance is cached by its class and its arguments, so the same instantiation is made once however many
times it is written.

The instance's own types are then resolved with the substitution in place, and *that* finds more generic
classes, which are monomorphised in turn. The work is a queue, and it ends when no new instance is
minted.

**A generic class written in a call is monomorphised the same way.** `List<String>()` names the instance
`List_of_String`, and the resolver publishes that name, so the builder lowers the call to the instance
and the class the call answers is the instance too. The type `List<String>` names the same instance, and
the builder asks the resolver for that one too. The name is published per class, because a template body
writes the same call once and means a different instance in every instance of the template: the
`List<$element_type>()` of the `List` template names `List_of_String` in the instance `List_of_String`
and `List_of_Integer` in the instance `List_of_Integer`.

## The rules it hands to validators

- The count of types in `<>` against a class's `generic` lines: `validators/name_resolution/generic_arguments`.
- A type parameter with no `generic` line: `validators/name_resolution/codegen_line`.
- A member of a type that is not there: `validators/name_resolution/type_member`.

A class name that reaches no file is collected and not reported yet (`TODO.md`).

## The two kinds of dependent type

A type written with two segments is a qualified class name when the first segment names a class or a
namespace, and a dependent type when it does not:

- `Spite.Access` is the class `Access` in the namespace `Spite`.
- `member.class` is the class of the value named `member`, which is a parameter of the enclosing
  function.
- `$value_type.element_type` is the element type of the type bound to `$value_type`.

The old compiler decides the same way, by looking for the owner as a class and falling back to the
member reading.

A dependent type is resolved by finding the owner's type and then the member's type in it. The
associated types of the built-in generic classes are known without a file:

| class | member | is |
| --- | --- | --- |
| `List<T>` | `element_type` | `T` |
| `Dictionary<K, V>` | `key_type` | `K` |
| `Dictionary<K, V>` | `value_type` | `V` |
| `Symbol<T>` | `value_type` | `T` |

Any other member is found in the class's own declarations.

A member read on a type parameter is a codegen value: the original compiles a generic class once and
gives the type argument at run time, so `$value_type.key_type` is the key type of whatever the argument
is, and the compiler cannot know it while it reads. Such a member is a note, not an error, and the
member is answered when the class is compiled.

## What is not built yet

- The resolver answers a *type*, not a *value*. A name that is a function, an attribute or a local is
  still not resolved, so a program cannot yet say which of its classes are reachable.
- A template that nothing instantiates is never checked. That is deliberate: the same rule as everywhere
  else in this compiler, that what is not used is not read. It does mean a broken generic class is only
  found when something writes it.

## The files

- `resolved_type.spite`: a type that has been resolved: a path, its arguments, whether it is nullable,
  and whether it is a class, a type parameter, a dependent member or a codegen value.
- `types.spite`: the builder for the above. A class cannot be called in Spite, so the ways of making
  one live here.
- `substitution.spite`: what a type parameter is bound to, and the applying of it to a type.
- `instance.spite`: a monomorphised class: where it came from, its name, the parameters it binds, the
  arguments it was given, and its substitution.
- `mangle.spite`: the name of an instance: `List_of_Integer`.
- `type_use.spite`: a type as it is written in a file, before it is resolved.
- `finder.spite`: the walk over a file that finds every type written in it, in declarations, in
  statements and in the type arguments of a call.
- `resolver.spite`: the work: find the types, resolve them, mint the instances, and mint the instances
  the instances need.
- `class_name.spite`: the class a type names: the class of a named type, of a type parameter, and of a
  type that is dependent on another.
- `answers.spite`: the class every function of every class answers.
