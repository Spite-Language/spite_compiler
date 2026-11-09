# low_optimization_passes

The passes that transform the low representation, in the order `low_optimization_passes.spite` registers them.

- `low_optimization_passes.spite`: the entry, which registers each pass in its setup and runs them in order.
- `<pass>/<pass>.spite`: the entry of a pass, named for the folder, which the stage registers; it runs `<pass>/pass.spite`, class `Pass`, over every selected function. `folder_layout` refuses a pass folder without either. A helper only that pass reads sits beside them.
- `proving.spite`: `Proving(proof)`, which registers a low proof among the passes.
- `every_function.spite`: the step that selects every function again.
- `operands.spite`, `flow.spite`, `block_edges.spite`, `dominance.spite`, `register_lives.spite` and `singleton_tests.spite`: what several passes read the same way.
- `machine.spite` and `frame.spite`: the machine that runs low instructions while compiling, which `compile_time_evaluation` and `constant_folding` read.

`../ARCHITECTURE.md#the-low-passes-in-order` says what each pass does.

## Copies

A pass that copies an instruction (`inlining`, and `compile_time_evaluation`'s unrolling, function clones and
redirected calls) calls `copy()`, which carries every field, and gives each list field a list of its own with a walk
over the copy's attributes (`own_list`), so a field added later is copied without anyone writing it. Only what the
copy changes is written beside it: the registers inlining moves, the blocks a clone maps, the function a call is
redirected to.
