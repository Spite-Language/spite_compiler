# low_intermediary_representation

The program as functions of blocks of instructions over virtual registers, once the high passes have decided everything.

- `low_intermediary_representation.spite`: the entry, `LowIntermediaryRepresentation(high, counts_memory)`; its `run` lowers every reached function into a `lowered_program.spite`.
- `lowering`: the builder, one file per concern.
- `instructions`: one file per instruction kind.
- `vector`: the vector instructions.
- `low_function.spite` and `low_block.spite`: a function and its blocks.
- `placed_objects.spite`, `proven_tests.spite` and `register_ranges.spite`: the facts a proof records on a function; `call_frames.spite`: the frame of a call.
- `written_functions.spite`: run once the low passes end, it crashes on a call of a function the program never wrote, a fault of the compiler.

It only lowers: every decision the lowering reads was recorded by a high pass.
