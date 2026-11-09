# high_optimization_passes

The passes that transform the high representation, in the order `high_optimization_passes.spite` registers them.

- `high_optimization_passes.spite`: the entry, which registers each pass and proof in its setup and runs them in order.
- `<pass>/pass.spite`: one pass, class `Pass`, with `optimized(HighIntermediaryRepresentation.HighProgram)`.
- `proving.spite`: `Proving(proof)`, which registers a proof among the passes.
- `rewriting.spite` and `function_building.spite`: the two kits a pass that rewrites or builds functions uses.
- `references.spite`: what a call reached, read by the passes that drop functions.

`../ARCHITECTURE.md#the-high-passes-in-order` says what each pass does.

## Copies

A pass that copies a statement or a value calls `copy()`, which carries every field, and gives each list field a list
of its own with a walk over the copy's attributes (`own_list`), so a field added later is copied without anyone
writing it. Only what the copy changes is written beside it.

### What a copy leaves out

A field a copy must not carry is reset by name beside the copy, under a link here saying why:

- `replaced_defaults` evaluates a copy of each first use of a quiet write, only so the defaults run where they used
  to. The copy must run them (`skips_the_defaults` is `false`) and hands nothing to foreign code (`foreign_place` is
  empty): it is a fresh object made for its defaults, not the object that was handed over.
