# Proofs

A **proof** is a fact the compiler establishes while compiling: that a `T?` holds a value here, that an index is in
range, that an object never leaves its function, that no other thread reaches a singleton. With the fact in hand
the compiler **accepts** code it would otherwise refuse, **drops** a check it would otherwise emit, **chooses
cheaper code**, or **refuses** code that would go wrong (D276). A proof emits nothing of its own: what it costs is
the check it leaves in place when it does not hold, and a proof that does not hold never fails silently (D244):
the code is refused, saying what to write, or the run-time check stays.

The rules are the language's, in `../SpiteLanguage/specs`; this page says, for each proof, what this compiler does
with it. Each section has the same parts:

- **Status**: built, partly built (what is missing is its line in `TODO.md`, "Every proof the original makes"), or
  missing.
- **Rule**: what is proven and how, with a link to the specification that states it in full.
- **Buys**: the code accepted or refused, the check dropped, the cost saved.
- **Falls back**: when it does not apply, what the compiler does and what the user writes.
- **Lives in**: the pass or the file that makes it. A proof is a pass of its own (D1086), in `proofs/<name>/`; a
  proof still made inside a step or another pass says "embedded", and moving it out is a `TODO.md` line.
- **Checked by**: the `../SpiteSpec` programs that pin it (`tests/` must run, `conformance/` must be refused).

Two kinds of proof run at two places (D1086, D1072). A proof that decides whether code is **accepted** runs on the
high representation once it is built and before any optimisation pass, so what a program may say never depends on
how well it is optimised. A proof that only makes code **cheaper** runs where its facts exist (after inlining, for
placing objects in the frame) and records its fact; the optimisation passes read those facts rather than proving
anything themselves. `ARCHITECTURE.md` lists the order.

Of the 92 proofs the old compiler made, 33 are built, 38 are partly built and 21 are missing (audit of
2026-10-24, with what was built since). Where a proof is partly built and what is missing could let a wrong program through, the section says
**fails silently**: that is a D244 bug and its `TODO.md` line comes first.

## Presence and control flow

### Narrowing a `T?`

- **Status**: built.
- **Rule**: only a call-free name or path narrows; `if` narrows its block and not its `else`; `assert` and `crash`
  narrow the rest of the block; `while` narrows its body; a `switch` `T:` case narrows its case; one check narrows
  every link of the path before it. It tests presence, never the value
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule),
  [control_flow.md](../SpiteLanguage/specs/control_flow.md#control-flow-in-full)).
- **Buys**: reads, calls and stores through a `T?` are accepted, and the narrowed read has no test.
- **Falls back**: refused, "this value may be null (it is a ...), so '...' cannot be read from it yet: narrow it
  first with 'if value { }', 'assert value' or 'crash value'". Put a call's result in a `var` and narrow that.
- **Lives in**: embedded in the builder, `high_intermediary_representation/building/statements.spite` (`read_facts`,
  `read_a_fact`, `narrowed_block_of`), `scope.spite` (`narrow`), `values.spite` (`narrowed`, `with_its_links`,
  `refuse_an_unproven_read`). Narrowing decides the type of every read, so it is made while the high representation
  is built.
- **Checked by**: tests/path_narrowing, tests/present_zero, tests/nullable_narrowing, tests/narrowed_path_kept,
  tests/narrowed_read_local, tests/while_narrows, tests/nullable_switch_null_case; conformance/store_through_nullable,
  conformance/path_narrow_else, conformance/sibling_path_unnarrowed, conformance/maybe_boolean_conditions,
  conformance/null_comparison.

### Every side of an `and` narrows

- **Status**: built, wider than the old rule.
- **Rule**: each side of an `and` holds where the whole holds, and later sides see the earlier ones narrowed; the
  right side of an `or` sees the left side's opposite. This holds in every condition, `while` and a plain
  expression included ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: one line proves several reads (`if node and node.ready`).
- **Falls back**: the sides are tested in order, so a later side is never read unproven.
- **Lives in**: embedded, `statements.spite` (`read_a_binary_fact`), `values.spite` (`logic_value`,
  `right_condition_of`).
- **Checked by**: tests/and_narrowing, tests/and_return_narrowing.

### An `if` that leaves proves the rest

- **Status**: partly built.
- **Rule**: after an `if` with no `else` whose block always leaves (a `return`, a bare `crash`, a `switch` whose
  every case leaves, an `if`/`else` that both leave, a `while true`), the opposite of its condition holds: each `or`
  side written `not path` narrows that path, each side read with the sides before it narrowed (`if not holder or
  not holder.weapon { return }` proves both), and other sides turned around prove `[]` reads and divisors
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule),
  [control_flow.md](../SpiteLanguage/specs/control_flow.md#switch-over-values)).
- **Buys**: guards read as answers: `if not monster { return }` and the rest reads `monster`.
- **Missing**: a count side (`found.count() == 0`) after `not found` proves no `found[0]`.
- **Falls back**: the rest stays unproven, and a read of it is refused.
- **Lives in**: embedded, `statements.spite` (`build_if`, `read_a_negated_fact`, `read_a_negated_binary`,
  `note_the_leaving_if`), `endings.spite` (`always_leaves`), `ranges.spite` (`prove_an_if`).
- **Checked by**: tests/leaving_if, tests/returning_branch_proof, tests/control_switch_leaving_narrows,
  tests/leaving_or_narrows; conformance/leaving_if_proves_nothing.

### Assigning undoes a proof

- **Status**: built.
- **Rule**: assigning a narrowed path, or anything it reads through (an index name included), undoes every proof
  beneath it: an attribute assigned by its bare name undoes the paths written from it (`target.weapon` after
  `target = Monster()`), a store through a setter undoes its path, and `list[i] = value` undoes what was proven
  below the items, and every item's narrowing when the value may be null; assigning it a value that cannot be null
  keeps its own narrowing. Inside a `while`, assigning a value that may be null to a path narrowed before the loop
  and read in it is an error: for an attribute at once, for a local or a parameter when the end of the body leaves
  it unnarrowed (a check later in the same pass keeps it)
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: nothing stale is read: a narrowed read has no run-time test.
- **Falls back**: refused, "assigning to '...' inside this loop undoes a narrowing made before the loop, and the
  next pass would read it unproven: narrow it inside the loop instead"; after the assignment, a read is refused
  until it is proven again.
- **Lives in**: embedded, `statements.spite` (`assign_a_name`, `assign_an_attribute`, `forget_the_stored_items`,
  `note_an_undone_loop_proof`, `refuse_what_the_loop_left_undone`), `scope.spite` (`forget`, `forget_below`,
  `forget_below_the_items`, `keep_present`).
- **Checked by**: tests/narrowed_value_assignment, tests/proof_again_in_loop, tests/narrowing_snapshot_copy,
  tests/loop_narrows_its_local_again; conformance/narrowed_name_reassigned, conformance/path_narrow_assignment,
  conformance/path_narrow_loop, conformance/narrowed_path_undone_below, conformance/narrowed_local_undone_in_loop,
  conformance/assigned_start_undoes_narrowing, conformance/index_store_undoes_narrowing.

### A call keeps a proof it cannot change

- **Status**: partly built: every narrowing a read relies on without a test is checked; the `[]` and count proofs,
  which keep a test, are not.
- **Rule**: a narrowed attribute read is refused when a call built between the check and the read may assign that
  attribute, followed through everything the call reaches. What a call may assign is decided by the attribute's
  class and name: a constructor's writes to its own object and writes to an object made in the same function are
  not writes to anything a proof reads; a wait writes nothing in a program that makes no `Concurrent` or
  `Parallel`, and anything in one that does; a call through a function value reaches the functions taken as values
  with its signature, and a function that only calls its parameters reaches the functions each caller passes it; a
  `drop()` that may run is followed too. Inside a loop, a call anywhere in the body undoes a narrowing made before
  the loop for the next pass ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: no re-check after a harmless call; a call that may null what was proven is never read past.
- **Missing**: a `[]` or count proof is undone only by a direct shrinking call, a bare call of the class's own
  function and a call on a `[]` receiver (a read it keeps halts, "is outside its list", when the list changed); a
  call inside a condition is ordered after the block it guards.
- **Falls back**: refused, "'keeper.target' was proven before line 12, where 'forget(...)' may assign 'target'
  again, so this read would use what the call left there, unproven: prove 'keeper.target' again after that line";
  in a loop, at the call, "'forget(...)' inside this loop may change 'target', which undoes what was proven about
  'keeper.target' before the loop, and the next pass would read it unproven: prove it inside the loop instead". The
  message names the function that writes when it is not the one called.
- **Lives in**: the pass `proofs/narrowings_kept_across_calls` (its own folder), run on the high representation
  once every function is built. The builder records each narrowed read
  (`high_intermediary_representation/narrowed_read.spite`, `values.spite`: `note_a_narrowed_read`) with the calls
  built since its check (`statements.spite`: `log_the_calls_of`); what a call may assign is
  `low_intermediary_representation/lowering/assignments.spite` read for narrowings (`read_for_narrowings`).
- **Checked by**: tests/receiver_call_effects, tests/same_name_call_effects,
  tests/narrowing_kept_across_harmless_call; conformance/call_undoes_proof, conformance/branch_undoes_proof,
  conformance/receiver_call_undoes_proof, conformance/count_undoes_proof, conformance/bound_proofs_undone,
  conformance/structural_index_undone, conformance/call_on_other_undoes_narrowing,
  conformance/call_in_loop_undoes_narrowing.

### An address keeps its owner alive

- **Status**: built, by construction.
- **Rule**: an address read out of an object counts as a use of that object, so the object is let go only after the
  address's last use ([memory.md](../SpiteLanguage/specs/memory.md)).
- **Buys**: no address outlives its object.
- **Falls back**: nothing to fall back to: the library has no `Memory.Address`, and every object is let go at the
  end of its block or statement, never earlier. The rule comes back with addresses or with a release at last use.
- **Lives in**: `low_intermediary_representation/lowering/function_lowering.spite` (`lower_block`,
  `release_the_pending`, `is_the_last_use`).
- **Checked by**: none.

### Proving what is proven is an error

- **Status**: partly built.
- **Rule**: a check of a `T?` already narrowed, a `[]` read already proven (by a bound, a count or an earlier
  check), a divisor already proven, a class test the type already answers, the same call-free condition on the next
  line, or an `assert`/`crash` that folds true is refused, naming where it was proven
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: no dead checks in the source.
- **Missing**: a re-check inside the `if`, `while` or `switch` that narrowed gets the "a condition is a Boolean"
  text instead; `[]` reads proven by a count or an earlier check are not refused; a divisor re-proven, a class test
  already answered, the repeated next-line check and an `assert` that folds true are not refused; the plain-value
  refusal covers parameters and attributes, not locals.
- **Falls back**: the redundant check is kept as a run-time test (harmless), or refused with a less precise text.
- **Lives in**: embedded, `statements.spite` (`refuse_a_proven_check`, `refuse_a_proven_read_check`,
  `refuse_a_check_of_a_plain_value`, `note_the_checks`).
- **Checked by**: conformance/check_proves_nothing, conformance/known_fact_checked, conformance/proven_element,
  conformance/proven_index_check, conformance/assert_on_plain_value, conformance/leaving_if_proves_nothing.

### A copy made to narrow is an error

- **Status**: partly built.
- **Rule**: a `var` holding a bare name or path of a `T?`, never assigned again and whose source is not assigned in
  the function, then narrowed (by `assert`, `crash`, `if`, `while`, `switch`, `not` of it or an `and` side), is
  refused: narrow the source itself. A snapshot taken before its source changes is allowed
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: one name per value.
- **Missing**: a copy narrowed by an `if not copy` whose block does not leave.
- **Falls back**: accepted, which is safe: only the style rule is missed.
- **Lives in**: embedded, `statements.spite` (`note_a_copy`, `refuse_a_copy`, `refuse_a_loop_copy`, `build_switch`).
- **Checked by**: conformance/copy_to_narrow, conformance/copy_to_narrow_conditions; tests/narrowing_snapshot_copy.

### A class test narrows its block

- **Status**: built, wider than the old rule.
- **Rule**: `if value == Monster { }` narrows the block to `Monster`, on a name, a member path, or a side of an
  `and`; a null tests false; in a generic class a test that cannot hold folds to false; `!=`, the `else` and a
  leaving `if` narrow nothing ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#unions-in-full)).
- **Buys**: a member's attributes and functions are read inside the block.
- **Falls back**: a member read without the test is refused; use a `switch`.
- **Lives in**: embedded, `statements.spite` (`read_a_binary_fact`), `values.spite` (`class_test_value`,
  `same_class`).
- **Checked by**: tests/class_test, tests/generic_class_test, tests/codegen_class_test, tests/null_class_test_false,
  tests/tested_classes; conformance/class_test_not_member.

### Every path ends in a `return`

- **Status**: built.
- **Rule**: a path ends at a `return`, a bare `crash`, an `if`/`else` whose branches both end, a `switch` whose every
  case ends, a `while true`, or a folded condition whose taken branch ends; a function that answers something and
  has a path that reaches its end is refused ([failure.md](../SpiteLanguage/specs/failure.md#assert-is-control-flow)).
- **Buys**: no caller gets a value nobody wrote.
- **Falls back**: refused, "'...' answers ..., but ... it reaches its end without a 'return' ...: end that path with
  'return <value>', or with 'crash' if it cannot happen".
- **Lives in**: `high_intermediary_representation/building/endings.spite` (`check`, `always_leaves`), its own class,
  run by the builder on each function body.
- **Checked by**: conformance/falling_end; tests/every_path_returns, tests/control_while_true_returns.

### A guard `assert` answers only "nothing"

- **Status**: built.
- **Rule**: a guard `assert` is allowed only where the result says "nothing" (no result, a `T?`, a `List`, a
  `Dictionary`, a `Vector`, an `Items`), never in a constructor; an `if` that only returns the default, or a last
  `if` with no `else` that only checks presence, is refused naming the `assert`
  ([failure.md](../SpiteLanguage/specs/failure.md#assert-is-control-flow)).
- **Buys**: no default a caller cannot tell from a real answer.
- **Falls back**: refused, "this 'assert' would answer a default ... that a caller cannot tell from a real one ...".
- **Lives in**: embedded, `statements.spite` (`build_assert`, `default_return`, `refuse_a_terminal_if`), and
  `validators/abstract_syntax_tree/default_guard`.
- **Checked by**: conformance/default_answer, conformance/default_answer_boolean, conformance/default_answer_decimal,
  conformance/default_answer_enum, conformance/default_answer_text, conformance/default_guard,
  conformance/returning_guard, conformance/empty_collection_guard, conformance/terminal_if,
  conformance/assert_in_constructor, conformance/constructor_guard, conformance/guard_de_morgan,
  conformance/guard_inside_loop.

### A switch covers every case

- **Status**: built.
- **Rule**: a switch over a union covers every member or ends with `_:`; over a `T?` of a class or a union it covers
  the class (or every member) and `Null`, or ends with `_:`; over an enum every value or `_:`; over a whole number
  or a text always `_:`; a needless or repeated case is an error
  ([control_flow.md](../SpiteLanguage/specs/control_flow.md#switch-over-values),
  [values_and_types.md](../SpiteLanguage/specs/values_and_types.md#unions-in-full)).
- **Buys**: a member, a value or a null added later cannot be forgotten.
- **Falls back**: refused, "this switch over '...' has no case for ...: add the cases, or end with '_:' for the
  rest"; over a `T?`, "this switch over 'target' has no case for Null: 'target' is a Monster?, and a switch over a
  'T?' covers its value and null, so a null cannot be forgotten; add the cases, or end with '_:' for the rest".
- **Lives in**: the proof `proofs/switch_cover`, which judges every switch the builder recorded before writing it as
  `if`s (`context.switch_sites`, from `statements.spite`: `check_the_cover`, `check_the_nullable_cover`) with the
  validator `validators/high_intermediary_representation/switch_cover`; a case of the wrong kind is still refused
  while building the case, and `validators/abstract_syntax_tree/switch_cases` checks the written cases.
  A switch is built as a chain of `if`s, so its cover is judged while it is built.
- **Checked by**: conformance/missing_switch_case, conformance/control_switch_enum_missing,
  conformance/control_switch_enum_rest_unneeded, conformance/control_switch_number_no_rest,
  conformance/control_switch_text_no_rest, conformance/switch_rest_case, conformance/switch_rest_after_all,
  conformance/switch_rest_not_last, conformance/switch_same_as_rest, conformance/value_switch,
  conformance/control_switch_value_on_nullable, conformance/nullable_switch_without_null; tests/rest_case,
  tests/value_switch, tests/nullable_switch_null_case, tests/nullable_switch_with_rest.

## Indices and numbers

### A proven count or bound proves a read

- **Status**: partly built.
- **Rule**: `index < list.count()` (also `- k`, `count() > index`, a count kept in a `var`), with any call-free
  index (`code - 32 < glyphs.count()` proves `glyphs[code - 32]`), `base + k < list.count()` for k from 1 to 63, and
  the count facts `== k`, `>= k`, `> k`, `!= 0` and `not is_empty()` (at most 64 indices) prove `list[...]`, in
  `assert`, `crash`, `if`, `while`, the right of an `and`, and after an `if` that leaves
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a proven read answers `T`, not `T?`.
- **Missing**: bounds written with `<=`; count facts in a `while`; undoing a proof inside the loop that read it is
  not refused, and a shrinking call inside an assignment or an argument does not undo it (each read still halts
  when its list changed, see the next section).
- **Falls back**: an unproven read is a `T?`; where a `T` is needed it is refused, "'...' may be missing, since every
  '[ ]' answers a 'T?' ...: ..., or prove the count first, 'crash list.count() > 2'".
- **Lives in**: embedded, `statements.spite` (`read_a_bound`, `read_a_counted_list`, `read_a_counted_member`,
  `read_a_turned_bound`, `whole_index_of`, `note_a_counted_list`, `forget_after_a_shrinking_call`), `values.spite`
  (`index_value`, `proven_by_its_path`).
- **Checked by**: tests/count_bound_proofs, tests/bound_proofs, tests/count_in_name_proves, tests/structural_index,
  tests/proof_again_in_loop, tests/compared_count_proves_read; conformance/index_reads,
  conformance/bound_proofs_undone, conformance/count_proves_no_key, conformance/count_undoes_proof,
  conformance/structural_index_undone, conformance/proven_index_check, conformance/call_in_index,
  conformance/indexable_unproven.

### A proven read halts outside its list

- **Status**: built.
- **Rule**: a read proven by a bound or a count keeps one never-taken test against the list's length, which halts
  naming the read: a bound proves only the top of an index, and the list may have changed
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a wrong or stale proof halts, never reads out of bounds.
- **Falls back**: "spite: '...' is outside its list: a bound proves only the top of an index, and this one is below 0
  or the list changed, at ...".
- **Lives in**: `low_intermediary_representation/lowering/list_reads.spite` (`read_the_item`), and the pass
  `low_optimization_passes/proven_bounds`, which drops the test where a signed test of the same values and a never
  negative index already prove it.
- **Checked by**: tests/proven_read_outside.

### A proven count or bound proves a read of a width

- **Status**: missing.
- **Rule**: `read_<number>_at(p)` of width w is proven where `bytes[p + w - 1]` would be (a bound, a count, a `<=`
  bound with k from 1 to 64, a counted loop's window); a position known not to be negative drops the low test
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a header or a record is read with one bound.
- **Falls back**: the read is a `T?` the program narrows; the library read tests both ends.
- **Lives in**: none.
- **Checked by**: conformance/byte_reads (the refusals only).

### An index built from loop counters is proven by one guard

- **Status**: missing.
- **Rule**: the guard `rows * stride <= list.count()` with `while row < rows` and `while column < stride` over
  non-negative locals proves `list[row * stride + column]`, and the reads of a width there
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: the cells of an area are read with one guard.
- **Falls back**: the read is a `T?` and is narrowed, or refused where a `T` is needed.
- **Lives in**: none.
- **Checked by**: none (tests/area_guard_cells has the shape and reads the cells as `T?`).

### An index offset by a base is proven by one guard

- **Status**: missing.
- **Rule**: the guard `base + bound <= list.count()` with `while counter < bound`, base and counter not negative,
  proves `list[base + counter]` ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a slice of a list is read with one guard.
- **Falls back**: the read is a `T?` and is narrowed.
- **Lives in**: none.
- **Checked by**: none.

### A counted loop reads its items unchecked

- **Status**: partly built (done differently).
- **Rule**: inside `while index < values.count()` with the counter stepped last, the count is read once and the
  items with no test; a second list indexed by the counter is tested once before the loop
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a tight loop over numbers costs a load per item.
- **Missing**: in the scalar loop a second list keeps its test on every pass (only the vector loop tests once); a
  window read (`values[index + k]`) loses its test only when the registers line up with the loop test.
- **Falls back**: each read keeps its unsigned test.
- **Lives in**: the pass `low_optimization_passes/proven_bounds` (`proven_by_a_signed_test`), with
  `lowering/list_reads.spite`, `low_optimization_passes/loop_invariants` and `low_optimization_passes/vector_loops`.
- **Checked by**: tests/counted_loops, tests/strided_counted_loops.

### A proven divisor is not checked

- **Status**: partly built (by ranges, wider than the old rule).
- **Rule**: a divisor that is a non-zero constant, or whose range leaves out 0 (and -1 when the dividend may be the
  smallest value), is divided with no test ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#numeric-types)).
- **Buys**: no zero test on a division.
- **Missing**: `!= 0` proves nothing (a range cannot leave out a middle value); a divisor that is an attribute or a
  member path; nothing in `--repl` and `--hot-reload` builds.
- **Falls back**: the test stays, "spite: '...' divided by zero, at ...".
- **Lives in**: the proof `proofs/ranges` (`prove_the_divisor`), a speed proof run after the acceptance proofs,
  whose fact the lowering reads (`is_divisor_proven`).
- **Checked by**: tests/division_by_zero, tests/divisions, tests/smallest_divided.

### A divisor written as zero is an error

- **Status**: built.
- **Rule**: a whole-number `/` or `%` whose divisor is a constant expression equal to zero is refused
  ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#numeric-types)).
- **Buys**: a division that always halts never compiles.
- **Falls back**: refused, "'...' divides by zero, which always halts the program ...".
- **Lives in**: embedded, `values.spite` (`binary_value`, `refuse_a_division_by_zero`).
- **Checked by**: conformance/division_by_constant_zero, conformance/remainder_by_folded_zero.

### Arithmetic that does not fit halts

- **Status**: partly built.
- **Rule**: every whole-number `+`, `-`, `*`, unary `-`, the smallest value divided by -1 and a narrowing halts if
  it does not fit; the step of a counter under its bound carries no check, nor does constant arithmetic; constant
  arithmetic that does not fit is a compile error
  ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#numeric-types)).
- **Buys**: no wrapped number is ever read.
- **Missing**: a `Long` counter whose bound has no range keeps its check; `--repl` and `--hot-reload` builds keep
  every check; the constant overflow error is made only for `Integer` arithmetic.
- **Falls back**: the check stays, "spite: '...' does not fit in an Integer (...), at ...".
- **Lives in**: the lowering (`function_lowering.spite`: `is_checked`, `check_the_range`), the generator
  (`emit_a_cold_stop`), and the counter proof in `ranges.spite`.
- **Checked by**: tests/counter_room, tests/integer_overflow, tests/unsigned_overflow, tests/narrowing_overflow,
  tests/negate_overflow, tests/smallest_divided, tests/smallest_absolute; conformance/constant_overflow,
  conformance/literal_does_not_fit, conformance/byte_minimum_literal_does_not_fit.

### A range proves arithmetic fits

- **Status**: partly built (D768).
- **Rule**: every whole-number local and parameter has a range from literals, assignments and the conditions in
  force; `count()`, `length()`, `%`, `minimum`, `maximum` and `clamp` bound their answers; loops widen counters and
  count passes; a total holds at most `passes` terms
  ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#a-range-proves-a-check-unneeded)).
- **Buys**: an operation the ranges prove carries no overflow check.
- **Missing**: `absolute` gives no range; a counter stepped down keeps no floor and counts no passes; loop locals
  other than counters; types wider than 4 bytes only where a value gives a range.
- **Falls back**: the check stays and is listed by `--optimization-report`.
- **Lives in**: the proof `proofs/ranges`, a speed proof run after the acceptance proofs, over every function built from
  the source; it records its fact on each operation (`proves_no_ranges`, the unchecked arithmetic) for the lowering.
- **Checked by**: tests/proven_ranges, tests/optimization_report, tests/counter_room.

### A wider operand is written first

- **Status**: built.
- **Rule**: in arithmetic, comparisons and bitwise functions, a right side with more bits (or a decimal beside a
  whole number) is refused, naming the turned-around form, unless it is a literal within the left type
  ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#casting)).
- **Buys**: nothing is cut to fit.
- **Falls back**: refused, "'...' is added in Integer, since arithmetic takes the left side's type, and the right
  side is a Long, which would be cut to fit: write the Long first ...". A literal out of the left type's range gets
  the literal-fit error instead; inside a template's number copy the cut halts at run time.
- **Lives in**: embedded, `values.spite` (`binary_value`, `refuse_a_cut`, `refuse_a_wider_bitwise_operand`).
- **Checked by**: conformance/wider_right_operand, conformance/wider_comparison, conformance/wider_bitwise_operand,
  conformance/wider_decimal_right, conformance/wider_multiplication_order, conformance/wider_subtraction;
  tests/signedness_not_wider.

### Maths on constants is worked out while compiling

- **Status**: built (wider than the old rule).
- **Rule**: a maths member whose receiver and arguments are known is answered by the compiler, a not-a-number answer
  excepted ([standard_library.md](../SpiteLanguage/specs/standard_library.md#maths)).
- **Buys**: no call at run time.
- **Falls back**: one call into the C library, or one instruction.
- **Lives in**: the passes `low_optimization_passes/compile_time_evaluation` and `constant_folding`; see
  `OPTIMIZATIONS.md`.
- **Checked by**: tests/maths_folding; conformance/maths_constant_assigned, conformance/maths_constant_called,
  conformance/maths_constant_on_value.

### A dictionary only read by literal keys is never made

- **Status**: built.
- **Rule**: a local made from a dictionary literal of literal keys and values, every later mention of which is
  `name[literal]` and never assigned, is never made: each read is its value or `null`, still a `T?`.
- **Buys**: no dictionary, no hashing.
- **Falls back**: the dictionary is made and read as written.
- **Lives in**: embedded, `high_intermediary_representation/building/folded/dictionaries.spite`.
- **Checked by**: tests/dictionary_folding.

## Compile-time questions

### Conditions decided while compiling

- **Status**: partly built.
- **Rule**: an `if` on a Build field, a codegen value, a type test, a walk's `attribute.class` or name test, a class
  test the value's type answers, or a compile-time question (and `not`, `and`, `or`, `==`, `!=` over them) keeps
  only its taken branch; only what survives is compiled
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md)).
- **Buys**: generic code compiles only the branch its class takes.
- **Missing**: `function_waits` and `function_writes_parameter` are answered after every function is built, so both
  branches are built and checked (D673); a codegen number compared with a literal folds only when one side is a
  call; a function taking a `type` has no copy per class; `x and false` and `x or true` with a run-time left side.
- **Falls back**: a run-time test of a constant, removed later by constant folding; both branches must compile.
- **Lives in**: embedded, `statements.spite` (`build_a_decided_if`), `values.spite` (`condition_of`,
  `folded_logic`, `decided_comparison`, `reflection_question`).
- **Checked by**: tests/codegen_member_fold, tests/walked_class_fold, tests/private_walk, tests/codegen_short_circuit,
  tests/codegen_kind_tests, tests/codegen_class_test, tests/build_settings, tests/folded_helpers,
  tests/folded_functions, tests/folded_argument_count.

### Whether a function waits

- **Status**: partly built; **fails silently**.
- **Rule**: waiting spreads from `sleep`, console, file and socket reads and joins, through calls, function values
  (to every function taken as a value with the same signature) and `type` dispatch, to a fixed point; letting go of
  a `Concurrent` waits; where it cannot tell, the answer is true
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks),
  [concurrency.md](../SpiteLanguage/specs/concurrency.md)).
- **Buys**: `function_waits` and `is_resumable` fold.
- **Missing**: the study behind `function_waits` does not count letting go of a `Concurrent` (a local or an
  attribute assigned again, a holder dropped, a list cleared), which the lowering's own study does count; a call
  through a function value it does not know adds nothing, where it should spread or answer true. Both answer false.
- **Falls back**: refused when the answer would decide itself, "whether '...' can wait was answered ... before the
  functions that ask 'function_waits' were compiled ...".
- **Lives in**: the proof `proofs/compile_time_facts`, which answers every question asked while building and
  refuses an answer that would decide itself; the study it reads is `high_intermediary_representation/building/facts.spite`
  (`waits`, `waits_through`), which the builder also reads for the frame starts; a second study in `lowering/waits.spite`
  (embedded: the lowering's own, for what each call suspends).
- **Checked by**: tests/waiting_systems, tests/entry_function_waits, tests/pooled_loads_wait, tests/default_handles,
  tests/reflection_objects; conformance/function_waits_paradox.

### How many arguments a function takes

- **Status**: partly built.
- **Rule**: `$T.argument_count("<pattern>")` and a walk's `phase.argument_count()` fold to a whole number; every
  function a pattern matches must take the same number, and a pattern matching none is an error
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks)).
- **Buys**: generic code chooses its call by the count.
- **Missing**: the error for `argument.argument_count()` asked outside a walk over functions.
- **Falls back**: refused, "'...' has no function named '...', so 'argument_count' has nothing to count ...", or
  "... has no one answer: the functions of 'Painter' that fit it take different numbers of arguments ('update_each'
  1, 'render_each' 2), so ask 'phase.argument_count()' in a template over them, where each is walked on its own".
- **Lives in**: embedded, `values.spite` (`counted_arguments`, `refuse_disagreeing_counts`,
  `pattern_argument_count`).
- **Checked by**: tests/folded_argument_count, tests/system_phases, tests/streamed_rows; conformance/argument_count,
  conformance/argument_count_missing, conformance/passed_argument_count, conformance/argument_count_disagrees.

### Whether a class fits a `Vector`

- **Status**: partly built.
- **Rule**: every attribute is a number, a Boolean, a text, an enum, a symbol, a singleton or a `T?` of those; no
  `drop()`; no function uses `this` as a value; not a generic template. `fits_vector()`, `is_fixed_size` and
  `any_attribute_fits_vector` fold, and an `Items<T>` stores its items inline exactly when a `Vector<T>` could be
  made ([collections.md](../SpiteLanguage/specs/collections.md)).
- **Buys**: items inline, lent rather than counted.
- **Missing**: "not a generic template"; the borrow study (`borrows.spite`) keeps its own copy of the answer, which
  does not test `this` yet, so it may refuse a borrow of an `Items` item that is held by reference.
- **Falls back**: refused for a `Vector<T>`, "'...' uses 'this' as a value, and an item of a Vector is borrowed ...";
  an `Items<T>` holds such items by reference.
- **Lives in**: the proof `proofs/vector_fit` refuses a `Vector` of a class that does not fit, judging every
  `Vector` the builder recorded making (`context.vector_sites`); the test itself, `constraints.spite`
  (`fits_a_vector`, with `uses_this_as_a_value`), is still asked while building by `values.spite`, `borrows.spite`
  and `reflection.spite`, which choose the form of what they build from it.
- **Checked by**: tests/items_columns, tests/folded_checks, tests/folded_lends, tests/lent_list_elements,
  tests/reflection_objects; conformance/folded_crash.

### Whether a function writes a parameter

- **Status**: built.
- **Rule**: `function_writes_parameter(...)` and `.is_mutated` fold: a write is an attribute or item set, a call
  that writes, passing it to a written parameter, or storing it where a later write could reach it; reassigning,
  copying plain values out and writing a singleton are not; where it cannot tell, true
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks)).
- **Buys**: generic code skips a copy a callee never writes.
- **Falls back**: true for an unknown function value, a member template or a function with a `Spite.*` parameter.
- **Lives in**: the proof `proofs/compile_time_facts`, reading `building/facts.spite` (`writes`, `callee_writes`).
- **Checked by**: tests/parameter_writes, tests/parameter_write_rows, tests/run_time_kinds;
  conformance/parameter_write_question, conformance/snapshot_argument_writes.

### Whether a class keeps state

- **Status**: partly built; **fails silently**.
- **Rule**: `$T.is_stateful` folds to "some function other than the constructor and `drop()` writes its own object
  or a singleton, or a singleton it binds keeps state"; where it cannot tell (a function it cannot build, such as a
  member template or one taking a `Spite.*` parameter), true
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks)).
- **Buys**: generic code shares an object nothing changes.
- **Missing**: writing a singleton does not count; it is a filled reflection value, not a folded constant, so an
  `if` on it builds both branches.
- **Falls back**: true when a bound singleton has attributes, when a function cannot be built, and for a library
  class with attributes.
- **Lives in**: embedded, `reflection.spite` (`fill_from_the_model`, `every_writer_can_be_built`,
  `writes_its_object`).
- **Checked by**: tests/class_walk, tests/run_time_kinds, tests/reflection_objects.

### The one class a `type` admits

- **Status**: built (wider than the old rule).
- **Rule**: with the whole program known, an attribute read through a `type` is read at the offset every class that
  fills it shares, with no class test; off in interactive builds
  ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#inline-types-and-duck-typing-in-full)).
- **Buys**: no class test on a read through a `type`.
- **Falls back**: a test of the class id, for a member some filler answers with a function, a shape call with
  arguments, or an offset another union takes.
- **Lives in**: embedded, the high pass `high_optimization_passes/untouched_attributes` (`optimized`), and the lowering (`lower_shape_call`).
- **Checked by**: none aimed at it (tests/class_through_shape and tests/unions read through a `type`).

### A `crash` that folds false is a compile error

- **Status**: built.
- **Rule**: an `assert` or a `crash` that asks only compile-time questions folds; a `crash` that folds false in a
  function the program reaches is refused, naming the instance and each side of an `and`; an `assert` that folds
  false answers its default and the rest of its block is not compiled
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md)).
- **Buys**: a generic class that cannot work for a class is refused for it.
- **Falls back**: refused, "'crash ...' always halts in ...: its condition is decided while compiling and is false
  ...".
- **Lives in**: the proof `proofs/folded_crashes`, run once the facts are answered, and embedded in
  `statements.spite` (`build_crash`, `refuse_a_folded_crash`) for a `crash` the builder folds while building it.
- **Checked by**: conformance/folded_crash, conformance/folded_build_crash, conformance/folded_crash_and_side,
  conformance/empty_walk_crash, conformance/snapshot_argument_writes; tests/folded_crash_uncalled,
  tests/folded_checks.

### Tree shaking: what `main` can reach

- **Status**: partly built.
- **Rule**: only what the entry reaches is kept, transitively: a function called, a member a dispatch may call, a
  function taken as a value ([compiler.md](../SpiteLanguage/specs/compiler.md)).
- **Buys**: a program carries none of what it does not use.
- **Missing**: reach is decided only while the high representation is built: a function whose only callers were
  inlined, or that sits in a branch folded later, is still written; a function nobody calls is never built, so it
  is not type-checked; an inspectable build keeping everything.
- **Falls back**: keeps too much, never too little.
- **Lives in**: `builder.spite` (`build`), `building/context.spite` (`need`).
- **Checked by**: tests/folded_helpers, tests/folded_crash_uncalled, tests/unreached_function_reads, tests/hello.

### A reload compiles only the changed classes

- **Status**: missing (no reload).
- **Rule**: a `--hot-reload` build records every fact one class took from another; a reload replays them, compiles
  the changed classes, and falls back to a whole compile, saying why, when a fact differs
  ([repl.md](../SpiteLanguage/specs/repl.md)).
- **Lives in**: none (`HOT_RELOAD.md` is the design).
- **Checked by**: none.

### A reload reaches every object whose attributes it changes

- **Status**: missing (no reload).
- **Rule**: every live object of a program class is reachable by the reload, which moves it to the new layout, and
  a function that cannot be re-pointed refuses the reload by name ([repl.md](../SpiteLanguage/specs/repl.md)).
- **Lives in**: none.
- **Checked by**: none.

## Memory

### A buffer freed in its block lives in the frame

- **Status**: missing (the library has no `Memory.Heap`).
- **Rule**: a buffer allocated and freed in one block, used only through address primitives in between, lives in
  the frame ([memory.md](../SpiteLanguage/specs/memory.md)).
- **Falls back**: a `Buffer` is a heap object.
- **Lives in**: none.
- **Checked by**: none.

### Objects that never leave their function live in the frame

- **Status**: partly built (D801, D953).
- **Rule**: a fresh object of a class that holds only numbers, Booleans, enums and singletons, that never leaves its
  function, lives in registers or the frame; a constructor-made local whose class holds text or lists too
  ([memory.md](../SpiteLanguage/specs/memory.md)).
- **Buys**: no allocation, no count.
- **Missing**: the fresh result of a function that is not inlined goes to the heap; an object whose class lets go
  of attributes is placed only in registers, never in the frame; `.memory.section` answering `'stack'`.
- **Falls back**: a heap object.
- **Lives in**: the pass `low_optimization_passes/object_placement`, after inlining and compile-time evaluation.
- **Checked by**: tests/generic_vectors, tests/written_codegen_in_frame, tests/owned_objects (output only).

### Local and variadic lists in the frame

- **Status**: partly built (D991).
- **Rule**: a local list made by a literal or `List<T>()` and filled at its own level, then only read, lives in the
  frame; a variadic list its callee only reads lives in the caller's frame
  ([functions_and_operators.md](../SpiteLanguage/specs/functions_and_operators.md)).
- **Buys**: no allocation.
- **Missing**: variadic lists; lists of anything but whole numbers; reads other than `count()` and `[]`; constant
  data.
- **Falls back**: a heap list.
- **Lives in**: embedded in the lowering, `lowering/frame_lists.spite`.
- **Checked by**: tests/frame_lists, tests/variadic_answers_in_frame, tests/text_building (output only).

### A function value its callee only calls lives in the frame

- **Status**: partly built (only through inlining and known closures, D1043).
- **Rule**: a function value passed to a function whose every mention of it is a call lives in the caller's frame,
  uncounted ([functions_and_operators.md](../SpiteLanguage/specs/functions_and_operators.md)).
- **Missing**: the "only calls it" proof over the callee, so a callee not inlined gets a counted heap value.
- **Falls back**: a heap function value with a counted receiver.
- **Lives in**: indirectly, `compile_time_evaluation/partial_evaluation.spite` and `object_placement`.
- **Checked by**: tests/function_value_in_frame, tests/held_value_functions, tests/function_values.

## Borrowing and lending

These proofs belong to the ownership analysis of the high representation; the refusals are in
`high_intermediary_representation/building/borrows.spite`, and the counts it saves in the lowering.

### Borrowed items of a `Vector` or `Items`

- **Status**: partly built (D729): the refusals.
- **Rule**: `vector[index]` and a template's visited item are borrowed, never kept, listed, returned, made a function
  value, given a second name or assigned again ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)).
- **Missing**: the reads are still counted (no uncounted address); walk copies and library member templates are not
  checked; `InlineMemory` is not a borrowing collection.
- **Falls back**: refused, "'...' is borrowed from '...' and cannot be kept in the attribute '...': keep
  '....copy()', an independent object".
- **Checked by**: conformance/vector_borrow_alias, vector_borrow_assigned, vector_borrow_function_value,
  vector_borrow_kept, vector_borrow_listed, vector_borrow_returned, vector_borrow_temporary, items_borrows,
  own_template_borrows, reopened_vector_borrows, vector_this_item; tests/vector_items, items_narrowed,
  vector_item_written_in_place, game_vectors, generic_vectors.

### No borrowed read past a resize

- **Status**: partly built (D730); **fails silently** (the rule goes unenforced, memory stays safe).
- **Rule**: a borrowed name is not read after anything that may resize its collection, followed through calls; a
  resize anywhere in a loop ends the borrow for the loop
  ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)).
- **Missing**: assigning a local `Vector` again, or an attribute along the path, is not a resize; library functions
  are not followed; a value of unknown type fans out to every function of the name; a callee's effects computed
  under the recursion guard are cached short.
- **Falls back**: refused, "'...' is borrowed from '...', and '...' on line ... may move the items ...".
- **Checked by**: conformance/vector_borrow_call_grows, vector_borrow_loop, vector_borrow_removed,
  vector_borrow_swap, vector_reserve_borrows, dispatched_resizes, found_item_borrows, items_borrow_remove_swapping;
  tests/queued_borrows.

### Rows of borrowed items

- **Status**: partly built.
- **Rule**: a row lives for exactly one call, passed only to a function called by name taking a `type`, never
  kept, returned, listed, aliased or assigned, and the call may not resize its sources
  ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)).
- **Missing**: the row in the frame and uncounted when the callee is not inlined; a walked template's
  `var stored_row = rows[...]`; the arguments a plural fills; `row.describe` as a function value; a row passed to a
  library function.
- **Falls back**: refused for the cases built; otherwise a counted heap row.
- **Checked by**: conformance/vector_rows, sparse_rows, walked_rows, vector_row_alias,
  vector_row_attribute_assigned, vector_row_kept, vector_row_mixed, vector_row_passed, vector_row_returned;
  tests/vector_rows, sparse_rows, walked_rows, walked_row_locals, streamed_rows, vector_row_attributes_written.

### An item lent to the caller

- **Status**: partly built; **fails silently** (one case).
- **Rule**: a `return` of an item read straight from a singleton's `Vector` or fitting `Items` lends it: every
  return is such an item or null, the caller borrows it, and it is called only by name
  ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)).
- **Missing**: the uncounted return; `is_fixed_size` and `functions[...]` folded in its conditions; returning a lent
  result through a name (`var h = lookup.of(0); return h`) is accepted.
- **Falls back**: refused, "'...' lends its caller an item of '...' ...".
- **Checked by**: conformance/lent_escapes, lent_results, lent_function_type, lent_function_value,
  lent_result_name_reused, lent_result_other_value, lent_result_returned_further; tests/lent_results,
  narrowed_lends, folded_lends.

### An item lent to a call

- **Status**: partly built; **fails silently** (the rule goes unenforced).
- **Rule**: a borrowed item passed to a program function called by name is lent for the call; the callee is
  compiled under the borrow rules, the call may not resize the source, and lending to a library function, a union
  or an unnamed expression is an error ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)).
- **Missing**: the uncounted argument; a lent parameter the callee passes on to a function that keeps it; a row's
  attribute is not lent; the unnamed expression refusal; lending to a local function value; variadic positions.
- **Falls back**: refused, "'...' is borrowed from '...' and lent to '...' for its call ...".
- **Lives in**: the proof `proofs/lent_parameters` judges the callee's body; the builder records each lent call in
  the context (`borrows.spite`, `check_the_lent_body`) and refuses a resizing, library or union
  lend while building the call (embedded: it needs the call's borrows in scope).
- **Checked by**: conformance/lent_to_calls, lent_call_alias, lent_call_function_value, lent_call_kept,
  lent_call_library, lent_call_listed, lent_call_returned, lent_call_union; tests/lent_to_calls, lent_arguments,
  lent_call_written_back, ignored_lent_argument.

### A list element lent to a row

- **Status**: missing.
- **Rule**: a row line calling a singleton function that only reads `list[i]` gets one count per row and takes the
  lock once.
- **Falls back**: a counted call and a lock per call.
- **Checked by**: tests/lent_list_elements, tests/lent_list_elements_parallel (output only).

### An argument its caller holds is passed uncounted

- **Status**: built (as a convention: a function counts only the parameters it assigns again).
- **Rule**: a caller holds what it passes for the whole call, so an argument read from a place the call cannot
  assign is not counted.
- **Falls back**: an argument read from a place the call may assign is counted before the call and let go after.
- **Lives in**: the lowering, `function_lowering.spite` (`note_the_borrowed_parameters`, `is_steady`).
- **Checked by**: tests/held_arguments, tests/held_value_functions.

### An attribute a call cannot assign is passed uncounted

- **Status**: built.
- **Rule**: an attribute path from `this` or a held name whose callee may assign none of its attributes is passed
  uncounted; see `OPTIMIZATIONS.md`.
- **Falls back**: counted before the call and let go after.
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_steady_attribute`), `lowering/assignments.spite`
  (`may_assign`).
- **Checked by**: tests/held_paths.

### A singleton attribute that never changes is read in place

- **Status**: partly built.
- **Rule**: an object attribute of a singleton assigned by no function but its constructor is read from other
  classes as its address, with no count and no lock.
- **Missing**: the per-attribute fact: a singleton is steady only when all its attributes are plain.
- **Falls back**: a counted read.
- **Lives in**: `lowering/singleton_forms.spite`, the passes `made_singletons` and `unread_objects`.
- **Checked by**: tests/singleton_attribute_reads.

### A list's templates read their elements uncounted

- **Status**: built.
- **Rule**: in a template's pass, an element is read uncounted when the rest of the pass cannot let go of an object
  or write a list of the element's class.
- **Falls back**: a counted read.
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_borrowed_local`, `gather_the_sources`).
- **Checked by**: tests/template_lend_drop, tests/fused_chain_allocations, tests/fused_chains, tests/kept_templates,
  tests/member_templates.

### An item written back to its own slot is the slot

- **Status**: partly built.
- **Rule**: between `var item = list[index]` and `list[index] = item`, with nothing between that may change the
  name, the index, the path or the list, the write-back is not written and the read is uncounted.
- **Missing**: a write-back nested in a block, and lists other than a library `List` of numbers or objects.
- **Falls back**: a counted read and the write-back written.
- **Lives in**: the lowering, `function_lowering.spite` (`write_back_of`, `is_a_write_back`).
- **Checked by**: tests/slot_write_backs.

### A value followed through calls is the slot it was read from

- **Status**: missing.
- **Rule**: a call made as a statement that only stores back what each slot already holds is dropped.
- **Falls back**: the call runs.
- **Checked by**: tests/mirrored_write_backs (output only).

### An item a name holds from its list is not counted

- **Status**: built (D992).
- **Rule**: `var item = list[index]` with a proven read, when nothing after it in its block can write the slot,
  holds no count.
- **Falls back**: a counted read; a name kept across a call that may write any list of the item's class keeps its
  count.
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_borrowed_item`), `list_reads.spite` (`held_item`).
- **Checked by**: tests/held_items, tests/slot_write_backs.

### A list item read only to test it is not counted

- **Status**: partly built.
- **Rule**: a presence test of `list[index]` tests the slot in place.
- **Missing**: lists of nullable items, `Items`, and a test of a path through the item.
- **Falls back**: a counted read and its release.
- **Lives in**: the lowering, `function_lowering.spite` (`lower_presence_test`), `list_reads.spite`.
- **Checked by**: tests/tested_items.

### An item used at once is not counted

- **Status**: partly built.
- **Rule**: a proven `list[index]` used once, as a receiver or passed to a call that cannot change the list, is
  read in its slot.
- **Missing**: the item passed as an argument; indices and arguments that are not plain reads.
- **Falls back**: a counted read.
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_held_receiver`, `is_a_held_item`).
- **Checked by**: tests/items_at_once.

### A list held only in a slot of another list

- **Status**: missing.
- **Rule**: inner lists put fresh into a `List<List<T>>` and only used through it live inside the outer list's block.
- **Falls back**: a list of references.
- **Checked by**: tests/nested_lists (output only).

### A list only its class fills holds only what it fills

- **Status**: missing.
- **Rule**: a list attribute filled only by its own class with values the compiler can list decides `==` against a
  value it never holds.
- **Falls back**: the test runs.
- **Checked by**: tests/listed_values (output only).

### A stage registers its passes only in its setup

- **Status**: built.
- **Rule**: a function `register` whose one parameter is a `type` and which appends it to a list of its class, when
  the class's `run` walks that list in a counted loop, may be called only from the class's setup and the functions of the class only the setup calls; a call anywhere else is
  refused, "'Stage.register' is called outside the setup of 'Stage': its passes are registered only in 'Stage()' and
  the functions only it calls, so the compiler knows them and its 'run' is direct calls in order: move this call
  there".
- **Buys**: the setup's list is known while compiling, so `run` is direct calls in order
  ([a list its setup fills holds what the setup made](#a-list-its-setup-fills-holds-what-the-setup-made)).
- **Falls back**: refused.
- **Lives in**: the proof `proofs/registered_in_setup`, an acceptance proof.
- **Checked by**: conformance/register_outside_setup.

### A list its setup fills holds what the setup made

- **Status**: built.
- **Rule**: a list attribute read only by the one function that appends its parameter to it and by counted loops
  over it, written by nothing but its default, and filled only from the class's setup with objects the setup makes,
  holds exactly those objects, in the order the setup made them, whenever a function of the object runs after its
  setup.
- **Buys**: a loop over the list that calls through the list's `type` calls each item's function directly
  ([a walk over a list its setup filled calls each item directly](OPTIMIZATIONS.md#a-walk-over-a-list-its-setup-filled-calls-each-item-directly)).
- **Falls back**: the loop as written; nothing is refused.
- **Lives in**: the proof `proofs/setup_lists`, a speed proof run after the acceptance proofs; it records each walk it
  proves (`HighProgram.setup_list_walks`) for `high_optimization_passes/setup_list_calls`.
- **Checked by**: the compiler's own stages (their `run` is direct calls in its low representation).

### A table filled once holds what its setup put in

- **Status**: partly built (by whole-function evaluation).
- **Rule**: a table filled by one setup function and never changed is read as constants.
- **Missing**: tables held by a singleton or made in another function.
- **Falls back**: the function as written.
- **Lives in**: the pass `low_optimization_passes/compile_time_evaluation`.
- **Checked by**: tests/configured_tables.

## Threads and locks

The rules are in [concurrency.md](../SpiteLanguage/specs/concurrency.md) and, for the counts,
[memory.md](../SpiteLanguage/specs/memory.md#the-memory-model).

### Calls that share nothing written

- **Status**: missing. **Falls back**: the calls run in order. **Checked by**: none.

### Classes in a list that share nothing written

- **Status**: missing. **Falls back**: a plain loop. **Checked by**: tests/row_of_classes (output only).

### Passes that write only their own item

- **Status**: partly built.
- **Rule**: every pass of `list.each_f()` writes only its own element and reads nothing another pass writes, so the
  passes run in bands.
- **Missing**: `Vector`; writes other than the element's number and enum attributes; calls other than its own
  number functions; a kept thread pool.
- **Falls back**: the loop in order.
- **Lives in**: `high_intermediary_representation/building/banded_loops.spite`.
- **Checked by**: tests/band_passes.

### An object made for its owner is told apart

- **Status**: missing. **Falls back**: nothing runs at once, so nothing depends on it. **Checked by**: none.

### No other thread counts a class

- **Status**: missing.
- **Falls back**: every class counts atomically in a program with threads, plainly in one without.
- **Checked by**: tests/plain_counts (output only).

### What one of the calls run at once counts

- **Status**: missing. **Falls back**: atomic counts once threads exist. **Checked by**: none.

### Objects of a class made on one thread

- **Status**: missing.
- **Falls back**: blocks come from each thread's own size lists, through a call.
- **Checked by**: tests/class_pools, tests/threaded_class_objects (output only).

### A copy nothing changes is the original

- **Status**: missing. **Falls back**: the copy is made. **Checked by**: tests/shared_copies (output only).

### Which singletons a `Parallel` reaches

- **Status**: partly built; **fails silently**.
- **Rule**: walk the calls from every function a `Parallel` or the pool can run; a reached singleton is made safe,
  an unreached one takes no lock.
- **Missing**: a `ForeignCallback`'s function is not a root, so a singleton reached only from a callback C calls on
  its own thread takes no lock.
- **Falls back**: locked.
- **Lives in**: `low_intermediary_representation/lowering/waits.spite`.
- **Checked by**: tests/singleton_forms, tests/singleton_race, tests/unshared_locks, tests/singleton_lock_calls.

### No other thread touches a singleton

- **Status**: missing (the second walk over the tree-shaken program).
- **Falls back**: the form the first walk chose.
- **Checked by**: none.

### Read-only and atomic singletons

- **Status**: partly built.
- **Rule**: a singleton nothing changes after it is made takes no lock; one whose changing attributes are numbers
  touched once per function, outside loops, is atomic.
- **Missing**: one lone atomic attribute inside a locked singleton.
- **Falls back**: the whole singleton takes its lock.
- **Lives in**: `lowering/singleton_forms.spite`, `lowering/waits.spite`.
- **Checked by**: tests/singleton_forms, tests/singleton_lock_calls, tests/lone_atomic_counter.

### A function that touches no changing state takes no lock

- **Status**: partly built.
- **Rule**: a function that reads or writes no changing attribute, and calls nothing that does, runs unlocked; a
  call from a locked function to another of the same singleton goes to its unlocked body.
- **Missing**: it tests "never reads `this`", so reading an attribute nothing changes still locks; a call between
  two locked functions takes the lock again.
- **Falls back**: the lock, taken again by its owner.
- **Lives in**: `lowering/waits.spite`, `function_lowering.spite`.
- **Checked by**: tests/singleton_stateless_calls, tests/singleton_function_values.

### Reading functions share the lock

- **Status**: partly built (D988): only for a counted loop that holds the lock.
- **Falls back**: the lock alone.
- **Lives in**: `lowering/waits.spite`, `lowering/coarse_loops.spite`.
- **Checked by**: tests/singleton_reads.

### A counted loop takes a singleton's lock once

- **Status**: built.
- **Rule**: a counted `while` that calls only one singleton's functions and plain helpers, and reaches no wait,
  start or other lock, takes the lock once.
- **Falls back**: a lock per call.
- **Lives in**: `lowering/coarse_loops.spite`, `lowering/waits.spite`.
- **Checked by**: tests/coarse_locks.

### A loop that starts no task tests for tasks once

- **Status**: missing. **Falls back**: the task count is tested on every call. **Checked by**: none.

### No attribute is read past the lock

- **Status**: missing; **fails silently**.
- **Rule**: no attribute of a locked singleton is read or written directly from another class, except a lone atomic
  one.
- **Falls back**: none: a direct `singleton.attribute` read or write from another class runs unlocked, a race.
- **Checked by**: none.

### A lock that would wait forever is an error

- **Status**: built.
- **Rule**: a locked function that waits for a `Parallel` whose work calls back into the same singleton, or a loop
  that never ends inside a locked function, is refused.
- **Falls back**: refused, "'...' waits for '...' while it holds ...'s lock ...: each would wait for the other
  forever ...". A handle passed or returned is not judged.
- **Lives in**: `high_intermediary_representation/building/thread_reach.spite`.
- **Checked by**: conformance/locked_wait, conformance/endless_locked_loop; tests/locked_waits,
  tests/locked_bare_return.

### A loop that can never end is an error

- **Status**: partly built.
- **Rule**: a `while true` with no `return`, `assert` or `crash` that calls nothing is refused; in `Parallel` work
  it is refused when nothing in it waits.
- **Missing**: in `Parallel` work "waits" is "calls nothing but the console", not the waits fact.
- **Falls back**: refused, "this 'while true' never ends: ...".
- **Lives in**: `validators/abstract_syntax_tree/spinning_loop`, `thread_reach.spite` (`refuse_endless_work`).
- **Checked by**: conformance/spinning_loop, conformance/endless_parallel_work; tests/parallel_loop_that_leaves.

### A poll that nothing steps is an error

- **Status**: built.
- **Rule**: a `while` that reads `handle.finished` and calls nothing is refused
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Falls back**: a loop that calls something halts after 1,000,000 polls with no frame stepped.
- **Lives in**: embedded, `statements.spite` (`refuse_an_unstepped_poll`).
- **Checked by**: conformance/unstepped_poll; tests/poll_without_step_halts, tests/finished_polling.

### A write to an object only this function holds must be read

- **Status**: built.
- **Rule**: a write to a local only this function holds (a constructor's result, a copy, an always-new result),
  never read after it, is refused ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Falls back**: not refused where the always-new answer comes from another class.
- **Lives in**: `high_intermediary_representation/building/lost_writes.spite`.
- **Checked by**: conformance/lost_writes.

### A name read from a list, assigned and never read, is an error

- **Status**: built.
- **Rule**: a local read from a list item, then assigned as its last mention, is refused: the list still holds the
  old item ([memory.md](../SpiteLanguage/specs/memory.md#assigning-a-name-read-from-a-list-changes-only-the-name)).
- **Lives in**: `lost_writes.spite` (`check_a_replaced_item`).
- **Checked by**: conformance/replaced_items, conformance/memory_replaced_branch,
  conformance/memory_replaced_answered, conformance/memory_replaced_unwritten; tests/memory_replaced_allowed.

### What a `Parallel` may reach

- **Status**: partly built.
- **Rule**: a `Parallel` work or a `parallel_each_` member reaches only its own value attributes, its locals and
  singletons; it writes a value attribute only of an object handed over to it, never of `this`, an attribute, a
  parameter or a local used again ([concurrency.md](../SpiteLanguage/specs/concurrency.md)).
- **Missing**: reach is followed only through calls of the work's own class.
- **Falls back**: refused, "'...' runs '...' on another thread, so it may reach only ...", or "'Parallel(kept.bump)'
  writes 'count' of this 'Counter' on another thread while this thread may write it too, so one write would be lost
  ...".
- **Lives in**: `high_intermediary_representation/building/parallel_reach.spite`.
- **Checked by**: conformance/parallel_reach, parallel_function_reach, parallel_handover, parallel_shared_writes,
  parallel_shared_value_writes, parallel_held_value_writes, parallel_each_reach_through_call,
  parallel_each_after_map, parallel_each_numbers, foreign_callback_thread_reach; tests/parallel_work,
  parallel_handover, parallel_each, parallel_receivers.

### Which calls suspend a `Concurrent`

- **Status**: built.
- **Rule**: a function given to a `Concurrent` that can wait, and every waiting function it calls, gets a resumable
  copy.
- **Falls back**: a wait the study does not see as such runs the event loop in place.
- **Lives in**: `lowering/waits.spite`, `lowering/machine_writing.spite`.
- **Checked by**: tests/concurrent_waits, waits_never_hang, wait_order, wait_index_order, concurrent_wait_cycle,
  concurrent_wait_cycle_in_place, dropped_handle_waits.

### A wait in a frame is started

- **Status**: built.
- **Rule**: in a loop that sleeps, a call with no arguments and no answer that can wait is started as a
  `Concurrent`, unless either side writes back a value read before a wait
  ([concurrency.md](../SpiteLanguage/specs/concurrency.md#a-wait-in-a-frame-does-not-hold-the-frame)).
- **Falls back**: it waits where it is written, listed under "Waits that hold the frame".
- **Lives in**: `high_intermediary_representation/building/frame_starts.spite`.
- **Checked by**: tests/frame_waits, tests/frame_waits_kept, tests/waiting_systems.

### Reads in a row are independent

- **Status**: missing. **Falls back**: the reads run one after another. **Checked by**: tests/overlapped_reads
  (output only).

## Other refusals built on an analysis

### Unused is an error

- **Status**: built.
- **Rule**: a name, parameter or attribute only written and never read is refused
  ([style.md](../SpiteLanguage/specs/style.md#unused-is-an-error)).
- **Lives in**: `validators/abstract_syntax_tree/unused_names`, and the proof `proofs/every_attribute_is_read`
  for attributes.
- **Checked by**: conformance/unused_names, written_not_read, unused_attributes, template_unused_attribute,
  template_unused_function.

### A constructed object must be kept and used

- **Status**: built.
- **Rule**: a construction written as a statement of its own is refused
  ([classes_and_files.md](../SpiteLanguage/specs/classes_and_files.md#a-constructed-object-must-be-kept-and-used)).
- **Lives in**: `validators/abstract_syntax_tree/dropped_construction`.
- **Checked by**: conformance/dropped_construction.

### Singletons that make each other in a circle are an error

- **Status**: partly built.
- **Rule**: following every attribute of every singleton through the objects those attributes make, a path back to
  the start is refused ([classes_and_files.md](../SpiteLanguage/specs/classes_and_files.md#singleton-rules)).
- **Missing**: the "makes" links: a circle through an ordinary object made in an attribute default.
- **Falls back**: such a circle halts at run time, "spite: singleton ...: singletons initialise each other in a
  circle".
- **Lives in**: `validators/name_resolution/singleton_circle`.
- **Checked by**: conformance/singleton_circle; tests/singleton_circle.

### Build settings are constants

- **Status**: built.
- **Rule**: a flag's value has its field's type, an unknown flag is refused, and an `if` around a `load` is decided
  from Build fields and literals ([programs.md](../SpiteLanguage/specs/programs.md#build-settings-build)).
- **Lives in**: `validators/command_line/known_flag`, `validators/name_resolution/settings`,
  `validators/abstract_syntax_tree/load_statement`.
- **Checked by**: conformance/flag_value, load_unknown_condition, unknown_compiler_flag, bare_flag_not_boolean,
  flag_given_twice, setting_named_like_flag, program_flag, check_and_build_flags, underscore_flag, format_flag.

### A value fits a `type`

- **Status**: partly built; **fails silently**.
- **Rule**: a value fits a `type`, and a `$T` its constraint, on its attributes, its functions, their types and
  not-null ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#inline-types-and-duck-typing-in-full)).
- **Missing**: only a member's existence is checked; an attribute's type and a function's parameter and return types
  are not compared with the type's, and a missing attribute is worded as a missing function.
- **Falls back**: refused, "'...' does not fit type '...': it has no function '...'".
- **Lives in**: embedded, `values.spite` (`filled_shape`, `fits_as_a_class`), `constraints.spite`.
- **Checked by**: conformance/shape_mismatch, shape_function_mismatch, generic_constraints,
  generic_constraint_nullable, generic_constraint_not_a_type, shape_operator_without_function.

### A member template fits

- **Status**: partly built.
- **Rule**: the member a template names exists and has the right kind (a Boolean for `filter_`, a number for
  `sum_`), and a passed function takes the element
  ([collections.md](../SpiteLanguage/specs/collections.md#standard-library-metaprogramming)).
- **Missing**: the specific errors for `map_` of a member that answers nothing, `sort_by_` of a Boolean, a
  non-Boolean `filter_`, `any_` or `all_` (refused by the general condition error), `each` given something that is
  not a function.
- **Falls back**: refused, mostly with a more general text.
- **Lives in**: embedded, `values.spite` (`specialized_over_a_class`), `validators/high_intermediary_representation/typing`.
- **Checked by**: conformance/member_template_mistakes, conformance/passed_functions.

### A value can be written

- **Status**: built.
- **Rule**: the `T` of a JSON or binary writer or reader holds no union, `type` or function value anywhere
  ([json.md](../SpiteLanguage/specs/json.md)).
- **Lives in**: `constraints.spite` (`check_the_written_form`), `serializable.spite`.
- **Checked by**: conformance/json_unwritable, binary_writer_union, binary_object_key.

### What crosses into C

- **Status**: built.
- **Rule**: numbers, Booleans, enums, text, lists of numbers, number-only `type`s and function values cross into C;
  a callback's parameters and context are checked
  ([foreign_libraries.md](../SpiteLanguage/specs/foreign_libraries.md#what-crosses)).
- **Lives in**: `high_intermediary_representation/building/foreign_crossing.spite`.
- **Checked by**: conformance/foreign_call_mistakes, foreign_call_through_parameter, foreign_callback_mistakes,
  foreign_callback_context_literal, foreign_callback_named_directly, foreign_callback_needs_singleton,
  foreign_callback_text_parameter, foreign_callback_text_result, foreign_callback_thread_reach,
  foreign_list_of_text, foreign_type_with_text, foreign_size_of_shape, foreign_literal_arguments.

### The short form is proven the same, and the long form refused

- **Status**: built.
- **Rule**: a `while` a member template already says, a chain of `if`s that is a `switch`, the same call opening
  every branch, a switch that is a class test and a text that is one hole are refused, naming the short form
  ([control_flow.md](../SpiteLanguage/specs/control_flow.md)).
- **Lives in**: `high_intermediary_representation/building/template_walks.spite`,
  `validators/abstract_syntax_tree/switch_chain`, `repeated_branch_call`, `switch_cases`, `lone_hole`.
- **Checked by**: conformance/walk_with_function, argument_walk_without_function, repeated_branch_call,
  repeated_branch_call_chain, switch_chain, switch_chain_else_if, switch_chain_or, lone_hole and its variants.
