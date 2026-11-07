# lowering

The step that turns the high program into low functions: one `LowFunction` per built function, plus the functions the
compiler writes itself (the pool, the crash gate, the scheduler, the release of a class, the fault handler).

`lowering.spite` walks the program and makes a `FunctionLowering` for each function it writes. The lowering of a
function reads what the high passes decided (the layout, the waits, the ownership, the assignments) and decides nothing
of its own.

## The files of one function

The fields of a lowering live in one object, `FunctionLoweringState` (`function_lowering_state.spite`): the function being written, its
blocks, the current block, the register count, the scopes and the owned values, the frame lists and the counts of the
slots, and the singleton being locked. Every concern takes it, never the `FunctionLowering`, which would be a reference
cycle. The concerns call each other both ways, so none holds another as an attribute: a function makes the ones it
needs over the same state, as a local.

- `function_lowering.spite`: the entry. The exhaustive `switch` over the values (`lower_value`) and over the statements
  (`lower_a_statement`), the block and register primitives (`new_register`, `new_block`, `switch_to`, `emit`,
  `jump_to`, `constant`, `data_label`, `text_label`), the questions of what a type is held as (`is_a_pointer`,
  `width_of`, `storage_of`), the setup of a function (`lowered`, `start`, its parameters) and what the waits say about
  it.
- `frame_lists.spite`: the lists a frame holds and the appends of a slot.
- `counting.spite`: owned values, retain, release, and when a value is let go.
- `statements.spite`: a block and each statement: declarations, assignments, stores, `if`, `while`, `return`, stops.
- `values.spite`: numbers, texts, locals, attributes, the operations, tests of a class or a presence, and the objects
  made.
- `calls.spite`: a call and its arguments, the values that are functions, sleeps, and the calls into C.
- `singletons.spite`: making a singleton, locking and unlocking it, sharing it between readers.
- `conversions.spite`: converting a value, boxing into a shape or a maybe, calling a shape, the texts of an enum, and
  the range checks and decimal conversions.

The collaborators that write one kind of function (`working`, `settling`, `callbacks`, `list_reads`, `column_lists`,
`text_joins` and the others) take the `FunctionLowering` they write into, and reach its fields through
`lowering.state`.

## What a file may hold

No file holds more than the file content budget (`validators/abstract_syntax_tree/file_content_budget`). A concern
that grows past it is split by what it does, not cut where the count ends.
