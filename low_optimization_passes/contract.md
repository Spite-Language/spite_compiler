# low_optimization_passes

The passes that transform the low representation, in the order `low_optimization_passes.spite` registers them.

- `low_optimization_passes.spite`: the entry, which registers each pass in its setup and runs them in order.
- `<pass>/pass.spite`: the work of a pass over one function, class `Pass`; the entry class of the pass, named for the folder, runs it over every selected function.
- `proving.spite`: `Proving(proof)`, which registers a low proof among the passes.
- `every_function.spite`: the step that selects every function again.
- `operands.spite`, `flow.spite`, `block_edges.spite`, `dominance.spite`, `register_lives.spite` and `singleton_tests.spite`: what several passes read the same way.

`../ARCHITECTURE.md#the-low-passes-in-order` says what each pass does.
