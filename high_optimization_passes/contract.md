# high_optimization_passes

The passes that transform the high representation, in the order `high_optimization_passes.spite` registers them.

- `high_optimization_passes.spite`: the entry, which registers each pass and proof in its setup and runs them in order.
- `<pass>/pass.spite`: one pass, class `Pass`, with `optimized(HighIntermediaryRepresentation.HighProgram)`.
- `proving.spite`: `Proving(proof)`, which registers a proof among the passes.
- `rewriting.spite` and `function_building.spite`: the two kits a pass that rewrites or builds functions uses.
- `references.spite`: what a call reached, read by the passes that drop functions.

`../ARCHITECTURE.md#the-high-passes-in-order` says what each pass does.
