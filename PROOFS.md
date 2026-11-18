# Proofs

A **proof** is a fact the compiler establishes while compiling: that a `T?` holds a value here, that an index is in
range, that an object never leaves its function, that no other thread reaches a singleton. With the fact in hand
the compiler **accepts** code it would otherwise refuse, **drops** a check it would otherwise emit, **chooses
cheaper code**, or **refuses** code that would go wrong (D276). A proof emits nothing of its own: what it costs is
the check it leaves in place when it does not hold, and a proof that does not hold never fails silently (D244):
the code is refused, saying what to write, or the run-time check stays.

The rules are the language's, taught in `../spite_documentation` and held by the programs of `../spite_spec`; this page says, for each proof, what this compiler does
with it. Each section has the same parts:

- **Status**: built, partly built (what is missing is its issue labelled `proof`), or
  missing.
- **Rule**: what is proven and how, with a link to the documentation page that teaches it.
- **Buys**: the code accepted or refused, the check dropped, the cost saved.
- **Falls back**: when it does not apply, what the compiler does and what the user writes.
- **Lives in**: the pass or the file that makes it. A proof is a pass of its own (D1086), in `proofs/<name>/`; a
  proof still made inside a step or another pass says "embedded", and moving it out is an issue.
- **Checked by**: the `../spite_spec` programs that pin it (`tests/` must run, `conformance/` must be refused).

Two kinds of proof run at two places (D1086, D1072). A proof that decides whether code is **accepted** runs on the
high representation once it is built and before any optimisation pass, so what a program may say never depends on
how well it is optimised. A proof that only makes code **cheaper** runs where its facts exist (after inlining, for
placing objects in the frame) and records its fact; the optimisation passes read those facts rather than proving
anything themselves. A proof on the low representation is a `LowProof`, in its own folder of `proofs/` like every
proof, registered among the low passes right before the pass that reads its facts. `ARCHITECTURE.md` lists the
order.

Of the 92 proofs the old compiler made, 41 are built, 31 are partly built and 20 are missing (audit of
2026-10-24, with what was built since). Where a proof is partly built and what is missing could let a wrong program through, the section says
**fails silently**: that is a D244 bug and its issue is labelled `urgency: silent` and comes first.

## What the builder records for the proofs

The builder decides what each piece of code is (the type of every read, which branch of a decided condition is
compiled), so the facts that decide a type stay in it: narrowing, the bounds and counts that make a `[]` read a `T`,
and the conditions it folds. What it no longer does is refuse: where a proof needs what the builder resolved, the
builder records the site, with that data, in its context (`HighProgram.context`), and builds on as if the code were
right; the proof judges every recorded site after the build, in the order they were built, with the same validator and
the same text. A refused program never reaches the lowering, so what the builder made past a recorded site is never
used.

| Site | Recorded by | What it holds | Judged by |
|---|---|---|---|
| `StatementSite` | `statements.spite` (`note_a_block`, `note_a_statement`), every block entered and left and every statement of the program's own code, before it is built | the statement list and index, the blocks around it, the line, and a `ScopeView`: every name in scope with its internal name, its narrowed type and its declared type | `proofs/lost_writes` |
| `PresenceSite` | `values.spite` (`note_a_maybe_null`, `note_a_maybe_null_type`), `statements.spite` (`note_a_maybe_boolean`) | a value that may be null where a value is needed: its type, the value (for the list read it came from), what was wanted, the member or operator | `proofs/present_values` |
| `CheckSite` | `statements.spite` (`note_a_proven_check`, `note_a_proven_read_check`, `note_a_check_of_a_plain_value`, `note_a_narrowed_copy`) | the check written and what the scope says already proved it, the checked type, the copy and its source | `proofs/proven_checks` |
| `CheckSite` | `assignments.spite` (`note_an_undone_loop_check`, `note_an_undone_path`) | a path assigned a value that may be null inside a loop: whether it was narrowed before the loop and read in it, or whether the end of the body left it narrowed | `proofs/loop_narrowings` |
| `GuardSite` | `crashes.spite` (`default_return`), `statements.spite` (`note_a_terminal_if`) | a guard `fallback` with no "nothing" to answer, or an `if` that may be the last statement | `proofs/guard_asserts` |
| `SwitchSite`, `VectorSite` | `switches.spite`, `constraints.spite` | a switch's cases and members, a `Vector` made | `proofs/switch_cover`, `proofs/vector_fit` |

`building/function_entry.spite` puts a proof back inside the function of a site (its class, its function, its line,
and the member a member template binds), so a validator names the same place it named while building.

The builder also lists every site in the order it recorded them (`context.recorded_sites`), and the proof
`proofs/recorded_sites` walks that list, handing each site to the proof of its kind (a statement to `lost_writes`), so the first error is the one in the earliest code, whichever proof finds it. A refusal
the builder still makes itself first asks the same walk to judge what was recorded before it
(`Context.judge_what_is_recorded`, from `EveryRule.tell`; the proofs stage hands its walk to the high
representation stage before the build), leaving out `present_values`, since "every assignment is present" is only known once
every function is built ([A failure stops its own check](ARCHITECTURE.md#a-failure-stops-its-own-check)). The rules of
the syntax tree that need the built program run as the proof `proofs/rules_after_building`, right after the walk.

## Presence and control flow

### Narrowing a `T?`

- **Status**: built.
- **Rule**: only a call-free name or path narrows, for every fact a condition proves (presence, a class, a count, a bound): a path holding a call anywhere (`thing.pop().held`, `items[next()]`) narrows nothing, since writing it again calls again, except the list of a `[]` read (`crash Store<$item>().values[index]`), whose proven read still tests what it finds; `if` narrows its block and not its `else`; `fallback` and `crash`
  narrow the rest of the block; `while` narrows its body; a `switch` `T:` case narrows its case; one check narrows
  every link of the path before it. It tests presence, never the value
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently),
  [control_flow.md](../spite_documentation/control_flow.md)).
- **Buys**: reads, calls and stores through a `T?` are accepted, and the narrowed read has no test.
- **Falls back**: refused, "this value may be null (it is a ...), so '...' cannot be read from it yet: narrow it
  first with 'if value { }', 'fallback value' or 'crash value'". Put a call's result in a `var` and narrow that.
  A path through a getter narrows like an attribute while the getter only reads ([A getter narrows while it only reads](#a-getter-narrows-while-it-only-reads)).
- **Lives in**: the narrowing itself is building, since it decides the type of every read:
  `high_intermediary_representation/building/statements.spite` (`read_facts`, `read_a_fact`, `narrowed_block_of`),
  `scope.spite` (`narrow`), `reads.spite` (`narrowed`), `operators.spite` (`with_its_links`). The refusal of a value that may be null
  where a value is needed is the proof `proofs/present_values`, which judges every `PresenceSite` the builder
  recorded (`values.spite`: `note_a_maybe_null`), a `Boolean?` condition among them: it proves what is present and
  hands the site to `validators/high_intermediary_representation/present_value`, which decides by its kind.
- **Checked by**: tests/path_narrowing, tests/present_zero, tests/nullable_narrowing, tests/narrowed_path_kept,
  tests/narrowed_read_local, tests/while_narrows, tests/nullable_switch_null_case; conformance/store_through_nullable,
  conformance/path_narrow_else, conformance/sibling_path_unnarrowed, conformance/maybe_boolean_conditions,
  conformance/null_comparison, conformance/call_path_after_if_does_not_narrow,
  conformance/call_path_after_while_does_not_narrow, conformance/call_path_after_crash_does_not_narrow,
  conformance/call_path_after_fallback_does_not_narrow.

### Every side of an `and` narrows

- **Status**: built, wider than the old rule.
- **Rule**: each side of an `and` holds where the whole holds, and later sides see the earlier ones narrowed; the
  right side of an `or` sees the left side's opposite. This holds in every condition, `while` and a plain
  expression included, and a `while` body starts with every side of its `and` narrowed. No side of an `or` narrows
  where the whole holds ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: one line proves several reads (`if node and node.ready`).
- **Falls back**: the sides are tested in order, so a later side is never read unproven.
- **Lives in**: embedded, `statements.spite` (`read_a_binary_fact`), `loops.spite` (`read_a_present_side`),
  `operators.spite` (`logic_value`, `right_condition_of`).
- **Checked by**: tests/and_narrowing, tests/and_return_narrowing, tests/while_and_narrows;
  conformance/while_or_proves_nothing, conformance/while_and_or_proves_nothing,
  conformance/while_and_inner_or_proves_nothing, conformance/while_and_not_proves_nothing,
  conformance/while_and_proves_nothing_after_the_loop, conformance/while_and_attribute_written_in_the_body,
  conformance/while_and_local_written_in_the_body, conformance/while_and_written_in_a_branch,
  conformance/while_and_written_around_an_inner_loop, conformance/while_and_earlier_link_written,
  conformance/while_and_item_written_in_the_body, conformance/while_and_call_in_the_body,
  conformance/while_and_write_through_another_object.

### An `if` that leaves proves the rest

- **Status**: built.
- **Rule**: after an `if` with no `else` whose block always leaves (a `return`, a bare `crash`, a `switch` whose
  every case leaves, an `if`/`else` that both leave), the opposite of its condition holds: each `or`
  side written `not path` narrows that path, each side read with the sides before it narrowed (`if not holder or
  not holder.weapon { return }` proves both), and other sides turned around prove `[]` reads and divisors
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently),
  [control_flow.md](../spite_documentation/control_flow.md#switch-over-values)).
- **Buys**: guards read as answers: `if not monster { return }` and the rest reads `monster`, and `if not found or
  found.count() == 0 { return }` proves `found[0]`.
- **Falls back**: the rest stays unproven, and a read of it is refused.
- **Lives in**: embedded, `statements.spite` (`build_if`, `read_a_negated_fact`, `read_a_negated_binary`,
  `note_the_leaving_if`), `endings.spite` (`always_leaves`), `ranges.spite` (`prove_an_if`).
- **Checked by**: tests/leaving_if, tests/returning_branch_proof, tests/control_switch_leaving_narrows,
  tests/leaving_or_narrows, tests/leaving_count_side; conformance/leaving_if_proves_nothing.

### Assigning undoes a proof

- **Status**: built.
- **Rule**: assigning a narrowed path, or anything it reads through (an index name included), undoes every proof
  beneath it: an attribute assigned by its bare name undoes the paths written from it (`target.weapon` after
  `target = Monster()`), a store through a setter undoes its path, and `list[i] = value` undoes what was proven
  below the items, and every item's narrowing when the value may be null; assigning it a value that cannot be null
  keeps its own narrowing. Inside a `while`, assigning a value that may be null to a path narrowed before the loop
  and read in it is an error: for an attribute at once, for a local or a parameter when the end of the body leaves
  it unnarrowed (a check later in the same pass keeps it). An assignment in a block that always leaves undoes nothing
  after that block, and no next pass reads it, when the block sits inside the loop that holds the assignment; every
  other path keeps it undone: a block that falls through, an `else` that falls through, a loop inside the leaving
  block that goes around. An `else` starts from what was proven before its `then`, and after the `if` a path stays
  narrowed only where every branch that falls through kept it (`Scope.start_the_other_branch`, `join_the_branches`)
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: nothing stale is read: a narrowed read has no run-time test.
- **Falls back**: refused, "assigning to '...' inside this loop undoes a narrowing made before the loop, and the
  next pass would read it unproven: narrow it inside the loop instead"; after the assignment, a read is refused
  until it is proven again.
- **Lives in**: forgetting is building, `assignments.spite` (`assign_a_name`,
  `assign_an_attribute`), `statements.spite` (`forget_the_stored_items`, `finish_a_stretch`), `context.spite` (`note_the_loop_writes_left_behind`), `scope.spite` (`forget`, `forget_below`, `forget_below_the_items`, `keep_present`, `hold_the_narrowings`, `let_go_of_the_narrowings`); the
  refusals in a loop are the proof `proofs/loop_narrowings`, judging what `note_an_undone_loop_check` and
  `note_an_undone_path` recorded.
- **Checked by**: tests/narrowed_value_assignment, tests/proof_again_in_loop, tests/narrowing_snapshot_copy,
  tests/loop_narrows_its_local_again, tests/narrowed_past_a_same_path_write_that_returns;
  conformance/same_path_write_falls_through, conformance/same_path_write_in_an_else,
  conformance/same_path_write_in_both_branches, conformance/same_path_write_in_a_then_that_stays,
  conformance/same_path_write_in_a_branch_that_may_stay, conformance/same_path_write_before_a_loop_that_may_stay,
  conformance/same_path_read_after_the_write, conformance/same_path_write_in_a_switch_case_that_stays,
  conformance/same_path_write_around_a_loop, conformance/same_path_write_around_a_loop_in_a_leaving_block,
  conformance/alias_write_around_a_loop_in_a_leaving_block,
  conformance/same_path_write_around_a_loop_that_may_stay, conformance/same_local_write_around_a_loop_that_may_stay,
  conformance/same_item_write_falls_through; conformance/narrowed_name_reassigned, conformance/path_narrow_assignment,
  conformance/path_narrow_loop, conformance/narrowed_path_undone_below, conformance/narrowed_local_undone_in_loop,
  conformance/assigned_start_undoes_narrowing, conformance/index_store_undoes_narrowing.

### A call keeps a proof it cannot change

- **Status**: built, for every narrowing a read relies on without a test and for the `[]` and count proofs, which keep a test.
- **Rule**: a narrowed attribute read is refused when a call built between the check and the read may assign that
  attribute, followed through everything the call reaches, or when a write through another object that could break what was proven sits between them: a value that may be null,
  or one of another class than the narrowed one (not one to the same path, which the builder already follows, nor one to an object made in the same function and not handed on yet).
  A call or a write that may assign an earlier attribute of the path counts whatever it writes, since it changes which object is read.
  One in a block that always leaves does not reach a read after that block, nor a read before it in that block when the block sits inside the read's own loop (`NarrowedRead.is_left_behind`); a block that falls through, and a loop that goes around after it, still count.
  A call in a condition counts: `fallback` and `crash` log theirs, and a fact of an `and` (or of the `or` of a guard that leaves) is proven before any call on a later side, while a fact on a later side is proven after it (`statements.spite`: `note_the_facts_before_a_call`, `log_a_condition_that_calls`; `operators.spite`: `right_condition_of`, for what a later side reads).
  A write of a value of the narrowed type leaves the proof true, whichever object it reached. What a call may assign is decided by the attribute's
  class and name: a constructor's writes to its own object and writes to an object made in the same function, before
  it is stored, copied, passed, called on, taken with a function or returned (for a local made before a loop, before
  the loop if the body hands it on), are not writes to anything a proof reads (`Assignments.hand_on`, which marks the write `is_to_a_fresh_object`); a wait writes nothing in a program that makes no `Concurrent` or
  `Parallel`, and anything in one that does; a call through a function value reaches the functions taken as values
  with its signature anywhere in the program, whichever function is read first (`Assignments.call_a_value`, and
  every function taken as a value only when none is taken with it), and a function that only calls its parameters reaches the functions each caller passes it; a
  foreign call reaches the functions handed to a `ForeignCallback` (`Assignments.note_a_callback`), which C may call
  back, and through them what they call and take as values, never every function value; a
  `drop()` that may run is followed too. Inside a loop, a call anywhere in the body undoes a narrowing made before
  the loop for the next pass ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
  "Before the loop" is told by the scope the narrowing lives in (`NarrowedRead.proven_in_frame` against the loop's
  base, `statements.spite`: `extend_the_reads_over_the_loop`), not by the calls logged since, so a check right
  before the `while`, with nothing logged between, counts too; a copy made right before it the same way. A check
  of the same path still in force at the end of the body proves it for the next pass, so only what comes after that
  check counts there (`NarrowedRead.next_pass_start`, `statements.spite`: `note_what_the_next_pass_starts_proven`):
  `while target.name != "dragon" { forget_target() crash target }` stands.
- **Buys**: no re-check after a harmless call; a call that may null what was proven is never read past.
  A read proven by a `[]` or count proof (`NarrowedRead.watched_lists`) is refused past a call that may shrink its list, whatever the call's answer is used for: `Assignments.note_a_shrink` writes a key for each shrinking call in the program's own code, by the attribute that holds the list, or by the list's class when a parameter or another list's item reaches it. A `fallback`, `crash` or `if` on the same read after a call tests the list again and proves it anew. A local made in the function and not handed on is not counted, and neither is what the library does inside its own functions, since a call of a library function that shrinks is itself the shrinking call.
  A local that may hold a list held elsewhere (a parameter, a local given anything but a list made there or answered new by the library (a `copy()`, a `split`, not an item), and a made list once it is stored, passed or given to another local: `HandedLists`, `Context.shared_lists`) is watched by every read of a list of its type, judged against every such local of the whole function, and a local list nothing else can hold is watched only through its own name, so `var alias = items`, `alias.clear()` and `given.clear()` on a parameter that is the attribute are refused before `items[0]`. A call or a write that may assign the attribute holding the list, or an attribute on the way to it, counts as a shrink (`shelf.renew()` assigning `items`; `Writes.renews_a_list`). A count kept in a `var` proves from the line it was counted (`Context.counted_starts`, `Statements.stamp_the_kept_counts`), so a shrink between the count and the read, or anywhere in a loop around the read, is refused.
  A call counts from where it runs in its statement: every call, a getter's included, is logged as it is built (`Context.log_a_call_as_it_is_built`, from `Values.value_of`), so `cleared(alias) + rack.item.number`, a comparison, a text hole, a list item, an index after the list, or an argument of a call on an earlier call's answer is refused like a read on the next line, while a read before the call in the same statement keeps its proof. A getter on a later side of a condition counts like a call (`WrittenGetters`).
  A call or a write in a `then` does not reach a read in its `else` (`NarrowedRead.is_on_another_branch`), unless the read was proven before a loop around both.
- **Falls back**: refused, "'keeper.target' was proven before line 12, where 'forget(...)' may assign 'target'
  again, so this read would use what the call left there, unproven: prove 'keeper.target' again after that line"
  (a list: "'items[0]' was proven before line 9, where 'trim(...)' may shrink what it reads, so this read may fall outside it: prove 'items[0]' again after that line");
  in a loop, at the call, "'forget(...)' inside this loop may change 'target', which undoes what was proven about
  'keeper.target' before the loop, and the next pass would read it unproven: prove it inside the loop instead". The
  message names the function that writes when it is not the one called.
- **Lives in**: the pass `proofs/narrowings_kept_across_calls` (its own folder), run on the high representation
  once every function is built. The builder records each narrowed read
  (`high_intermediary_representation/narrowed_read.spite`, `reads.spite`: `note_a_narrowed_read`) with the calls
  built since its check (`statements.spite`: `log_the_calls_of`); what a call may assign is
  `high_intermediary_representation/assignments.spite` read for narrowings (`read_for_narrowings`).
- **Checked by**: tests/receiver_call_effects, tests/same_name_call_effects, tests/foreign_callback_keeps_proofs,
  tests/value_call_reaches_functions_taken_later,
  tests/narrowing_kept_across_harmless_call, tests/copy_right_before_a_loop_is_kept;
  conformance/call_in_loop_right_after_the_check_undoes_narrowing,
  conformance/own_call_in_loop_right_after_the_check_undoes_narrowing,
  conformance/getter_read_in_a_loop_right_after_the_check; conformance/condition_call_after_the_if_fact,
  conformance/condition_call_after_the_while_fact, conformance/condition_call_before_a_later_side,
  conformance/condition_call_before_a_later_while_side, conformance/condition_call_in_a_leaving_or,
  conformance/condition_call_before_the_right_of_an_or, conformance/condition_call_in_a_plain_value,
  conformance/condition_call_in_a_while_inside_the_fact, conformance/condition_call_before_its_else,
  conformance/fallback_call_undoes_proof, conformance/crash_call_undoes_proof, conformance/fallback_and_call_undoes_proof,
  conformance/crash_and_call_undoes_proof; conformance/call_undoes_proof, conformance/branch_undoes_proof,
  conformance/receiver_call_undoes_proof, conformance/count_undoes_proof, conformance/bound_proofs_undone,
  conformance/structural_index_undone, conformance/call_on_other_undoes_narrowing,
  conformance/call_in_loop_undoes_narrowing, conformance/shrink_undoes_proof_*, conformance/foreign_callback_shrink_undoes_proof, tests/shrink_keeps_the_proofs_it_cannot_reach,
  conformance/narrowed_past_a_write_to_an_earlier_attribute,
  conformance/narrowed_past_a_write_to_an_object_handed_on, tests/narrowed_past_filling_a_new_object.

### A getter narrows while it only reads

- **Status**: built (spite_compiler#370).
- **Rule**: a path read through a getter (`thing.reading` running `get_reading()`) is narrowed by a check like an
  attribute, and each read runs the getter again. A getter that reaches a write of any attribute, or a foreign call,
  may change what it answers, so a read of it after the check is refused. One that only reads keeps the proof
  until a call or a write between the check and the read may assign an attribute it reads, followed as in
  [A call keeps a proof it cannot change](#a-call-keeps-a-proof-it-cannot-change). `if`, `while`, `crash`, `fallback`
  and `switch` agree, since all narrow the same path.
- **Buys**: a getter that only reads needs no copy to be read twice; one with an effect is never trusted on its
  second answer.
- **Falls back**: refused, "'thing.reading' calls 'get_reading' again here, and 'get_reading' may change what it
  answers, so the check before proves nothing about this read: hold it once with 'var held = thing.reading' and
  narrow 'held'"; past a change, "'thing.plain' was proven before line 8, where 'clear(...)' may assign 'store',
  which 'get_plain' reads, so this read would call it again unproven: prove 'thing.plain' again after that line"
  (a write: "this write"; in a loop, at the change, "... inside this loop may assign 'store', which 'get_plain'
  reads, ..."). A read the proof could not see change still tests what the getter answers, and halts, "'thing.plain'
  was proven present, but reading it again answered nothing, since what it reads changed after the check".
- **Lives in**: `reads.spite` (`note_a_getter_read`), the pass `proofs/narrowings_kept_across_calls`
  (`check_a_getter_read`), `assignments.spite` (`may_have_an_effect`, `attributes_read_by`), and
  `low_intermediary_representation/lowering/conversions.spite` (`missing_words_of`).
- **Checked by**: tests/getter_that_only_reads_keeps_narrowing, tests/copy_of_a_getter_with_an_effect_is_kept;
  conformance/getter_with_an_effect_after_if, conformance/getter_with_an_effect_after_while,
  conformance/getter_with_an_effect_after_crash, conformance/getter_with_an_effect_after_fallback,
  conformance/getter_with_an_effect_after_switch, conformance/getter_read_after_a_call_that_changes_it,
  conformance/getter_read_after_a_write_that_changes_it.

### An address keeps its owner alive

- **Status**: built, by construction.
- **Rule**: an address read out of an object counts as a use of that object, so the object is let go only after the
  address's last use ([memory.md](../spite_documentation/memory.md)).
- **Buys**: no address outlives its object.
- **Falls back**: nothing to fall back to: the library has no `Memory.Address`, and every object is let go at the
  end of its block or statement, never earlier. The rule comes back with addresses or with a release at last use.
- **Lives in**: `low_intermediary_representation/lowering/statements.spite` (`lower_block`) and `counting.spite`
  (`release_the_pending`, `is_the_last_use`).
- **Checked by**: none.

### Proving what is proven is an error

- **Status**: built (D1445 to D1447).
- **Rule**: a check of a `T?` already narrowed (by a `fallback`, a `crash`, the `if`, `while` or `switch` around
  it), a `[]` read already proven (by a bound, a count or an earlier check), a divisor already proven (`name != 0`
  after `name != 0` or `name > 0`, `name > 0` after `name > 0`), a class test the type already answers, the same
  call-free condition on the very next statement of the same block, a `fallback`/`crash` that folds true, and a check
  of a value that cannot be null are refused, naming where it was proven
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
  Where the check is a line of its own or an `if`, in a program's own file, `fixes/after_building` rewrites it before the refusal.
  A check after a write or a call that undoes the proof is a new proof, not a repeat: the builder reads the attribute itself for it
  (`Values.note_a_rechecked_read`) and narrows again, and only the whole build answers which it is, by what `a call keeps a proof` answers (`KeptCopies.may_change_under`).
  A class test the type answers, after such a write, is left to that rule's refusal, and proving the value first (`fallback holder.figure`) forgets the class.
- **Buys**: no dead checks in the source.
- **How**: inside a `while`, only a proof made inside that loop makes a check redundant (the frame of the scope the
  path was narrowed in is compared with the loop's), since an assignment later in the loop would leave the next
  pass unproven. A narrowed `Boolean` is not refused when tested again, since an `if` on it tests its value. A folded
  `fallback` is one that asks a compile-time question (a call such as `has_function`, or a `Build` field); a presence
  check that folds is judged as a plain value or a proven read instead; any other folded condition that is not a
  bare name is refused too (D1746). The
  class test and the folded `fallback` are refused only outside a generic class and a walk, where they fold per
  instance, and outside the library and the compiler's generated files. A local is plain when its value cannot be
  null, whatever made it (D1447: a call's answer, a copy of an attribute or another local, a proven `[]` read);
  in a generic class or a walk only a written type or a construction makes it plain, since its type may differ per
  instance. The plain-value refusal judges a local by the type it is declared with (written, or the type of its first
  value), so a local declared `T?` and narrowed since is refused as narrowed instead.
- **Falls back**: the redundant check is refused; a check the compiler cannot prove redundant (two equal checks
  with a statement between, a condition with a call, a stronger check after a weaker one) stays.
- **Lives in**: the proof `proofs/proven_checks`, judging what `statements.spite` recorded
  (`note_a_proven_check`, `note_a_proven_condition`, `note_a_proven_read_check`, `note_a_check_of_a_plain_value`,
  `note_a_repeated_check`, `note_a_proven_divisor`, `note_a_check_that_always_holds`, `note_the_checks`,
  `note_one_check`) and `operators.spite` (`note_an_answered_class_test`). The proof proves the check redundant,
  tries its fix, and hands the site it could not fix to `validators/high_intermediary_representation/proven_check`,
  which words it by its kind.
- **Checked by**: conformance/check_proves_nothing, conformance/known_fact_checked, conformance/proven_element,
  conformance/proven_index_check, conformance/assert_on_plain_value, conformance/leaving_if_proves_nothing,
  conformance/crash_on_plain_local, conformance/known_fact_inside_its_if, conformance/known_fact_divisor,
  conformance/known_fact_next_line, conformance/known_fact_class_never, conformance/known_fact_class_again,
  conformance/proven_element_by_count, conformance/proven_element_by_earlier_check,
  conformance/check_always_holds, conformance/check_of_a_returned_local, conformance/check_of_a_copied_local.

### A copy made to narrow is an error

- **Status**: built (D1447).
- **Rule**: a `var` holding a bare name or path of a `T?`, never assigned again and whose source is not assigned in
  the function, then narrowed (by `fallback`, `crash`, `if`, `while`, `switch`, `not` of it or an `and` side), is
  refused: narrow the source itself. `if not copy { }` tests it whether or not its block leaves. A snapshot taken
  before its source changes is allowed
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
  A path holding a written call is never a copy's source, since writing it again calls again; a copy through a getter keeps a value when the getter may have an effect, or when a call or a write before the read may assign what it reads (`kept_copies.spite`: `getter_may_change_under`), and one through a getter that only reads is a copy like any other.
  A local whose source (an attribute, or one along its path) a call or a write through any object may change between the copy and a read of the local keeps a value, so it is not a copy: the builder records those reads as `NarrowedRead`s with their `copy_line`, and `proven_checks` asks the question `narrowings_kept_across_calls` asks.
  The fix renames every use of the copy, and a copy of a copy names the first source: each `Fixes.Renaming` also renames a path an earlier one wrote that starts at its name, and rewrites the source of a later one in the same function that does (`fixes.spite`: `rename_every_use`).
- **Buys**: one name per value.
- **Falls back**: refused, "'watcher' only copies 'tracker' so it can be narrowed: narrow 'tracker' itself ('fallback
  tracker') and use it directly".
- **Lives in**: the proof `proofs/proven_checks`, judging each copy `statements.spite` recorded when the copy is
  narrowed (`note_a_copy`, `note_a_narrowed_copy`, `note_a_loop_copy`, `note_a_tested_copy`, `build_switch`), and
  refused by `validators/high_intermediary_representation/proven_check`.
- **Checked by**: conformance/copy_to_narrow, conformance/library_copy_to_narrow, conformance/copy_to_narrow_conditions,
  conformance/copy_to_narrow_not_leaving, conformance/copy_to_narrow_of_a_copy, conformance/copy_to_narrow_of_a_kept_copy; tests/narrowing_snapshot_copy, tests/copy_of_a_getter_with_an_effect_is_kept,
  tests/copy_of_a_path_holding_a_call_is_kept, tests/copy_of_a_getter_before_a_change_is_kept, conformance/namespace_nullable.

### A literal that converts is a `T`

- **Status**: built (D1874, D1888).
- **Rule**: a conversion that answers `T?` is worked out while compiling when the value it reads is written at that
  very place: literal text with no hole, or a literal number with its sign. A conversion that answers a value is a
  present `T`; one that answers `null` is a compile error naming the literal and the conversion. An enum read by the
  compiler's own conversion is decided where it is written, with no evaluation.
- **Buys**: `var paint: Color = "#ff8000"` and `client.connect("127.0.0.1", 8080)` need no narrowing, and a mistyped
  literal cannot reach a run.
- **Falls back**: the evaluator (`proofs/literal_conversions/evaluator.spite`) walks the high representation over its
  own model of objects; it stops, and the value stays the run-time `T?` it is declared, at anything only a run can do:
  a foreign call other than `strtod`/`strtof` of `ucrtbase.dll`, a singleton, a write through a `this` it did not
  make, a function value, a reflected class, a `stop`, an arithmetic that would halt or overflow, a read past a
  buffer, or more than 1 000 000 steps for one literal (20 000 000 for the program). A local holding a literal is not
  a literal, an interpolated text is not one, and neither is text joined with `+`. A check of one such value is the
  "already narrowed" error of the next section.
- **Lives in**: `proofs/literal_conversions` (run first of all by `proven_present`, so its facts feed the rest;
  its refusals are judged in `recorded_sites` in the order built, in `validators/high_intermediary_representation/literal_conversion`),
  and the builder's `note_a_literal_conversion`, `text_literal_read_into_an_enum` and `number_literal_read_into_an_enum`.
  It runs in every build, `--check`, `--development`, `--hot-reload` and `--repl` too.
- **Checked by**: tests/literal_conversion_*; conformance/literal_conversion_*.

### A value proven present is a `T`

- **Status**: built (D1719): locals, attributes and answers, and the literal conversions the proof above decides.
- **Rule**: a `T?` the compiler proves present is a `T` where it is read, with nothing written: a local every
  assignment of which in its function is present, an attribute of a program class whose default and every
  assignment anywhere in the built program are present, and a function of the program every `return` of which is
  present, at every call of it. A value is present when its type is not a `T?`, when it is a read of a proven local
  or attribute or a call of a proven function, or a `T` made a `T?` to fit; a read of the name itself (a copy
  assigning an attribute from the same attribute) and an `else` taken only when the name tested is null keep the
  proof. The proofs are run together until neither proves more, so a local holding a proven answer, or an answer
  returning a proven attribute, is proven too
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: `var shown: Monster? = Monster()`, never assigned null, reads `shown.name` with no narrowing; an
  `fallback`, `crash` or `if` on such a name is the "already narrowed" error: "'shown' is already narrowed by the
  proof that every value it can hold is present: remove this check".
- **Falls back**: not proven, and read as the `T?` it is declared, when any assignment may be null, a `T?`
  parameter is read, an attribute has no default or belongs to the library or to a `Spite.` class, an attribute of
  that name is assigned a `T?` through a `type`, or the function belongs to the library (whose answers are the
  contract every target keeps, D1721). The refusal of a check is made outside a generic class and a walk only,
  where a name's type may differ per instance; a check of a call (`crash find()`) is never refused, since a dropped
  answer must be used. A proven `Boolean?` is a condition, and a proven `Spite.Class` or function value held in
  an attribute or a local is called, with nothing written (D1746). A `while` on a proven name is refused like an
  `if`.
- **Lives in**: `proofs/proven_present`, which runs `proofs/present_assignments` and `proofs/present_answers` until
  neither proves more, before `recorded_sites`, recording `PresenceFacts` on the builder's context
  (`high_intermediary_representation/presence_facts.spite`); `proofs/present_values` accepts a use of a proven
  value, and `proofs/proven_checks` refuses a check of one (`statements.spite`: `note_a_check_of_a_proven_value`).
  When the builder refuses something before the proofs run, the proofs are made over the functions built so far,
  so that the earliest error is told.
- **Checked by**: tests/proven_present_local, tests/proven_present_attribute, tests/proven_present_answer,
  tests/proven_present_uses; conformance/proven_present_checked, conformance/proven_present_attribute_checked,
  conformance/proven_present_while_checked.

### A live build proves no attribute

- **Status**: built (D1746).
- **Rule**: in a `--hot-reload` or `--repl` build only locals are proven present; an attribute is read as the
  `T?` it is declared, so a null an older version of the program left in a running object is still checked
  ([repl.md](../spite_documentation/repl.md)).
- **Buys**: a reload or a REPL assignment can never break a proof the running objects were built under. Those builds
  are for iteration time, not for the checks a proof drops.
- **Falls back**: the attribute keeps its narrowing: a check of it is written and is not the "already narrowed" error.
- **Lives in**: `proofs/present_assignments` (`is_an_eligible_attribute`), told by `proofs/proven_present`.
- **Checked by**: tests/proven_present_hot_reload, tests/proven_present_repl.

### A class test narrows its block

- **Status**: built, wider than the old rule.
- **Rule**: `if value == Monster { }` narrows the block to `Monster`, on a name, a member path, or a side of an
  `and`; a null tests false; in a generic class a test that cannot hold folds to false; `!=`, the `else` and a
  leaving `if` narrow nothing ([values_and_types.md](../spite_documentation/values_and_types.md#unions)).
- **Buys**: a member's attributes and functions are read inside the block.
- **Falls back**: a member read without the test is refused; use a `switch`.
- **Lives in**: embedded, `statements.spite` (`read_a_binary_fact`), `operators.spite` (`class_test_value`, `same_class`).
- **Checked by**: tests/class_test, tests/generic_class_test, tests/codegen_class_test, tests/null_class_test_false,
  tests/tested_classes; conformance/class_test_not_member.

### Every path ends in a `return`

- **Status**: built.
- **Rule**: a path ends at a `return`, a bare `crash`, an `if`/`else` whose branches both end, a `switch` whose every
  case ends, or a folded condition whose taken branch ends; a function that answers something and
  has a path that reaches its end is refused ([failure.md](../spite_documentation/failure.md#fallback-is-a-guard)).
- **Buys**: no caller gets a value nobody wrote.
- **Falls back**: refused, "'...' answers ..., but ... it reaches its end without a 'return' ...: end that path with
  'return <value>', or with 'crash' if it cannot happen".
- **Lives in**: `validators/high_intermediary_representation/missing_return`, run by the builder on each function
  body, asking `high_intermediary_representation/building/endings.spite` (`always_leaves`) whether a path leaves.
- **Checked by**: conformance/falling_end; tests/every_path_returns, tests/control_while_running.

### A fallback answers what its answer type builds with no arguments

- **Status**: built.
- **Rule**: a `fallback` whose condition fails returns what the function's answer type builds with no arguments
  (D1765): nothing, `null` for a `T?`, `0` for a number, `false`, `""`, an empty collection, or the object of a class
  with no constructor or a constructor without parameters. It is refused where the answer type has no such value (an
  enum, a class whose constructor takes arguments, a singleton) and in a constructor; an `if` that only returns that
  value, or a last `if` with no `else` that only checks presence, is refused naming the `fallback`
  ([failure.md](../spite_documentation/failure.md#fallback-is-a-guard)).
- **Buys**: a guard written once, whose answer the answer type states.
- **Falls back**: refused, "'fallback' returns what the answer type builds with no arguments, and a ... has none ...".
- **Lives in**: `crashes.spite` (`default_return`, `is_built_with_no_arguments`), the proof `proofs/guard_asserts`,
  judging every `fallback` whose answer type has no such value and every `if` the builder recorded
  (`note_a_terminal_if`), and `validators/abstract_syntax_tree/default_guard`.
- **Checked by**: tests/fallback_answers, conformance/default_answer_enum,
  conformance/fallback_built_with_arguments, conformance/default_guard, conformance/returning_guard,
  conformance/empty_collection_guard, conformance/terminal_if, conformance/library_terminal_if, conformance/assert_in_constructor,
  conformance/constructor_guard, conformance/guard_de_morgan, conformance/guard_inside_loop,
  conformance/assert_is_fallback.

### A switch covers every case

- **Status**: built.
- **Rule**: a switch over a union covers every member; over a `T?` of a class or a union it covers the class (or
  every member) and `Null`; over an enum or a `Boolean` every value. There is no `_:`, and a switch over a whole
  number or a text is refused; a repeated case is an error
  ([control_flow.md](../spite_documentation/control_flow.md#switch-over-values),
  [values_and_types.md](../spite_documentation/values_and_types.md#unions)).
- **Buys**: a member, a value or a null added later cannot be forgotten.
- **Falls back**: refused, "this switch over '...' has no case for ...: add the cases"; over a `T?`, "this switch
  over 'target' has no case for Null: 'target' is a Monster?, and a switch over a 'T?' covers its value and null, so
  a null cannot be forgotten; add the cases".
- **Lives in**: the proof `proofs/switch_cover`, which judges every switch the builder recorded before writing it as
  `if`s (`context.switch_sites`, from `switches.spite`: `check_the_cover`, `check_the_nullable_cover`) with the
  validator `validators/high_intermediary_representation/switch_cover`; a case of the wrong kind is still refused
  while building the case, and `validators/abstract_syntax_tree/switch_cases` checks the written cases.
  A switch is built as a chain of `if`s, so its cover is judged while it is built.
- **Checked by**: conformance/missing_switch_case, conformance/control_switch_enum_missing,
  conformance/control_switch_number_no_rest,
  conformance/control_switch_text_no_rest, conformance/switch_rest_case, conformance/switch_rest_refused, conformance/switch_on_text, conformance/switch_one_exception,
  conformance/switch_rest_not_last, conformance/switch_same_as_rest, conformance/value_switch,
  conformance/control_switch_value_on_nullable, conformance/nullable_switch_without_null; tests/rest_case,
  tests/value_switch, tests/nullable_switch_null_case.

## Indices and numbers

### A proven count or bound proves a read

- **Status**: built.
- **Rule**: `index < list.count()` (also `- k`, `count() > index`, a count kept in a `var`), with any call-free
  index (`code - 32 < glyphs.count()` proves `glyphs[code - 32]`), `base + k < list.count()` for k from 1 to 63, and
  the count facts `== k`, `>= k`, `> k`, `!= 0` and `not is_empty()` (at most 64 indices) prove `list[...]`, in
  `fallback`, `crash`, `if`, `while`, the right of an `and`, and after an `if` that leaves
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: a proven read answers `T`, not `T?`.
- **Bounds written with `<=`**: `crash p + k <= list.count()` (in a `fallback`, a `crash` or an `if`), and the `if
  p + k > list.count()` that leaves, prove `list[p]` to `list[p + k - 1]`, as `p + (k - 1) < list.count()` would.
- **In a `while`** (D1448): a `<=` bound and the count facts prove the reads of its body as they do after a `crash`:
  `while at + 3 <= values.count()` proves `values[at]` to `values[at + 2]`, `while queue.count() > 1` proves
  `queue[0]` and `queue[1]`.
- **A count kept in a `var`** proves only until a call that may shrink its list: past one, the read is refused as in [A call keeps a proof it cannot change](#a-call-keeps-a-proof-it-cannot-change).
- **Falls back**: an unproven read is a `T?`; where a `T` is needed it is refused, "'...' may be missing, since every
  '[ ]' answers a 'T?' ...: ..., or prove the count first, 'crash list.count() > 2'".
- **Lives in**: the proving is building, since it decides whether a read is a `T`: `loops.spite`
  (`read_a_bound`, `read_a_counted_list`, `whole_index_of`), `statements.spite` (`read_a_counted_member`,
  `read_a_turned_bound`, `note_a_counted_list`, `forget_after_a_shrinking_call`), `collections.spite` (`index_value`, `proven_by_its_path`); the
  refusal of an unproven read where a `T` is needed is the proof `proofs/present_values`.
- **Checked by**: tests/count_bound_proofs, tests/bound_proofs, tests/count_in_name_proves, tests/structural_index,
  tests/proof_again_in_loop, tests/compared_count_proves_read, tests/while_bound_facts; conformance/index_reads,
  conformance/bound_proofs_undone, conformance/count_proves_no_key, conformance/count_undoes_proof,
  conformance/structural_index_undone, conformance/proven_index_check, conformance/call_in_index,
  conformance/indexable_unproven.

### A proven read halts outside its list

- **Status**: built.
- **Rule**: a read proven by a bound or a count keeps one never-taken test against the list's length, which halts
  naming the read: a bound proves only the top of an index, and the list may have changed
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: a wrong or stale proof halts, never reads out of bounds.
- **Falls back**: "spite: '...' is outside its list: a bound proves only the top of an index, and this one is below 0
  or the list changed, at ...".
- **Lives in**: `low_intermediary_representation/lowering/list_reads.spite` (`read_the_item`), and the low proof
  `proofs/bounds_proven_by_signed_tests`, whose facts let the pass `low_optimization_passes/proven_bounds` drop the
  test where a signed test of the same values and a never negative index already prove it.
- **Checked by**: tests/proven_read_outside.

### A proven count or bound proves a read of a width

- **Status**: built.
- **Rule**: `buffer.read_<number>_at(p)` of width w (1 for `tiny` and `byte`, 2 for `short`, 4 for `integer` and
  `float`, 8 for `long` and `double`) answers the number, not a `T?`, where `buffer[p + w - 1]` is proven: by a
  bound (`while p + 3 < bytes.count()`), a count, or a `<=` bound (`crash body + 10 <= header.count()` proves the
  reads at `body`, `body + 4` and `body + 8` up to a short). The position is a name, a name plus a literal, or a
  literal ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: a header or a record is read with one bound, and each read is a number.
- **Falls back**: the read is a `T?` the program narrows. A proven read still answers null below 0 or past a
  changed buffer, and then halts: "spite: 'header.read_integer_little_endian_at(body)' is outside its list: a
  bound proves only the top of an index, and this one is below 0 or the list changed, at ...".
- **Lives in**: `high_intermediary_representation/building/width_reads.spite`, which reads the facts the bound
  recorded (`statements.spite`, `read_a_bound_at_most`).
- **Checked by**: tests/list_byte_numbers; conformance/byte_reads (the refusals).

### An index built from loop counters is proven by one guard

- **Status**: partly built (D1449): not the reads of a width.
- **Rule**: the guard `rows * stride <= list.count()` (a `fallback`, a `crash`, or the `if rows * stride >
  list.count()` that leaves), with `while row < rows` and inside it `while column < stride`, proves
  `list[row * stride + column]` in the inner loop: `row * stride + column` is below `rows * stride`. The four are
  names. Assigning `rows` or `stride`, or a call that shrinks the list, forgets the guard; assigning `row` or
  `column` forgets the read ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: the cells of an area are read with one guard, each a `T`.
- **Missing**: the reads of a width (`read_<number>_at`) at a cell.
- **Falls back**: the read is a `T?` and is narrowed, or refused where a `T` is needed. The guard proves only the top:
  a negative counter halts at the read, as every proven read does ("... is outside its list ...").
- **Lives in**: `high_intermediary_representation/building/windows.spite` (`note_an_area`, `read_the_areas`,
  `read_an_area_cell`), beside the window it extends: the outer loop's condition marks its counter in the scope of
  its body, and the inner loop's condition proves the cell where that mark still holds.
- **Checked by**: tests/area_guard_proven, tests/area_guard_cells.

### An index offset by a base is proven by one guard

- **Status**: built.
- **Rule**: the guard `base + width <= list.count()` (a `fallback` or a `crash`), or the `if base + width >
  list.count()` that leaves, with `while counter < width`, proves `list[base + counter]` inside the loop, base and
  width and counter being names. Assigning `base` or `width`, or a call that shrinks the list, forgets the guard
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: a slice of a list is read with one guard.
- **Falls back**: the read is a `T?` and is narrowed. The guard proves only the top: a negative base or counter
  halts at the read, as every proven read does ("... is outside its list ...").
- **Lives in**: `high_intermediary_representation/building/windows.spite`, called by `statements.spite` (the leaving
  `if`, the `fallback`), `crashes.spite` (the `crash`) and `loops.spite` (the loop condition).
- **Checked by**: tests/list_base_counter.

### A counted loop reads its items unchecked

- **Status**: partly built (done differently).
- **Rule**: inside `while index < values.count()` with the counter stepped last, the count is read once and the
  items with no test; a second list indexed by the counter is tested once before the loop
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)). A window read
  `values[at + k]` is proven by a test of `at + m` against the same count on the one way into it, `k <= m`, with
  `at` never negative and not written in between, so `while at + 2 < values.count()` proves `values[at]`,
  `values[at + 1]` and `values[at + 2]`; and a test of a compare's answer against zero (what `crash values[pick]`
  writes) proves as the compare does, its sides turned around.
- **Buys**: a tight loop over numbers costs a load per item.
- **Missing**: in the scalar loop a second list keeps its test on every pass (only the vector loop tests once).
- **Falls back**: each read keeps its unsigned test.
- **Lives in**: the low proof `proofs/bounds_proven_by_signed_tests`, run on the low representation before the
  pass `low_optimization_passes/proven_bounds` twice in each cleaning (once early, and once after the loop's
  invariant loads have moved out and equal loads are merged, when the count read by the loop's test and by the read
  have become one register), which records on each function the unsigned bound
  tests a signed test, or an unsigned test of the same values that passed, already proved and the sign tests a
  never negative value decides; the pass only writes what
  it recorded. With `lowering/list_reads.spite`, `low_optimization_passes/loop_invariants` and
  `low_optimization_passes/vector_loops`.
- **Checked by**: tests/counted_loops, tests/strided_counted_loops, tests/decided_comparisons, tests/window_reads_one_test.

### A test a dominating test already made is answered

- **Status**: built.
- **Rule**: a comparison made in its branch's own block or in a block that dominates it, of two registers each written once (or parameters) whose
  writes dominate an earlier branch on the same comparison of the same registers (or its opposite: `<` against
  `>=`, `==` against `!=`), is answered while compiling when the block one side of that earlier branch enters has no
  other way in and dominates the later branch. The answer is that side's: the comparison is answered when it is
  made in the branch's block, and the branch itself is decided when it is made in another. A decimal comparison is
  answered by the same comparison of the same decimals; only `==` and `!=` count as opposites (a `NaN` makes `<`
  and `>=` both false).
- **Buys**: a second bound test of an index already tested (`crash values[at]` then `values[at]`) and any repeated
  test of the same values are not made; the branch becomes a jump.
- **Missing**: a register written twice (a loop's counter), a function of more than 2000 blocks.
- **Falls back**: the test is made again.
- **Lives in**: the low proof `proofs/dominating_tests`, run in each cleaning after the signed-test proof, which
  adds its answers to the same record on each function; the pass `low_optimization_passes/proven_bounds` writes
  them (the comparison becomes its constant answer) and the folding and jump threading after it take the branch.
- **Checked by**: tests/dominated_tests.

### A proven divisor is not checked

- **Status**: built (by ranges, wider than the old rule).
- **Rule**: a divisor that is a non-zero constant, or whose range leaves out 0 (and -1 when the dividend may be the
  smallest value), is divided with no test ([values_and_types.md](../spite_documentation/values_and_types.md#numeric-types-and-the-casting-rule)).
  A local tested `!= 0` (`crash parts != 0`, `if parts == 0 { return }`, the block of `if parts != 0 { }`) is not zero
  until it is assigned, which a range cannot say, so the ranges keep it as a fact beside the range (D1450); it is
  divided with no test when its range also leaves out -1 or the dividend's range leaves out the smallest value.
  An attribute path through locals and `this` (`parts`, `config.parts`) tested `!= 0`, `> 0` or `< 0` is not zero
  in the same way until any attribute is assigned, a local it starts at is assigned, anything is called or made,
  a wait, or a loop's next pass; a call on the right of an `and` undoes what its left side proved (D1514).
- **Buys**: no zero test on a division.
- **Missing**: nothing.
- **Falls back**: the test stays, "spite: '...' divided by zero, at ...".
- **Lives in**: the proof `proofs/ranges` (`prove_the_divisor`, `prove_a_divisor_not_zero`), a speed proof run after
  the acceptance proofs, whose fact the lowering reads (`is_divisor_proven`).
- **Checked by**: tests/division_by_zero, tests/divisions, tests/smallest_divided, tests/divisor_not_zero,
  tests/divisor_attribute_proven.

### A divisor written as zero is an error

- **Status**: built.
- **Rule**: a whole-number `/` or `%` whose divisor is a constant expression equal to zero is refused
  ([values_and_types.md](../spite_documentation/values_and_types.md#numeric-types-and-the-casting-rule)).
- **Buys**: a division that always halts never compiles.
- **Falls back**: refused, "'...' divides by zero, which always halts the program ...".
- **Lives in**: `validators/high_intermediary_representation/division_by_zero`, handed the folded divisor by
  `operators.spite` (`binary_value`, `judge_a_division`).
- **Checked by**: conformance/division_by_constant_zero, conformance/remainder_by_folded_zero.

### Arithmetic that does not fit halts

- **Status**: partly built.
- **Rule**: every whole-number `+`, `-`, `*`, unary `-` and the smallest value divided by -1 halt if
  it does not fit (a narrowing is judged while compiling, [below](#a-number-that-may-not-fit-is-narrowed)); the step of a counter under its bound carries no check, nor does constant arithmetic; constant
  arithmetic that does not fit is a compile error
  ([values_and_types.md](../spite_documentation/values_and_types.md#numeric-types-and-the-casting-rule)).
- **Buys**: no wrapped number is ever read.
- **Missing**: a `Long` counter whose bound has no range keeps its check. Interactive builds prove ranges like
  every build: a range is about a function's own locals, which nothing typed at the REPL and no reload writes. The constant overflow error is made for `Integer` arithmetic only, as the old compiler made it: other
  widths are folded in their own type and checked where they are narrowed.
- **Falls back**: the check stays, "spite: '...' does not fit in an Integer (...), at ...".
- **Lives in**: the lowering (`conversions.spite`: `check_the_range`), the generator
  (`emit_a_cold_stop`), and the counter proof in `ranges.spite`.
- **Checked by**: tests/counter_room, tests/integer_overflow, tests/unsigned_overflow,
  tests/negate_overflow, tests/smallest_divided, tests/smallest_absolute; conformance/constant_overflow,
  conformance/literal_does_not_fit, conformance/byte_minimum_literal_does_not_fit.

### A number that may not fit is narrowed

- **Status**: built.
- **Rule**: a number put into a narrower one goes through that class's cast, which answers `null` when the value
  does not fit (D1895). Into a `T?` it is that `null`; into a plain number it is refused unless the ranges prove it
  fits, so the failure moves from run time to compile time. A decimal into a whole number, and a `Double` into a
  `Float`, are written on their own line, a declaration or an assignment, never as an argument, a `return` or an
  operand (D1896, D1899) ([values_and_types.md](../spite_documentation/values_and_types.md#a-number-that-may-not-fit-is-narrowed)).
- **Buys**: no narrowing halts at run time; a narrowing the ranges prove has no check at all, into a `T?` too, where
  it is present with no test, and a `crash`, `fallback` or `if` on a local only such narrowings assign is answered by
  the high pass `answered_facts` and left out with its cold path
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-check-of-a-narrowing-the-ranges-prove-is-not-made), #596).
- **Falls back**: refused, "this value is an Integer, which may not fit in a Tiny: write 'var converted: Tiny? =
  value' on its own line ..., or bound the value first with a condition ('if value >= smallest and value <= largest
  { }')", the condition naming only the side the value can pass (`value <= largest` for an `UnsignedInteger` into an
  `Integer`, `value >= smallest` for an `Integer` into an `UnsignedInteger`, both for a decimal, which
  [a range bounds](#a-range-proves-a-decimal-fits) only from a comparison that holds), or "this value is a Float, which loses its fraction in an Integer: write 'var
  converted: Integer? = value' on the line above, and narrow that".
- **Lives in**: `proofs/ranges` (`prove_a_conversion`, which records each narrowing as a
  `HighIntermediaryRepresentation.NarrowingSite` and whether its range fits), `proofs/narrowings_fit`, which hands
  each to `validators/high_intermediary_representation/narrowing_fit`; the lowering (`conversions.spite`:
  `fits_the_range`, `fits_the_decimal_range`, `fits_the_float_range`) answers the presence of a `T?`.
- **Checked by**: tests/narrowing_into_a_nullable, tests/fitted_narrowing_check_is_not_made, tests/narrowing_overflow, tests/cast_reads_the_range,
  tests/decimal_narrowing, tests/double_too_large_for_float, tests/signedness_change,
  tests/infinity_into_an_integer_is_null, tests/not_a_number_into_an_integer_is_null;
  conformance/narrowing_may_not_fit, conformance/byte_minimum_does_not_fit,
  conformance/decimal_argument_loses_its_fraction, conformance/decimal_returned_loses_its_fraction,
  conformance/decimal_declared_may_not_fit.

### A range proves arithmetic fits

- **Status**: partly built (D768).
- **Rule**: every whole-number local and parameter has a range from literals, assignments and the conditions in
  force (every side of an `and` that holds, every side of an `or` that does not, as after `if amount > 100 or
  amount < 0 { return 1 }`); `count()`, `length()`, `%`, `minimum`, `maximum` and `clamp` bound their answers, and `shifted_right` (or
  `_shifted_right`, whose count must be below the width) by a count with a range bounds a receiver that is never negative
  by its range, and any unsigned receiver by the bits it keeps (from 0 to 2^(width - count) - 1, so
  `hashed._shifted_right(32)` of an `UnsignedLong` fits an `UnsignedInteger`, #594); loops widen counters and
  count passes; a total holds at most `passes` terms
  ([values_and_types.md](../spite_documentation/proofs.md#a-range-proves-arithmetic-fits)). A range is kept only
  within 2^62 either way, so the proof's own arithmetic on bounds never overflows; an 8-byte local a condition bounds
  on one side only keeps that side apart (`name|floor`, `name|ceiling`), read only by the next condition on it, which
  makes a range once both sides are within the limit (#594). A local declared `T?` gets the range its present value
  has: a condition read through its narrowing (`fallback held and held <= top`, `if not held or held > top { return 0 }`,
  or a comparison after `crash held`) bounds it, and a read narrowed later keeps that bound until it is assigned (#622).
  Past an `if` with no `else` whose block reaches its end,
  each local holds the join of what the block left and what the entry narrowed by the opposite of the condition
  leaves; a range joined with a kept side keeps the wider side. An assignment reads the value's range before it forgets
  the name, so `remainder = 0 - remainder` keeps a range.
- **Why it settles**: the proof is one walk over the function in order; an `if` joins its two ends once, a `while`
  proves its body once from ranges the counter argument gives (no iteration), and a kept side is read only by a
  condition, so nothing is revisited.
- **Buys**: an operation the ranges prove carries no overflow check.
- **Missing**: loop locals other than counters; an 8-byte counter has a ceiling only from its own loop's bound.
  `absolute` bounds its answer by its receiver's range, and a counter only stepped down by constants under `>` or
  `>=` keeps a floor and counts its passes like one stepped up (D1515).
- **Falls back**: the check stays and is listed by `--optimization-report`.
- **Lives in**: the proof `proofs/ranges`, a speed proof run after the acceptance proofs, over every function built from
  the source; it records its fact on each operation (`proves_no_ranges`, the unchecked arithmetic) for the lowering.
  An operation is lowered once wherever the tree holds it, so one the proof visits again (a value two places share)
  keeps only what every visit proves: it fits, its divisor is safe or it folds (to the same number) only when each
  visit says so, and its operands' ranges for the report are the widest any visit saw (`prove_a_visit_again`).
  No builder shares an operation today (#314 removed the last), so no program reaches a second visit and no test
  can; the rule stands so that a builder sharing one later cannot fold it wrongly.
- **Checked by**: tests/proven_ranges, tests/optimization_report, tests/counter_room, tests/down_counter_ranges,
  tests/leaving_or_proves_ranges, tests/named_bounds_prove_ranges, tests/long_comparisons_bound,
  tests/clamping_if_keeps_its_bound, tests/shifted_right_bounds_a_narrowing, tests/nullable_read_keeps_its_bound;
  conformance/signed_shift_may_not_fit.

### A range proves a decimal fits

- **Status**: built (#614).
- **Rule**: a `Float` or `Double` local gets a range only from a comparison that holds as written: a side of an `if`
  or `while` condition, a side of an `and` that holds, a `fallback` or `crash` condition (which holds past it), and
  the `else` of a negated test (`if not (scaled > top) { } else { }`). The range bounds the value's floor: from
  `scaled <= bound` the floor is at most the bound's floor, from `scaled >= bound` at least it, `<` and `>` count as
  `<=` and `>=`, and `==` both. A bound is a written decimal (a negative one too, which the builder writes as
  `-0.0 - 1000.0`), a named decimal nothing writes, another decimal local with a range, or a whole number with a range within 2^53 (exact in a `Double`); a range is kept within 2^62 either
  way like a whole number's, one side at a time until both are known (`name|floor`, `name|ceiling`). A decimal into a whole
  number is proven when that floor range fits the whole type, since the cast fits exactly when the value is at
  least the type's smallest and below its largest plus one; a `Double` into a `Float` when the local has any range,
  since every value within 2^62 fits a `Float`. Rounding is not the proof's: the cast still drops the fraction toward
  zero and is still written on its own line (D2563).
- **Why NaN and the infinities cannot slip through**: every comparison with NaN is false, and `!=` is true. So a
  comparison that holds proves the value is not NaN, and a bound on both sides proves it finite. A comparison that
  does not hold proves nothing: past `if scaled > top or scaled < bottom { return 0 }` NaN reaches the next line, so
  the turned-around sides a whole number would get (`scaled <= top`, `scaled >= bottom`) are never recorded for a
  decimal, nor anything from `!=`. An infinity fails `<=` against a finite bound on its side, so a range from both
  sides holds only finite values; one side alone keeps no range.
- **Buys**: `if scaled <= top and scaled >= bottom { var whole: Integer = scaled }` is accepted with no run-time
  test, and into a `T?` the narrowing is present with no test, as a proven whole-number narrowing is.
- **Falls back**: refused as an unproven narrowing ("... or bound the value first with a condition ('if value >=
  smallest and value <= largest { }')"); arithmetic on decimals keeps no range, so `var half = scaled / 2.0` has
  none.
- **Lives in**: `proofs/ranges` (`narrow_a_decimal`, `decimal_range_of`, `decimal_constant_of`,
  `is_a_decimal_that_fits`); named decimals come from `high_intermediary_representation/attribute_uses.spite`
  (`is_a_written_decimal`); the lowering (`conversions.spite`) leaves out the
  test of a proven `to_whole` or `narrow_decimal`.
- **Checked by**: tests/bounded_decimal_narrowing; conformance/decimal_leaving_if_proves_nothing,
  conformance/decimal_declared_may_not_fit.

### An attribute nothing writes is read as its default

- **Status**: built (#395).
- **Rule**: an attribute no built function writes outside its default, whose default is one number literal,
  holds that number wherever it is read, so the proof `ranges` reads it as that number's range (a decimal's as the
  bound of [a decimal range](#a-range-proves-a-decimal-fits)): after
  `var _hundred = 100`, `floor.minimum(_hundred)` runs to at most 100, and `fallback amount < _thousand` bounds
  `amount` as `amount < 1000` does ([values_and_types.md](../spite_documentation/values_and_types.md#named-numbers)).
  What writes an attribute is what [untouched attributes](OPTIMIZATIONS.md#untouched-attributes-have-no-slot)
  counts: an assignment outside its default, a write through a shape its class fills, a struct handed to a foreign
  function; the slots the lowering writes (`_length`, `_buffer`, ...) and the classes of a fixed layout (`Buffer`,
  the scalars, `Spite.*`) count as written.
- **Buys**: a named bound proves arithmetic as its literal does, so the overflow check goes.
- **Missing**: a default that is not one literal (`var _bound = _hundred * 2`, a preset) keeps its type's range.
- **Falls back**: in a `--repl`, `--repl-port`, `--hot-reload` or `--development` build, where code loaded later may
  write it, every attribute keeps its type's range.
- **Lives in**: `high_intermediary_representation/attribute_uses.spite`, the one walk that decides which attributes
  nothing writes. The proof `ranges` runs it before it proves and records the numbers
  (`HighProgram.numbers_nothing_writes`); the pass `untouched_attributes` runs it again over what the high passes
  built since, and crashes if any of those attributes is written there.
- **Checked by**: tests/named_bounds_prove_ranges.

### The range of a register

- **Status**: built.
- **Rule**: on the low representation, after inlining, every register gets the bounds its writes prove, the union
  over all its writes when it has several: a constant its value; a comparison 0 to 1; a load of 8, 16 or 32 bits
  the range of that width; a `Float` operation or a conversion to `Float` 0 to 2^32 - 1 (its bits, with nothing
  above them); a copy and a pick (`select`) their sources' bounds; a sum, difference, product, quotient, shift,
  `bits_and`, `bits_or` or `bits_xor` of bounded operands the bounds of the result, when it fits its width; a
  remainder at most the divisor's size less one, with the dividend's sign; and a checked operation at most its
  width's range, since it halts otherwise. A register written from itself (a loop's counter, a running total)
  gets none. At the start of a block, a register written once (or a parameter never written) is bounded too by
  every test on the one way into it: the branches of the blocks before it, as long as each has one predecessor
  (stopping at a block it passed, [below](#every-loop-in-a-proof-settles-with-no-round-limit)), each test of the
  register against another register's bounds (signed: `<`, `<=`, `>`, `>=`,
  `==`; unsigned `<` and `<=` against a count never negative, from 0), and through a test of such an answer
  against zero (`crash` and `fallback` write that). A write of the register inside those blocks drops what the test
  proved. A write's bounds are worked out with what holds in the block it is in, so a number tested to be between
  0 and 65 535 and then taken apart gives parts that are never negative.
- **Buys**: arithmetic left unchecked ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#arithmetic-whose-operands-bounds-prove-it-fits-is-not-checked)),
  tests answered while compiling, and divisions by powers of two that are shifts
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-number-never-negative-divided-by-a-power-of-two-is-a-shift)).
- **Falls back**: a register with no bounds keeps every check and every test, and its divisions round toward zero
  with the sign correction.
- **Lives in**: the low proof `proofs/register_ranges`, recorded on each function (`LowFunction.register_ranges`)
  right before the passes `checked_ranges` and `power_divisions` in each cleaning; `power_divisions` clears it.
- **Checked by**: tests/proven_ranges, tests/half_precision, tests/divisions, tests/divisions_by_powers.

### A wider operand is written first

- **Status**: built.
- **Rule**: in arithmetic and bitwise functions, a right side with more bits (or a decimal beside a whole number)
  is refused, naming the turned-around form, unless it is a literal within the left type
  ([values_and_types.md](../spite_documentation/values_and_types.md#numeric-types-and-the-casting-rule)). A
  comparison is a call on its left side instead: its right side is fitted like an argument and refused with the
  assignment's words, or the sides are swapped with a `fixed:` line when the swapped form fits
  (`validators/high_intermediary_representation/swapped_comparison`,
  [functions_and_operators.md](../spite_documentation/functions_and_operators.md#a-comparison-is-a-call-on-its-left-side)).
- **Buys**: nothing is cut to fit.
- **Falls back**: refused, "'...' is added in Integer, since arithmetic takes the left side's type, and the right
  side is a Long, which would be cut to fit: write the Long first ...". A literal out of the left type's range gets
  the literal-fit error instead; inside a template's number copy the cut halts at run time.
- **Lives in**: `validators/high_intermediary_representation/cut_operand`, handed the fitted right side by
  `operators.spite` (`binary_value`, `judge_a_cut`); `calls.spite` hands the built call to
  `validators/high_intermediary_representation/wider_bitwise_operand`.
- **Checked by**: conformance/wider_right_operand, conformance/wider_bitwise_operand,
  conformance/library_wider_bitwise_operand,
  conformance/wider_decimal_right, conformance/wider_multiplication_order, conformance/wider_subtraction;
  tests/signedness_not_wider, tests/comparison_is_a_call_on_its_left_side, conformance/comparison_swapped_to_fit,
  conformance/comparison_that_cannot_swap, conformance/comparison_of_unsigned_long.

### Maths on constants is worked out while compiling

- **Status**: built (wider than the old rule).
- **Rule**: a maths member whose receiver and arguments are known is answered by the compiler, a not-a-number answer
  excepted ([standard_library.md](../spite_documentation/standard_library.md#maths)).
- **Buys**: no call at run time.
- **Falls back**: one call into the C library, or one instruction.
- **Lives in**: the passes `low_optimization_passes/compile_time_evaluation` and `constant_folding`; see
  `OPTIMIZATIONS.md`.
- **Checked by**: tests/maths_folding; conformance/maths_constant_assigned, conformance/maths_constant_called,
  conformance/maths_constant_on_value.

### A dictionary only read by literal keys is never made

- **Status**: built.
- **Rule**: a local made from a dictionary literal of literal keys and values, every later mention of which is
  `name[literal]` and never assigned, holds exactly those entries. A read of a key it holds is its value, still a
  `T?`; a read of a key it does not hold is known to be `null`, so `crash points["platinum"]` is the compile error a
  `crash` that folds false is, with the reason `the dictionary written out as 'points' holds no key 'platinum'`, in
  every build, `--repl` included.
- **Buys**: no dictionary, no hashing, when every read asks a key it holds.
- **Falls back**: the dictionary is made and read as written.
- **Lives in**: the proof `proofs/literal_dictionaries`, before `folded_crashes`, which records each such dictionary
  (`HighProgram.literal_dictionaries`) and marks each read of a key it lacks (`Call.missing_key`); the high pass
  `high_optimization_passes/folded_dictionaries` folds the ones with no such read.
- **Checked by**: tests/dictionary_folding; conformance/dictionary_literal_missing_key.

## Compile-time questions

### Conditions decided while compiling

- **Status**: partly built.
- **Rule**: an `if` on a Build field, a codegen value, a type test, a walk's `attribute.class` or name test, a class
  test the value's type answers, or a compile-time question (and `not`, `and`, `or`, `==`, `!=` over them) keeps
  only its taken branch; only what survives is compiled
  ([metaprogramming.md](../spite_documentation/metaprogramming.md)).
- **Buys**: generic code compiles only the branch its class takes.
- **Missing**: `function_waits` and `function_writes_parameter` are answered after every function is built, so both
  branches are built and checked (D673), and the high pass `answered_facts` then keeps only the taken one; a codegen number compared with a literal folds only when one side is a
  call. `x and $flag` and `x or $flag` fold whatever `x` is (in
  plain code a condition that folds is refused, D1746): one
  that only reads names, attributes and tests is left out (D1143), and one that calls something is run on its own,
  once, before the statement, and its answer dropped (D1513).
- **Falls back**: a run-time test of a constant, removed later by constant folding; both branches must compile.
- **Lives in**: the builder, `statements.spite` (`build_a_decided_if`), `operators.spite` (`condition_of`, `folded_logic`, `decided_comparison`), `questions.spite` (`reflection_question`): deciding a condition is choosing what to build, and
  the branch not taken is never built, so nothing is left for a proof to judge (D1110).
- **Checked by**: tests/codegen_member_fold, tests/walked_class_fold, tests/private_walk, tests/codegen_short_circuit,
  tests/codegen_kind_tests, tests/codegen_class_test, tests/build_settings, tests/folded_helpers,
  tests/folded_functions, tests/folded_argument_count, tests/decided_and_false, tests/decided_and_false_after_a_call.

### A split class behaves as the class

- **Status**: partly built (D1846, spite_compiler#309).
- **Rule**: an attribute its constructor sets from a parameter before anything else, and that nothing else
  writes, holds for the whole life of an object the value the constructor was given, so every object made with a
  literal there holds that literal. A call whose receiver or argument can only be such objects, on every path the
  high pass `split_classes` follows (locals, parameters of functions whose every caller it sees, `this`, answers),
  may run a copy of the callee in which each read of the attribute through that parameter is the literal. A
  parameter written in the callee, or a function reached where the pass did not look (a function address, a call
  from code the compiler wrote), keeps the call as it is.
- **Buys**: a test of an attribute every object reaching a call holds at the same value, given to the
  constructor, costs nothing in the copy, which is what a `Boolean` codegen value bought.
- **Missing**: an object read back from a list, an attribute or a function value is not known, so its calls keep
  the test; the attribute keeps its slot.
- **Falls back**: the run-time test, the same answer, and so does a call past the evaluation's size budgets (64
  split copies in a program, a callee of at most 4 000 instructions), which are budgets, not round limits
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#what-the-evaluation-while-compiling-stops-at)).
- **Lives in**: the high pass `high_optimization_passes/split_classes` (which values reach which calls) and
  `low_optimization_passes/compile_time_evaluation/partial_evaluation.spite` (`trusts_the_split`, the copies),
  embedded in an optimisation, since the facts are only worth proving for the copies it makes.
- **Checked by**: tests/decided_and_false, tests/decided_and_false_after_a_call, tests/split_by_a_constant
  (output only).

### Whether a function waits

- **Status**: built (D1134, D1253).
- **Rule**: waiting spreads from `sleep`, console, file and socket reads and joins, through calls, function values
  (to every function taken as a value with the same signature) and `type` dispatch, to a fixed point; letting go of
  a `Concurrent` waits; where it cannot tell, the answer is true
  ([metaprogramming.md](../spite_documentation/metaprogramming.md#walking-a-programs-structure),
  [concurrency.md](../spite_documentation/concurrency.md)).
- **Buys**: `function_waits` and `is_resumable` fold.
- **How**: a function that assigns a local again, assigns an attribute or clears a list, where what it replaces may
  hold a `Concurrent` (the handle itself, an object or a list holding one), lets one go, so it waits (D1134; the
  test of what holds one is `high_intermediary_representation/held_work.spite`, which the lowering's own study reads
  for every handle). A call through a function value the study
  cannot name reaches every function taken as a value anywhere in the program with as many parameters as the call
  passes: the first such call reads every body once.
  A local whose value may hold a `Concurrent` waits when it is let go at the end of its scope, unless the function
  hands it on: passes it as an argument, stores it in an attribute, names it again or returns it (D1253).
- **Falls back**: refused when the answer would decide itself, "whether '...' can wait was answered ... before the
  functions that ask 'function_waits' were compiled ...".
- **Lives in**: the proof `proofs/compile_time_facts`, which answers every question asked while building and
  refuses an answer that would decide itself; the study it reads is `high_intermediary_representation/building/facts.spite`
  (`waits`, `waits_through`), which the builder also reads for the frame starts; a second study in `high_intermediary_representation/waits.spite`
  (embedded: the lowering's own, for what each call suspends).
- **Checked by**: tests/waiting_systems, tests/entry_function_waits, tests/pooled_loads_wait, tests/default_handles,
  tests/reflection_objects, tests/function_waits_dropped; conformance/function_waits_paradox.

### How many arguments a function takes

- **Status**: built (D1442).
- **Rule**: `$T.argument_count("<pattern>")` and a walk's `phase.argument_count()` fold to a whole number; every
  function a pattern matches must take the same number, and a pattern matching none is an error
  ([metaprogramming.md](../spite_documentation/metaprogramming.md#walking-a-programs-structure)).
- **Buys**: generic code chooses its call by the count.
- **Falls back**: refused, "'...' has no function named '...', so 'argument_count' has nothing to count ...", or
  "... has no one answer: the functions of 'Painter' that fit it take different numbers of arguments ('update_each'
  1, 'render_each' 2), so ask 'phase.argument_count()' in a template over them, where each is walked on its own";
  asked of a walk that is not over functions, "'argument.argument_count()' is how many arguments the function a walk
  over functions stands for takes, so it is asked with no name in a template over functions, such as
  'run_phase_each(phase: Spite.FunctionDeclaration)'".
- **Lives in**: embedded, `questions.spite` (`counted_arguments`, `pattern_argument_count`), judged by
  `validators/high_intermediary_representation/function_question` and `walked_argument_count`.
- **Checked by**: tests/folded_argument_count, tests/system_phases, tests/streamed_rows; conformance/argument_count,
  conformance/argument_count_missing, conformance/passed_argument_count, conformance/argument_count_disagrees,
  conformance/argument_count_outside_walk.

### Whether a class fits a `Vector`

- **Status**: partly built.
- **Rule**: every attribute is a number, a Boolean, a text, an enum, a symbol, a singleton or a `T?` of those; no
  `drop()`; no function uses `this` as a value; not a generic template. `fits_vector()`, `is_fixed_size` and
  `any_attribute_fits_vector` fold, and an `Items<T>` stores its items inline exactly when a `Vector<T>` could be
  made ([collections.md](../spite_documentation/collections.md)).
- **Buys**: items inline, lent rather than counted.
- **Generic templates**: every generic class is made once per set of type arguments before anything asks, so no
  `fits_vector()` is ever asked of an unbound template and the old compiler's "not a generic template" test has
  nothing to refuse here.
- **Falls back**: refused for a `Vector<T>`, "'...' uses 'this' as a value, and an item of a Vector is borrowed ...";
  an `Items<T>` holds such items by reference.
- **Lives in**: the proof `proofs/vector_fit` refuses a `Vector` of a class that does not fit, judging every
  `Vector` the builder recorded making (`context.vector_sites`); the test itself, `constraints.spite`
  (`fits_a_vector`, with `uses_this_as_a_value`, and `is_kept_inline` for each attribute, which the proof asks
  too, so its refusal and the answer an `Items<T>` folds never disagree), is still asked while building by `reads.spite`
  and `fills.spite` (`is_fixed_size`), which choose the form of what they build from it.
- **Checked by**: tests/items_columns, tests/folded_checks, tests/folded_lends, tests/lent_list_elements,
  tests/reflection_objects; conformance/folded_crash.

### Whether a function writes a parameter

- **Status**: built.
- **Rule**: `function_writes_parameter(...)` and `.is_mutated` fold: a write is an attribute or item set, a call
  that writes, passing it to a written parameter, or storing it where a later write could reach it; reassigning,
  copying plain values out and writing a singleton are not; where it cannot tell, true
  ([metaprogramming.md](../spite_documentation/metaprogramming.md#walking-a-programs-structure)).
- **Buys**: generic code skips a copy a callee never writes.
- **Falls back**: true for an unknown function value, a member template or a function with a `Spite.*` parameter.
- **Lives in**: the proof `proofs/compile_time_facts`, reading `building/facts.spite` (`writes`, `callee_writes`).
- **Checked by**: tests/parameter_writes, tests/parameter_write_rows, tests/run_time_kinds;
  conformance/parameter_write_question, conformance/snapshot_argument_writes.

### Whether a class keeps state

- **Status**: partly built.
- **Rule**: `$T.is_stateful` folds to "some function other than the constructor and `drop()` writes its own object
  or a singleton, or a singleton it binds keeps state"; where it cannot tell (a function it cannot build, such as a
  member template or one taking a `Spite.*` parameter), true
  ([metaprogramming.md](../spite_documentation/metaprogramming.md#walking-a-programs-structure)).
- **Buys**: generic code shares an object nothing changes.
- **How**: the study (`building/facts.spite`) gives every singleton a slot of its own (`s:<class>`), reached by
  naming the singleton, by an attribute or a local holding it, and through every call that writes one; a program
  class whose writers can all be built asks the proof whether one of them writes its object or any singleton
  (the fact `keeps_state`), with or without attributes of its own (D1135).
- **Missing**: it is a filled reflection value, not a folded constant, so an `if` on it builds both branches.
- **Falls back**: true when a bound singleton has attributes, when a function of a program class cannot be built,
  and for a library class with attributes.
- **Lives in**: the proof `proofs/compile_time_facts` answers the fact; `fills.spite` (`fill_the_state`,
  `every_writer_can_be_built`, `writes_its_object`) asks it.
- **Checked by**: tests/class_walk, tests/run_time_kinds, tests/reflection_objects, tests/stateful_singleton_writes.

### A quiet value changes nothing handed in and never halts

- **Status**: built.
- **Rule**: `HighIntermediaryRepresentation.QuietValues` answers whether a value can be left out without the program
  seeing it. A call is quiet only on an object proven new: one made in the value being asked (a making, `this` inside
  a constructor or the defaults it runs, a parameter handed a new object, a local declared from one); a call on
  anything handed in (`names.append(name)` on a parameter, a call on an attribute's object) is never quiet, since
  the caller sees what it changes. For the defaults the constructor replaces, an attribute of the new object counts
  as new too, since that pass keeps every default that reads one that stays. A conversion is quiet only when it
  cannot halt (`Conversion.never_halts`): a `proven` conversion of a value that may be missing halts when it is, a
  `present` read of an attribute halts when its back reference is gone, and a narrowing halts outside its range;
  `unread_fields` asks the same of the arguments it drops
  ([optimizations.md](../spite_documentation/optimizations.md#an-attribute-that-only-holds-an-item-of-its-holders-list-is-not-counted)).
- **Buys**: a default left out, an unread attribute's default never made, or an argument dropped never takes away
  a change to an object the program still holds, nor a halt.
- **Falls back**: not quiet; the default is made, the argument is passed.
- **Lives in**: `high_intermediary_representation/quiet_values.spite` (embedded), asked by `replaced_defaults` and
  `lent_attributes`; `unread_fields` asks `Conversion.never_halts` (`values/conversion.spite`) of its arguments.
- **Checked by**: tests/lent_default_keeps_a_call_on_what_it_is_handed, tests/default_kept_chain_calls_what_it_kept,
  tests/default_kept_writes_through_an_argument.

### The one class a `type` admits

- **Status**: built (wider than the old rule).
- **Rule**: with the whole program known, an attribute read through a `type` is read at the offset every class that
  fills it shares, with no class test; off in interactive builds
  ([values_and_types.md](../spite_documentation/values_and_types.md#inline-types-and-duck-typing)).
- **Buys**: no class test on a read through a `type`.
- **Falls back**: a test of the class id, for a member some filler answers with a function, a shape call with
  arguments, or an offset another union takes.
- **Lives in**: embedded, the high pass `high_optimization_passes/untouched_attributes` (`optimized`), and the lowering (`lower_shape_call`).
- **Checked by**: none aimed at it (tests/class_through_shape and tests/unions read through a `type`).

### A condition known while compiling is an error

- **Status**: built (D1746).
- **Rule**: outside a generic class and a walk, an `if` or `while` whose condition the builder decides while
  compiling, and a `fallback` that folds false, are refused: the condition is always true or always false, so writing
  it tells a reader nothing. A condition that reads a `Build` field is kept, since the field is set from the command
  line and choosing the branch is its purpose; the literal `while true` is refused like any other (a loop states
  the condition it runs under). A
  bare name is judged by the narrowing errors instead ("already narrowed", a plain value). A `fallback` or `crash`
  that folds true is "Proving what is proven is an error"; a `crash` that folds false is the next section
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)).
- **Buys**: no dead branch in the source.
- **Falls back**: refused, "'if 2 > 1' is decided while compiling and is always true here, so it tells a reader
  nothing: remove the 'if' and keep the code it runs".
- **Lives in**: `statements.spite` (`note_a_decided_condition`, from `build_if`, `build_while` and `build_assert`),
  judged by `proofs/proven_checks`; `reads.spite` counts each `Build` read it folds (`folded_build_read`).
- **Checked by**: conformance/decided_if_true, conformance/decided_if_false, conformance/decided_while,
  conformance/decided_assert_false; tests/decided_conditions_kept.

### A `crash` that folds false is a compile error

- **Status**: built.
- **Rule**: a `fallback` or a `crash` that asks only what is decided while compiling folds; a `crash` that folds false is
  refused when the program would stop there every time the function runs and the program reaches the function, naming
  the instance and each side of an `and`; a `fallback` that folds false answers its default and the rest of its block is
  not compiled, and so is the rest of a block after a `crash` that folds false
  ([metaprogramming.md](../spite_documentation/metaprogramming.md)).
- **Decided**: a `Build` field, a `Fact`, a Boolean constant, a comparison of two written numbers, and every answer of
  the next section. The condition of an `if` on such a value decides which branch counts.
- **Not refused**: a `crash` in a branch that never runs; one under an `if`, a `while` or a `switch` case not decided while compiling, or after a `return`, a
  `fallback` or a `crash` under one, since the function can run without reaching it, and it stays a `crash` that halts at run time; one in a function the
  program does not reach, in every build. The refusal is this proof's and never the builder's, so a function built only
  because an inspectable build keeps it (`CommandLine.Inspection`), or called only from a branch a late fact drops, is not refused.
- **Reach**: `proofs/folded_crashes/reach.spite`, walked only once a `crash` is found, so a program with none pays nothing:
  from the entries, what tree shaking protects and the constructors of singletons, through `HighOptimizationPasses.References`, without the branch a decided
  condition drops. A function value in a reflection table's fill is not followed, so a function only `call_function()` runs
  is not refused and halts at run time naming its `crash`.
- **Buys**: a generic class that cannot work for a class is refused for it, and a broken shape of the program stops the
  build.
- **Falls back**: refused, "'crash ...' always halts in ...: its condition is decided while compiling and is false
  ...".
- **Lives in**: the proof `proofs/folded_crashes`, run once the facts are answered; `crashes.spite` (`build_crash`)
  stops compiling the block after a `crash` it folded.
- **Checked by**: conformance/folded_crash, conformance/folded_build_crash, conformance/folded_crash_and_side,
  conformance/empty_walk_crash, conformance/snapshot_argument_writes, conformance/folded_crash_numbers,
  conformance/folded_crash_after_a_decided_if; tests/folded_crash_uncalled, tests/folded_checks, tests/folded_crash_not_decided.

### A walk over known classes is decided while compiling

- **Status**: built, for what `building/folded/constants.spite` answers.
- **Rule**: a class or namespace named in the code, `$T`, `class`, the parameter of a walk over classes or namespaces,
  and a `var` or a parameter given one of these and never assigned again are constants, and so are their `name`,
  `name_with_namespaces`, `classes`, `namespaces`, `functions` and a class's `attributes` (when its fill lists them: not for `String`, a scalar, a list or a dictionary), `Spite.Namespace.instances` and `Spite.Class.instances` (the
  program's namespaces and classes, which no code can add to or take from while it runs), a list literal that only names classes or only names namespaces; `count()`, `is_empty()`, `map_names()`,
  `contains`, `count_name_starts_with` and `count_name_ends_with` of a constant list; `first()`, `last()`, `[n]` written as a
  whole number and `["Name"]` of a constant list of classes or namespaces, which are the item (`first()`, `last()` and a name
  a constant `T?` holding it, proven present, so a `crash` on a local holding one is removed as proven, as after
  `Phase.values.find_by_name('update')`), or run time when there is none; `starts_with`, `ends_with`,
  `contains`, `split` and `length()` of a constant text; and `==`, `!=`, the orders, `and`, `or` and `not` over them.
  Each answers what the object made at run time would answer, from the same names (`DescribedNames`, `namespaces_of_the_program`).
- **Walks**: `each` over a constant list of classes or namespaces with a walker of the class is one call per item, of a copy
  of the walker that knows it: over classes the copy binds the class as `Theme.classes.each(...)` does (`walked_class_keys`),
  so inside it the class is a type, makes its objects and narrows `value.class == part`; over namespaces it knows the
  namespace (`known_arguments`). A call of a function, of this class or of another object, handed a class or a namespace
  constant is a copy for that value (a class alone binds it the same way, `_over_<Class>`), and inside any walk copy so is
  a call handed any constant, however deep (#601: a copy is made once per function and constant, and constants are
  only read from the program, so there are finitely many). A
  function that takes a namespace or a class is never built on its own as an uncalled function (`is_a_walked_member`).
- **A list stays known only while nothing can write to it**: a local or parameter holding a known list is known only when each
  mention in the function is a read (`stays_as_it_was`) or an argument of a function that only reads it. Anything else is
  built as it was written, at run time, undecided.
- **Buys**: a walk whose every check folds costs nothing at run time: no reflection object is made for it, and a `crash` that
  holds is not written. A walk over `Spite.Namespace.instances` that checks the program's layout refuses the build, as the compiler's own `folder_layout` does (`tests/compiler_folder_layout_broken`).
- **Falls back**: what does not fold (an attribute's list, a call on another object handed no class or namespace, a filter over a constant list, a text with holes, an index that is not written as a number or a name, or names no item) is run time, so
  a `crash` under it is not decided.
- **Lives in**: `building/folded/constants.spite`, `building/folded/known_copies.spite`, asked first by `Values.value_of`.
- **Checked by**: tests/reflection_names_fold, tests/attribute_list_folds, tests/reflection_list_first_folds, tests/reflection_list_last_folds,
  tests/reflection_list_index_folds, tests/reflection_list_name_folds, tests/namespace_walk_decided, tests/known_list_walk, tests/class_name_is_short; conformance/reflection_name_crash, conformance/known_list_walk_crash, conformance/walk_name_crash,
  tests/registry_finds_components, tests/namespace_argument_folds,
  conformance/reflection_count_crash, conformance/reflection_names_contains_crash, conformance/namespace_walk_crash,
  conformance/namespace_walk_helper_crash.

### Tree shaking: what `main` can reach

- **Status**: partly built.
- **Rule**: only what the entry reaches is kept, transitively: a function called, a member a dispatch may call, a
  function taken as a value ([compiler.md](../spite_documentation/compiler.md)).
- **Buys**: a program carries none of what it does not use.
- **Missing**: reach is decided only while the high representation is built: a function whose only callers were
  inlined, or that sits in a branch folded later, is still written; a function nobody calls is never built, so it
  is not type-checked; an inspectable build keeping everything.
- **Falls back**: keeps too much, never too little.
- **Lives in**: `builder.spite` (`build`), `building/context.spite` (`need`).
- **Checked by**: tests/folded_helpers, tests/folded_crash_uncalled, tests/unreached_function_reads, tests/hello.

### What a class object holds is known while compiling

- **Status**: built (spite_compiler#54), for the attributes a class object's fill gives a constant.
- **Rule**: a class object (`Spite.Class`, `Spite.Namespace`, `Spite.Enum`, `Spite.Union`, `Spite.Type`) is made
  once, by the fill the compiler writes for it, which runs the reflection class's defaults and then its constructor
  on the new object. An attribute of the reflection class that its constructor writes once, at the top of its body,
  from a parameter it never assigns, and that no other function of the program writes (its defaults aside, which run
  before the constructor) nor any `type` member of its name can reach, holds for the object's whole life what the
  fill handed that parameter. Where that is a whole number, a decimal, a text, `null` or another class object, it is
  known while compiling. The facts are proven from the built program at each compile, never taken from the library
  ([reflection.md](../spite_documentation/reflection.md#the-spite-classes)).
- **Buys**: a call of a function that only answers such an attribute (`get_name`, `get_is_singleton`, `to_string`,
  `fits_vector`), on a class object written in the code, on another such answer (`Monster.namespace.name`) or on a
  local given one and never assigned again, is the attribute's value, with no test of the object's slot and no fill
  (`high_optimization_passes/class_object_reads`).
- **Keeps the order**: a class object is let go at exit, and a `drop()` that reads one after that halts with D1256's
  words, which depends on when the object was first made. So a class object that a function a `drop()` can reach
  names (through calls, `type` members of the same name, and, once such a function calls a function value, every
  function the program takes as a value), one the fill of such an object names, and one whose fill names such an
  object, is never folded anywhere, so each is made when it was and halts the same way; a `drop()` that reaches
  a `.class` of a value folds nothing. The program's output never changes.
- **Falls back**: an attribute that is a list or a dictionary, one the fill works out from a late answer
  (`is_stateful` of a program class), a class object read from a list, an attribute that is not
  [only given by its defaults](#an-attribute-only-its-defaults-give-a-class-object-holds-it) or a parameter of a
  function that is not a copy for one class, and any build
  that keeps everything (`CommandLine.Inspection`) read the object at run time, as before.
- **Lives in**: the proof `proofs/steady_class_objects`, registered among the high passes right before
  `class_object_reads` (`HighProgram.steady_class_object_values`).
- **Checked by**: tests/class_object_reads_fold, tests/class_object_read_in_a_drop_at_exit, tests/reflection_names_fold,
  tests/enum_reflection (output only).

### An attribute only its defaults give a class object holds it

- **Status**: built (spite_compiler#54).
- **Rule**: an attribute whose every write in the built program is in a defaults function of its class, at the top of
  its body, writing one class object named in the code (the same in each defaults function the class has), holds that
  object whenever an object of the class is read, as long as nothing before the write in the defaults can reach the
  object being made: for a class with many objects, no value before it reads `this`; for a singleton or the entry,
  which another function can reach while it is made, no value before it reads `this` or calls anything. It falls when
  a `type` member shares the attribute's name, or when an object of the class is made without its defaults.
- **Buys**: a read of what a class object holds through such an attribute, on a local or `this`, is the constant
  `class_object_reads` gives that class object (`keeper.held.name` is `"Monster"`).
- **Falls back**: any other write (a constructor, a reflection writer, a write in a branch), and a read through a
  call, read the attribute at run time.
- **Lives in**: `high_optimization_passes/class_object_reads/steady_attributes.spite`.
- **Checked by**: tests/class_object_read_through_an_attribute.

### A class object is filled only where it is read

- **Status**: built (spite_compiler#54).
- **Rule**: a fill runs only from a read of its class object's slot, and the only values that read one are a class
  object written in a function and a `.class` of a value, which reads the object of each class it may answer. A fill
  that no function but the fills reaches through those, transitively through the fills that are reached, never runs.
- **Buys**: such a fill is not compiled, nor what only it called (`high_optimization_passes/unread_fills`).
- **Falls back**: a fill reached from a function that is dropped later stays; builds that keep everything
  (`CommandLine.Inspection`) keep every fill.
- **Lives in**: `high_optimization_passes/unread_fills`.
- **Checked by**: tests/unread_fills_are_left_out, tests/class_object_reads_fold, tests/enum_reflection.

### A fill makes nothing but its objects

- **Status**: built (spite_compiler#620).
- **Rule**: a fill is written by the compiler's reflection writer, and its statements are a making of a reflection
  object, a list, a dictionary, a `File` or a `Directory` kept in a local, an `append` or `set_at` into such a local,
  and the constructor of its own class object. Making those and filling them does nothing but allocate and read the
  class objects named in them. So a local of a fill that nothing reads but its own `append`s and `set_at`s (the
  collection of a reflection field that `unread_fields` took out of the constructor) can go with them, and with it
  every class object only it named.
- **Buys**: the fill does not make the parts nothing reads, and the fills only they reached are not compiled
  (`high_optimization_passes/unread_fills/unread_parts.spite`, before the reached fills are found).
- **Falls back**: a local read anywhere else, inside an `if` included, stays with everything that fills it.
- **Lives in**: `high_optimization_passes/unread_fills/unread_parts.spite`.
- **Checked by**: tests/unread_fills_are_left_out, tests/static_class_objects.

### A class object is static data where no drop() at exit can see it

- **Status**: built (spite_compiler#620).
- **Rule**: a fill only makes objects and stores them into its own class object; it reads what no other fill writes,
  and no fill reads what another class object holds. So the fills can run in any order, once each, before the entry
  runs and before any other thread starts, with every class object at an address fixed in the executable, and each
  read of a class object is that address. The one thing the order changes is the order things are let go at exit, which
  only a `drop()` run at exit can see: a class object such a `drop()` can reach (`objects_seen_at_exit`, which counts a
  fill that names one as reaching it too) keeps its fill on first read, and when a `drop()` asks the class of a value,
  every class object does.
- **Buys**: no test, claim or wait at a read, no fill nesting inside another, and no allocation of the object itself
  (`high_optimization_passes/static_class_objects`, `low_intermediary_representation/lowering/static_class_objects.spite`).
- **Falls back**: builds that keep everything (`CommandLine.Inspection`) fill on first read.
- **Lives in**: `high_optimization_passes/static_class_objects`.
- **Checked by**: tests/static_class_objects, tests/class_object_read_in_a_drop_at_exit, tests/threaded_class_objects.

### A reflection field's write that goes keeps what its value does

- **Status**: built.
- **Rule**: a write to a field of a reflection class that no built function reads goes with the field, and its object
  and its value are each kept as an evaluation unless they are quiet: a literal, a local, `this`, a read of something
  quiet, a conversion of something quiet, or a making with no arguments whose defaults and
  constructor `HighIntermediaryRepresentation.QuietValues` proves quiet. A call is never quiet here, since it may
  change the object it is called on, nor a making with arguments, since its constructor may change what it is handed ([reflection.md](../spite_documentation/reflection.md#what-the-compiler-leaves-out)).
- **Buys**: the field's slot and its write go without changing what the program prints or changes; the evaluation
  lets go of what it answered, so nothing made leaks.
- **Falls back**: keeps the evaluation, never drops one that could do something.
- **Lives in**: `high_optimization_passes/unread_fields` (embedded).
- **Checked by**: tests/unread_reflection_field_keeps_its_effects.

## Memory

### Objects that never leave their function live in the frame

- **Status**: partly built (D801, D953).
- **Rule**: a fresh object of a class that holds only numbers, Booleans, enums and singletons, that never leaves its
  function, lives in registers or the frame; a constructor-made local whose class holds text or lists too
  ([memory.md](../spite_documentation/memory.md)). Comparing it with `==` or `!=` does not make it leave: its room
  in the frame is an address no other object has while it lives, so the comparison answers as it would on the heap,
  and an object compared is placed only in the frame, never in registers, where it would have no address.
- **Buys**: no allocation, no count.
- **Missing**: the fresh result of a function that is not inlined goes to the heap; an object whose class lets go
  of attributes is placed only in registers, never in the frame, but a `Buffer`, which is placed in the frame and
  lets go of its own bytes; `.memory.section` answering `'stack'`.
- **Falls back**: a heap object.
- **Lives in**: the low proof `proofs/objects_in_the_frame`, run on the low representation after inlining and
  compile-time evaluation (and again after the late inlining, on the functions it changed): it follows each object
  a function makes through its copies, loads, stores, calls and returns, asks whether each callee keeps what it is
  handed (`kept_parameters.spite`: an address made from the parameter and stored only into the parameter, as a
  `Buffer` points at the room inside it, keeps nothing) and reads the class's free function, and records on the
  function how each object that never leaves it is placed (`LowFunction.placed_objects`: in shared registers, in
  registers of its own, in the frame, or, for a `Buffer`, in the frame marked as living inside another value) with
  the fields it has, and whether anything reads an object's count: a load of its count in the function, or a callee
  that loads it (or reads through an address made from it, or copies its bytes). It runs once more right after the
  first cleaning, for an object stored only into one placed then. The pass `low_optimization_passes/object_placement`
  right after it only writes what was recorded, and an object in the frame whose count nothing reads gets no count.
- **Checked by**: tests/generic_vectors, tests/written_codegen_in_frame, tests/owned_objects (output only),
  tests/compared_object_in_the_frame (counts with `--debug-memory`).

### A short text that never leaves its function lives in the frame

- **Status**: partly built (D1990).
- **Rule**: a text a function makes that never leaves it, reached only through its own address, the addresses
  added to it (its `Buffer`, the bytes inside) and the `Buffer` read from its slot, each only read, written
  through, compared, copied from or handed to a call that keeps nothing of it, lives in the frame when its bytes fit
  the room inside it; no function of the program keeps a text's `Buffer`
  ([standard_library.md](../spite_documentation/standard_library.md)).
- **Buys**: no allocation for a short text that only lives in its function.
- **Missing**: a short text held inside a 16-byte `String` value wherever it goes (stored, answered, passed to a
  call that keeps it), spite_compiler#394.
- **Falls back**: a heap text, made in one block; a join longer than the room is made on the heap even in a
  function where its text never leaves.
- **Lives in**: the low proof `proofs/objects_in_the_frame` (`study.spite`, the derived addresses and the
  frees by class; `kept_parameters.spite`, whether any function keeps what it reads from a text's `_buffer`,
  asked once per program), and the pass `low_optimization_passes/object_placement`, which writes the room and the
  test of the length; `_free_String` (`low_intermediary_representation/lowering/freeing.spite`) leaves a text
  marked as living in the frame where it is.
- **Checked by**: tests/short_text_allocations (counts with `program.live_allocations()`, at the 15/16 and the
  47/48 byte edges), tests/short_text_boundaries (a stored, answered, foreign and handed-out text, output only),
  tests/short_text.

### A default replaced before any read is not made

- **Status**: built.
- **Rule**: an attribute of a local just made, assigned in the straight statements after the making before any
  statement reads the local, and not read by its constructor, is never read with its default: until the local is
  read nothing else holds the object. A quiet default no staying default reads is left out of the making
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-default-replaced-right-after-its-making-is-never-made)).
- **Buys**: the default's allocation, count and free.
- **Falls back**: the making runs every default; a branch, a loop, a `return` or a read of the local before the
  assignment keeps it.
- **Lives in**: embedded in the pass `high_optimization_passes/replaced_defaults` (`writes_after_making.spite`
  finds the writes, the pass trims the defaults), read by the lowering through `MakeObject.trimmed_defaults_key`.
- **Checked by**: tests/default_replaced_after_making (counts with `--debug-memory`),
  tests/jsx_nested_tags_set_children (counts with `--debug-memory`).

### A text is written only while nothing else holds it

- **Status**: built, embedded in the pass `high_optimization_passes/constant_texts` (D2120).
- **Rule**: every write into a text (into its length, its `Buffer` or the bytes, by any function, through `this`,
  a parameter or a local) writes a text one local of one function holds: the local starts from a text nothing else
  holds (made there, a join, a literal, or the answer of a function that answers only such texts), and until the
  statement of its last write nothing hands it on (stores, answers or passes it to a call that keeps or writes it).
  A text appended to in place after `_ready_to_grow` counts as held once, since that call copies it otherwise. What
  a function does with its `this` and its parameters (keeps them, writes them) is summarised per function and
  followed through every call until nothing changes. A text's `Buffer` is never kept: it is only read where it is,
  handed to a call that keeps nothing of it, or named by a local that does the same. A function that writes a text
  it is handed is never taken as a value or called through a shape. When anything breaks the rule the whole program
  keeps every text as today.
- **Buys**: [a text literal made once in the program's data](OPTIMIZATIONS.md#a-text-literal-is-made-once-in-the-programs-data)
  and [a text split only to search it](OPTIMIZATIONS.md#a-text-split-only-to-search-it-is-scanned-in-place): a text
  nothing writes keeps its bytes for the whole run.
- **Falls back**: every literal is made on each evaluation and every split is made, as before. A literal that starts
  a local the function writes into is made on each evaluation in a program where the rule holds.
- **Lives in**: `high_optimization_passes/constant_texts/written_texts.spite`, embedded.
- **Checked by**: tests/constant_texts (counts with `--debug-memory`, and literals appended to, written by
  `append_code` and kept).

### A data constant is never counted

- **Status**: built, embedded in the pass `low_optimization_passes/uncounted_constants` (D2200, to confirm).
- **Rule**: a register holds a data constant when every write of it is the address of a text literal laid out in the
  program's data or of a static object, a `0`, a copy or a pick (`if`-select, a join of edges) of registers that
  hold one, or the answer of a function every `return` of which answers one; a parameter never does. Inside one
  block, a register the block has set to such an address (or copied from one) holds it until it is written again,
  even when other paths give the register something else: the count taken where an `if` gives a name a literal is
  left out there. Such an object
  is never freed and nothing writes it in place: a literal lives in the data only where [a text is written only while
  nothing else holds it](#a-text-is-written-only-while-nothing-else-holds-it), a write into one takes its copy as
  before, and a test for being held once (`_ready_to_grow`) sees a count far from one. Which functions answer only
  constants is worked out over the whole program until nothing changes; none is under `--hot-reload`, where a
  function can be replaced.
- **Buys**: [a data constant is never counted](OPTIMIZATIONS.md#a-data-constant-is-never-counted): no retain and no
  release on such a register, so no locked count update on a constant, the count words every thread would share.
- **Falls back**: a register written once by anything else (a load, a parameter, an unknown call) is counted as
  before, even when it holds a constant at run time; a holder that lets go of a constant it was handed uncounted
  (a list, or the release of a name a constant reached on one path) takes its count down by one. A constant starts at 2^60, so no run takes one to zero (a billion such lettings go a
  second would take 36 years).
- **Lives in**: `low_optimization_passes/uncounted_constants` (`constant_registers.spite`, the registers of one
  function; `constant_answers.spite`, the functions that answer only constants), embedded.
- **Checked by**: tests/data_constants_are_never_counted (counts with `--debug-memory`, texts let go by their list
  and read again), tests/data_constants_are_never_counted_in_the_low_ir (no count update on a constant register).

### An interpolation compared in place answers what its text answers

- **Status**: built, embedded in the pass `high_optimization_passes/constant_texts` (D2125, to confirm).
- **Rule**: an interpolation handed straight to the library's `String.equals`, `contains`, `starts_with` or the
  compiler's `_holds_piece` is equal to a run of the other text exactly when each piece, in order, matches where the
  last one ended: a text piece byte for byte, an `Integer` or `Long` hole as the digits its `to_string()` writes
  (a `-` below 0, the digits from the last). The holes are worked out in the order the join works them out, and the
  join reads its text holes' bytes only after the last hole, as the comparison does, so no call runs between a hole
  and its reading that the join did not have too. A join on the left of `==` is compared in place only when the
  right side is a local, `this` or a literal, which nothing a hole calls can change. The written pieces are
  literals living in the program's data, so the rule runs only where [a text is written only while nothing else
  holds it](#a-text-is-written-only-while-nothing-else-holds-it).
- **Buys**: [an interpolation only compared is compared in
  place](OPTIMIZATIONS.md#an-interpolation-only-compared-is-compared-in-place): no text is made for it.
- **Falls back**: the interpolation is made and compared, as before.
- **Lives in**: `high_optimization_passes/constant_texts/compared_joins.spite`, embedded; the comparisons are
  written by `piece_forms.spite`.
- **Checked by**: tests/compared_joins (matches, mismatches, empty pieces, negative, zero and `Long` holes, the
  order of holes that call, and the counts with `--debug-memory`).

### Local and variadic lists in the frame

- **Status**: partly built (D991).
- **Rule**: a local list made by a literal or `List<T>()` and filled at its own level, then only read, lives in the
  frame; a variadic list its callee only reads lives in the caller's frame
  ([functions_and_operators.md](../spite_documentation/functions_and_operators.md)).
- **Buys**: no allocation.
- **Missing**: variadic lists; lists of objects or texts; reads other than `count()` and `[]`; constant data.
- **Falls back**: a heap list.
- **Lives in**: the speed proof `proofs/lists_in_the_frame`, run on the high representation after the acceptance
  proofs, which records on the list's declaration (and on a name that only holds it) how many items it holds
  (`Declare.frame_items`); the lowering lays out what was recorded. A name declared twice in one function is never
  placed in the frame.
- **Checked by**: tests/frame_lists, tests/frame_lists_of_decimals, tests/variadic_answers_in_frame,
  tests/text_building (output only).

### A list its callee only walks is never made

- **Status**: built for literal lists of at most 8 items (spite_compiler#486).
- **Rule**: a list made, filled with plain values and read only by one call, whose callee's whole body is
  `parameter.each(walker)` with a walker of the callee's own class, is the callee's copy taking the items, each walk
  one call per item in order ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-list-made-only-to-be-walked-is-never-made)).
- **Why it holds**: the list is fresh and no other name reaches it, so the walker cannot change it; `each` reads its
  items in order and calls the walker once for each; the callee keeps, answers and hands on nothing of the list. The
  copy shows the callee's place, so a crash report names the same frames.
- **Buys**: no list, buffer or appends per call; the call costs what the hand-written calls of the walker cost.
- **Missing**: a callee that does more than walk (a count, an index, a test); a walker passed in; a list built in
  a loop.
- **Falls back**: the list is made and walked.
- **Lives in**: `proofs/walked_lists`, which the high pass `walked_lists` asks for each candidate call before it
  writes the copy.
- **Checked by**: tests/walked_lists.

### A function value its callee only calls lives in the frame

- **Status**: partly built (only through inlining and known closures, D1043).
- **Rule**: a function value passed to a function whose every mention of it is a call lives in the caller's frame,
  uncounted ([functions_and_operators.md](../spite_documentation/functions_and_operators.md)).
- **Missing**: the "only calls it" proof over the callee, so a callee not inlined gets a counted heap value.
- **Falls back**: a heap function value with a counted receiver.
- **Lives in**: indirectly, `compile_time_evaluation/partial_evaluation.spite` (an optimisation, which calls a
  known closure directly) and the low proof `proofs/objects_in_the_frame` (a closure object the inlined callee only
  calls never leaves the caller).
- **Checked by**: tests/function_value_in_frame, tests/held_value_functions, tests/function_values.

### A back reference read holds its object

- **Status**: built (D1251).
- **Rule**: a back reference (the attribute of a cycle the compiler picks to hold no count,
  [memory.md](../spite_documentation/memory.md)) answers `null` once its object is freed, and a read of it holds its
  object for as long as the value read is used, so `child.parent.leave()` whose body lets the parent's owner go
  still runs on a live parent, and frees it when the call returns.
- **How**: the read calls `_back_counted`, which answers `null` when the object's count is zero and otherwise
  raises the count by one and answers the object; the value read is then an owned temporary, let go like a call's
  result. In a program with threads the test and the raise are one compare-and-exchange, retried when another
  thread changed the count between them, so a read never revives an object whose last release has begun.
  A back reference proven present (`crash child.parent`) may still lose its object at any later call that lets the
  owner go, so a read that relies on the proof tests the answer and halts on a freed object, "spite:
  'Child.parent' was proven present, but its object was freed since, and a back reference holds no count: prove it
  again after the call that lets it go, at ...", instead of using `null` as an object.
- **Buys**: no read of a back reference runs on freed memory, on one thread or on two.
- **Costs**: a call, a count up and a count down per read of a back reference, and a test of the answer where it
  was proven present; a program with no back reference
  carries nothing.
- **Lives in**: `low_intermediary_representation/lowering/freeing.spite` (`lower_the_back_counted`),
  `values.spite` (`held_back`).
- **Checked by**: tests/back_reference_calls, tests/back_reference_gone, tests/parent_back_reference.

### A back reference is picked from how the program links its objects

- **Status**: partly built (D759, D1396, D2525, D2526, D2580).
- **Rule**: an attribute `a: T?` of a class `C` holds no count when one function both sets `c.a = t` and stores `c`
  into `t`'s attribute `f`, which holds a `C` ([memory.md](../spite_documentation/memory.md)); never from the class
  graph alone, since taking an owning reference for a back one would free an object the program still holds. A
  collection `f` holds a `C` when its items are `C`, a union with `C` among its members, or a `type` every member of
  which `C` declares (D2525). An attribute `a: U?` holding a union, or `a: S?` holding a `type`, holds no count when
  every class it may hold links back that way: each class member of the union, or each class of the program that
  declares every member of the `type`; one that does not, or a member that is not a class, keeps it counted (D2526).
  Two objects one function makes side by side and links to each other directly (`question.answer = answer` beside
  `answer.question = question`) both die with that function when neither leaves it, so the attribute of the one made
  later is the back reference: when every function that links the two attributes this way makes the same one later
  and keeps both objects in, and no function stores into that attribute any other way (D2580).
- **How**: each function of the program is read for the stores it makes: `x.a = y`, `x.f.append(y)` (and
  `insert`, `prepend`, `add`, `set_at`), `x.f[k] = y`, and a constructor that keeps its argument in an attribute. A
  call of a program function adds that function's own stores, with `this` and its parameters replaced by the call's
  receiver and arguments, so `team.recruit(player)` beside `player.play_for(team)` links the two as
  `team.players.append(player)` beside `player.team = team` would (D1396). When two classes declare the name, the
  call is followed only into the function of the receiver's class, known when the receiver is `this`, a parameter
  of a class, an object the function makes, or an attribute of a class reached from one of these; any other
  receiver is not followed (D2525). A function's own stores
  include those of the program functions it calls, followed to a fixed point: one round over the program, then
  rounds over only the callers of a function whose summary grew, until none grows, so a link made any number of
  calls down counts (D1663, D1818, spite_compiler#26, #495). A partial reading is never used: a link found only in a later
  round can decide that an attribute pointing both ways keeps its counts. An object a function makes is named by that function and its place
  in it (`#Team:sign:1`), the same on every reading, so a summary read again is equal and the rounds end; a summary
  keeps each store once, and only stores whose keys reach at most four parts deep (`this.a.b.c`), a size budget
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#budgets-not-round-limits)): a recursive call over a chain
  (`walk(node.next)`) places the function's own stores one attribute deeper each round, so without it a summary
  grows without end. A store past it is left out, which can only hide a link: an attribute it hides a link for keeps
  its counts, and so does one that may point back to its holder (`partner: Person?`, or `beta: Beta?` beside
  `alpha: Alpha?`) whose name, or whose owning attribute's name, a left-out store wrote, since the link the other
  way that keeps both counted may be the one left out (#602; before, such an attribute was picked as the back
  reference and its object freed while still held, `tests/back_reference_other_way_past_the_key_budget`).
  A call whose summary names an object the reading function itself makes (through recursion) adds
  nothing of that object, since it is another call's object under the same name. A link found in one
  function decides the attribute for the whole program. Every class an object back attribute holds gets a back word
  (the count of back references that keep its memory); the classes a union or `type` back attribute may hold put it
  at one offset, the first slot free in all of them, so the store, the read's freed check and the release use one
  slot whichever class the value holds, with no check of its class at run time (D2526). A pair made side by side
  stays in its function (`model/made_pair_walk.spite`) when the stores read for it (its own and its callees') put
  neither object anywhere but in the other's link, and each mention of either is a name a `var` gives one of them, a
  receiver of an attribute read, a link store, a narrowing alone, or the receiver of a call of one of the two
  classes' functions whose answer is discarded or holds no object; the functions called that way, and the classes'
  constructors, are read the same way with `this` and the two link attributes as the pair. Anything else (an
  argument, a return, a list, an assignment of the local, a function value) lets the pair leave.
- **Missing**: a call of a function two classes name on a receiver whose class is not known (a local that is not
  made there), a store through keys more than four parts deep, two objects made side by side and linked directly
  where one of them leaves the function (`return answer`), one attribute pointing both ways (`partner`, as
  `tests/memory_leak_summary`), a union or `type` back attribute one of whose classes does not link
  back, and a back attribute that cannot be null: each keeps its counts and leaks, which `--debug-memory` names at
  exit. Nothing in the first three proves which side outlives the other; a class that does not link back could be
  freed while the program still means to hold it; and one that cannot be null has no `null` to answer once its
  object is freed (spite_compiler#26).
- **Falls back**: counted; the cycle leaks until the program clears the `T?` field that closes it.
- **Lives in**: `model/back_references.spite` and `model/made_pair_walk.spite`, asked by `ProgramModel.holds_no_count`; the shared back word in
  `high_intermediary_representation/layout.spite` (`place_the_shared_back_words`).
- **Checked by**: tests/parent_back_reference, tests/back_reference_two_functions, tests/back_reference_calls,
  tests/back_reference_two_levels, tests/a_back_reference_found_many_calls_down (73 calls down),
  tests/back_reference_other_way_past_the_key_budget,
  tests/back_reference_named_by_two_classes, tests/back_reference_union_items, tests/back_reference_type_items,
  tests/back_reference_union_attribute, tests/back_reference_type_attribute,
  tests/back_reference_made_side_by_side, tests/back_reference_made_side_by_side_leaving.

### A ForeignCallback kept by the object it calls holds that object back

- **Status**: built (#473, D2536 to confirm).
- **Rule**: a `ForeignCallback(f, ...)` made in a function of a class `C` (not a singleton, not generic) from `f` or
  `this.f`, one of `C`'s own functions, and kept only in `C`'s own attributes holds its owner without a count, so
  `C` holding the callback and the callback holding `C` is no cycle: `C` is freed when its last other holder goes,
  its `drop()` runs (and tells C to stop) while the callback is alive, and then the callback is released with `C`'s
  attributes ([foreign_libraries.md](../spite_documentation/foreign_libraries.md#calling-back-into-spite)). A
  callback the program may also keep anywhere else keeps its count and so its owner (D232).
- **How**: `model/kept_callbacks.spite` reads every function's written statements for such a making stored in an
  own attribute, directly or through the local it was made in, and names its site (`function key|line:column`). The
  site counts only when nothing lets the callback out: every mention of the attribute's name in the program (any
  class, so a name another class also uses keeps the count) and of the local in its function is a read of
  `.address` or `.context`, an assignment to it, a `fallback`, `crash`, `if` or `while` on it alone, or (the local)
  one of those stores. `C` then gets a back slot in the layout like the target of a back reference, and the
  function value made at the site is a `Spite.FunctionValueHoldingItsOwnerBack`: it points back at its owner
  (`_point_back`) instead of counting it, keeps the slot's offset beside the receiver, and lets the owner go back
  (`_let_go_back`) when it is freed. The trampoline reads the owner with `_back_counted`, holds it for the call and
  lets it go after. No copy can share or remake the callback: `copy()` and `deep_copy()` of a class holding a
  `ForeignCallback` are refused while compiling (below), so the owner is alive whenever C can call, with no check
  while running.
- **Buys**: the pattern foreign_libraries.md teaches frees, with no `drop()` of the program skipped.
- **Costs**: a back slot in `C`, and a count up and down around each call from C.
- **Missing**: a callback stored in another object's attribute, kept in a list, made in an attribute's default, or
  read for anything but its numbers keeps its count and leaks with its owner, which `--debug-memory` names at exit.
- **Lives in**: `model/kept_callbacks.spite`, `high_intermediary_representation/building/foreign_crossing.spite`
  (`hold_the_owner_back`), `low_intermediary_representation/lowering/calls.spite` (`point_back_at_the_owner`),
  `freeing.spite` (`let_the_owner_go_back`), `callbacks.spite` (`call_through_held_back`).
- **Checked by**: tests/foreign_callback_kept_by_its_owner_is_freed,
  tests/foreign_callback_kept_elsewhere_keeps_its_owner.

### A copy never shares or remakes a C registration

- **Status**: built (#512, Mortaro 2026-11-15, reach D2537 to confirm).
- **Rule**: a `copy()` or `deep_copy()` the compiler makes for a class is refused when the copy would reach a
  `ForeignCallback`: for `copy()`, an attribute of the class whose type is `ForeignCallback`, holds one as a type
  argument (`List<ForeignCallback>`) or is a union with it as a member; for `deep_copy()` also any class it reaches
  through attributes, type arguments, union members and the classes that fill a `type`, stopping at a class that
  declares its own `deep_copy()`. A copy of a `ForeignCallback` itself is refused too. The words name the class, the
  attribute and, when it is reached, the attribute it is reached through: "a copy of Window would share the C
  registration in '_on_close': ...".
- **How**: `Values.made_copy` and `made_copy_in`, the one place a class's copy is made, ask
  `validators/high_intermediary_representation/copied_registration` before making it, at the line being built: a
  written `x.copy()`, a bare `copy()`, a copy through a union or `type`, and the deep copy of a list of such objects
  all pass there. A class that declares its own `copy()` or `deep_copy()` is copied by it and not judged.
- **Buys**: the owner of a `ForeignCallback` it holds back (above) is the only object C can call, so the trampoline
  needs no run-time check, and `deep_copy()` no longer stops the compiler in `handed_over`.
- **Missing**: a copy through a `type` is judged by every class known to fill it, even one the program never copies.
- **Lives in**: `high_intermediary_representation/building/values.spite` (`judge_a_copied_registration`),
  `validators/high_intermediary_representation/copied_registration/validator.spite`.
- **Checked by**: conformance/foreign_callback_owner_copied, conformance/foreign_callback_owner_deep_copied,
  conformance/foreign_callback_reached_by_a_deep_copy.

### A deep copy copies a graph with its shape

- **Status**: built (D488, D724, D1252, D1397, D1754, D2545).
- **Rule**: every deep copy makes one new object per original object, so what the original reaches twice (two
  attributes, a list and an attribute, a union, a cycle, a back reference) is one object in the copy
  ([memory.md](../spite_documentation/memory.md)). A class is copied through a table made for the call unless the
  proof below shows that nothing its copy reaches can be reached twice.
- **Proof that drops the table**: for a class with no `deep_copy()` of its own, worked out per program from its
  monomorphised classes. It holds when the class cannot reach itself (no cycle, no back reference, no `type`
  attribute anywhere it reaches), has no bound type that is copied (generic items can repeat), and the classes
  each of its copied attributes can reach (through object attributes, bound types and union members, a class
  with its own `deep_copy()`, `List` and `Dictionary` included, through its bound types only) are disjoint from
  those every other copied attribute can reach. Two ways to one object part at some object: at this class
  they leave through two attributes whose reachable classes share none, so no object is on both; below it the
  attribute's own `deep_copy()` keeps the shape, by the same rule. A `List` or `Dictionary` whose items are
  copied (objects, unions, `type` values) always copies them through one table, since two items can be one
  object; a copy without a table calls that table copy for such an attribute.
- **How**: a class reaches another through an object attribute, a bound type, or a union attribute (each member of
  the union); a union attribute inside a table copy is copied through its member's `_deep_copy_in`, dispatched on
  the class it holds, with the same table. A class that reaches a `type` attribute is copied through a table
  whatever fills it, since the classes that fill a `type` are known only once the whole program is built (D1397),
  and the `type` value is copied through `_deep_copy_in` with the same table.
  A `List` or `Dictionary` whose items reach such a class (or a union or a `type`) is copied through one
  table for all its items (`_deep_copy_through_a_table`, made when a `deep_copy()` of it is built), so items that
  hold each other stay one graph; one reached inside a table copy uses that table (its `_deep_copy_in`), and is
  itself one copy however many objects hold it (`tests/deep_copy_list_graph`, `tests/deep_copy_shared_collections`).
  A collection whose items need no table copies them one by one and makes none. The table finds a copy through
  the hashed `Dictionary<Long, Long>` of `Spite.CopyTable`.
  Inside a table copy a class with its own `deep_copy()` is copied through it once and remembered, so it too is
  one object in the copy however often it is reached.
- **Falls back**: a table, whenever the proof cannot show the ways apart: a class that reaches a `type` (even when
  no filler reaches it back), two attributes of one class or of classes that reach a common one (even when the
  program only ever stores fresh objects in them), and any list or dictionary of objects.
- **Missing**: a proof from the writes (each attribute and each list written only from an object made for it and
  kept nowhere else) that would drop the table for a tree of such classes and for a list of fresh objects.
- **Lives in**: embedded, `high_intermediary_representation/building/copying.spite` (`uses_a_table`,
  `two_ways_can_meet`, `classes_reached_from`, `holds_a_type`, `copy_in_call`, `deep_copy_call`).
- **Checked by**: tests/deep_copy_graphs, tests/deep_copy_list_graph, tests/deep_copy_shared_collections,
  tests/deep_copy_union_cycles, tests/deep_copy_type_cycles, tests/deep_copy_shares_a_leaf_through_two_attributes,
  tests/deep_copy_shares_a_leaf_through_a_list_and_an_attribute, tests/deep_copy_shares_a_leaf_through_a_union,
  tests/deep_copy_shares_an_object_with_its_own_copy.

### A singleton made at the start is never tested again

- **Status**: built.
- **Rule**: a singleton the entry class's attribute defaults make on every path is made before the entry function
  starts, so a function that cannot run before those defaults end reads its slot without testing that it is made;
  the functions that may run before are the ones reached by calls and function addresses from what the start calls
  up to the defaults, the fault handler and every singleton's destroy at exit.
- **Buys**: no first-use test, and a slot load that never changes (moved out of loops, shared across calls).
- **Falls back**: the test stays in every function that may run before the defaults end, and for every singleton
  made only on some paths.
- **Lives in**: the low proof `proofs/singletons_made_at_start`, run on the low representation before the singletons
  are settled, which records `LoweredProgram.made_at_start` and `runs_before_the_entry`; the passes
  `low_optimization_passes/made_singletons` (once, and `Settled` in each cleaning) skip the tests it recorded.
- **Checked by**: tests/singleton_attribute_reads (output only).

## Borrowing and lending

These proofs let the lowering pass a value uncounted where its holder outlives the use. The borrow study of a
`Vector` or `Items` item (its refusals of a kept, listed, returned or renamed item, of a read past a resize, of rows
and of lends: D729, D730, D1139 to D1141, D1399, D1400) could no longer be reached once those classes left (D1707)
and was removed (#274); a `List` that stores its items inline (#205) keeps counted every item it cannot follow, and
refuses nothing (D1781).

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
- **Lives in**: the lowering, `function_lowering.spite` (`note_the_borrowed_parameters`), `calls.spite` (`is_steady`).
- **Checked by**: tests/held_arguments, tests/held_value_functions.

### An attribute a call cannot assign is passed uncounted

- **Status**: built.
- **Rule**: an attribute path from `this` or a held name whose callee may assign none of its attributes is passed
  uncounted; see `OPTIMIZATIONS.md`.
- **Falls back**: counted before the call and let go after.
- **Lives in**: the lowering, `calls.spite` (`is_a_steady_attribute`), `high_intermediary_representation/assignments.spite`
  (`may_assign`).
- **Checked by**: tests/held_paths.

### A singleton attribute that never changes is read in place

- **Status**: partly built.
- **Rule**: an object attribute of a singleton assigned by no function but its constructor is read from other
  classes as its address, with no count and no lock. Attribute by attribute: a number, `Boolean`, enum or object
  attribute (not a text, not nullable, not embedded, lent or a back reference) that nothing assigns after its
  singleton is made, and of a class no `type` writes through, holds the same value for the rest of the program, so
  its load through a singleton made at the start is the same everywhere and is moved out of loops and shared.
- **Missing**: the read with no count for an object attribute of a singleton that has other attributes that change.
- **Falls back**: a counted read, loaded where it is written.
- **Lives in**: `high_intermediary_representation/singleton_forms.spite`, the low proof
  `proofs/singletons_made_at_start` (the next section), the passes `made_singletons` and `unread_objects`; the
  attributes by the proof `proofs/steady_singleton_attributes`, the last of the high passes
  (`HighProgram.steady_singleton_attributes`), which `made_singletons` reads to mark the loads. Not in the
  inspectable builds.
- **Checked by**: tests/singleton_attribute_reads, tests/steady_singleton_reads (output only).

### A list's templates read their elements uncounted

- **Status**: built.
- **Rule**: in a template's pass, an element is read uncounted when the rest of the pass cannot let go of an object
  or write a list of the element's class.
- **Falls back**: a counted read.
- **Lives in**: the lowering, `statements.spite` (`is_a_borrowed_local`, `gather_the_sources`).
- **Checked by**: tests/template_lend_drop, tests/fused_chain_allocations, tests/fused_chains, tests/kept_templates,
  tests/member_templates.

### An item written back to its own slot is the slot

- **Status**: partly built.
- **Rule**: between `var item = list[index]` and `list[index] = item`, with nothing between that may change the
  name, the index, the path or the list, the write-back is not written and the read is uncounted.
  A write-back nested in an `if`, a `while` or a block after the read is the slot too, when the index never moves in
  the rest of the block and nothing else there can change the name, the path or the list.
- **Missing**: lists other than a library `List` of numbers or objects.
- **Falls back**: a counted read and the write-back written.
- **Lives in**: the lowering, `statements.spite` (`write_back_of`, `is_a_write_back`,
  `leaves_alone_but_a_nested_write_back`).
- **Checked by**: tests/slot_write_backs, tests/nested_write_backs.

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
- **Lives in**: the lowering, `statements.spite` (`is_a_borrowed_item`), `list_reads.spite` (`held_item`).
- **Checked by**: tests/held_items, tests/slot_write_backs.

### A list item read only to test it is not counted

- **Status**: partly built.
- **Rule**: a presence test of `list[index]` tests the slot in place.
- **Missing**: lists of nullable items, and a test of a path through the item.
- **Falls back**: a counted read and its release.
- **Lives in**: the lowering, `values.spite` (`lower_presence_test`), `list_reads.spite`.
- **Checked by**: tests/tested_items, tests/items_presence.

### An item used at once is not counted

- **Status**: partly built.
- **Rule**: a proven `list[index]` used once, as a receiver or passed to a call that cannot change the list, is
  read in its slot.
- **Missing**: indices and arguments that are not plain reads (or such item reads), and a call through a function
  value.
- **Falls back**: a counted read.
- **Lives in**: the lowering, `calls.spite` (`is_a_held_receiver`, `is_a_held_item`,
  `is_a_held_argument`).
- **Checked by**: tests/items_at_once, tests/held_item_arguments.

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

### A list its setup fills holds what the setup made

- **Status**: built.
- **Rule**: a list attribute read only by the one function that appends its parameter to it and by counted loops
  over it, written by nothing but its default, and filled only from the class's setup with objects the setup makes
  (a `register` called anywhere else leaves the loop as written, D1781),
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

### A list used only as a set

- **Status**: built.
- **Rule**: every list value has a place: a name or a parameter of a function, a function's answer, an attribute of a
  class, or the items of the lists and dictionaries of a place. Assigning, passing, answering, putting a list into
  another list or a dictionary and reading it back join two places into one family, and the items of joined lists
  are joined too. A family is used only as a set when it is searched (`contains`, `index_of`, or a
  [search loop](OPTIMIZATIONS.md#a-search-loop-over-such-a-list-is-one-lookup)), when no call writes it but `append`
  (any other function of `List` that writes, and any the proof does not name, marks the family written), when none
  of its lists reaches code the proof does not follow (a foreign call, a function value, a call through a `type`, a
  conversion into a union or a shape, an answer one of those hands back, or the receiver of a function taken as a
  value: each taints the family, and the items of a tainted list are tainted too), and when its items are `String`s
  or whole numbers. The functions of `List` and `Dictionary` themselves are not walked: a call of one is judged by its
  name. Where a list was made does not matter: a list made elsewhere holds no index yet and is searched item by item
  until its searches index it.
  A family is never a set when code that may run at once with other code searches it, appends to it or walks it
  in a search loop, since `contains$set` writes the list's count of items read and builds and stores its index:
  code that may run at once is every function the compiler starts on the pool (a `Parallel`: a band of a banded
  loop, a call of overlapped work; and a `Concurrent` of a frame loop), what its starter does from the start to
  the join that answers it in the same block (the whole starter when that join is anywhere else), and everything
  that code reaches: every function it calls, every filler's member of a shape it calls through, every
  constructor and attribute defaults of what it makes, every function handed straight to the parameter whose value
  it calls (every function taken as a value when it calls one that is not a parameter, a parameter that was handed
  on or reassigned, or once any function value goes to a call through a shape, a function value or a foreign
  function), and every `drop`. A function that code run at once enters only by calls (a call or a constructor,
  never as a value, a `drop`, a whole starter or a filler) calls through its parameter only what those calls hand
  it, which they reach themselves, so `list.each(f)` run at once reaches `f` and not every function the program
  hands to `each` elsewhere (D2290). The passes that start work run before this proof and leave each start in the
  IR (`Conversion` of kind `into_handle`), so the proof reads them there; nothing else records them.
  A search or an `append` in a band of a loop over a list's positions does not count when the band's own proof
  ([passes that write only what they alone reach](#passes-that-write-only-what-they-alone-reach)) saw its list, in
  every study of it, only as a list the pass made (made in the pass, or read from an attribute of something the pass
  made into which the pass stored only lists it made), and the function holding it runs at once only in such bands,
  outside a starter's region: no other band, and no other thread, reaches a list a pass made, so the count and the
  index its searches write are the band's own (D2290). Everything else that runs at once still counts: overlapped
  work, a frame loop, a band of `list.each_f()`, a starter until its join, a `drop`, a function value, and what a
  band reaches only through a block that ends the program, which its proof does not study.
- **Buys**: [a list used as a set keeps a hash index](OPTIMIZATIONS.md#a-list-used-as-a-set-keeps-a-hash-index): it
  marks each `contains`, `index_of` and `append` of the family (`Call.is_on_a_set`) and each search loop over it
  (`While.searches_a_set`).
- **Falls back**: the list as written, searched item by item; nothing is refused.
- **Lives in**: the proof `proofs/set_lists`, registered among the high passes through `HighOptimizationPasses.Proving`
  right before `indexed_lists`, which acts on its marks; a search loop's shape is
  `high_intermediary_representation/search_loop.spite`; what runs at once is `high_intermediary_representation/run_at_once.spite`
  with `reaches_only_handed_values` on, walked
  twice: once from every start, and once leaving out the bands whose proof followed every list (`HighProgram.band_fresh_classes`)
  but walking the blocks their proof skipped (`HighProgram.band_ending_blocks`). The band proof marks each search and
  `append` it studied by the lists it saw there (`Call.receiver_made_in_a_band`, `Call.receiver_not_made_in_a_band`,
  `Owned.Writes.keep_the_set_calls`) once the loop is banded.
- **Checked by**: tests/lists_used_as_sets (a 100,000-item set answers `contains` about as fast as a 1,000-item one,
  and a list that stops being a set keeps its answers), tests/set_searched_in_bands (a set every band searches
  keeps its plain `contains` and answers the same every run), tests/set_private_to_a_band (a set each pass of a
  band makes keeps its index, read from the high representation), tests/set_shared_between_bands (a set made
  before the loop and searched by every band keeps its plain `contains`).

## Threads and locks

The rules are in [concurrency.md](../spite_documentation/concurrency.md) and, for the counts,
[memory.md](../spite_documentation/memory.md).

### Calls that share nothing written

- **Status**: partly built (spite_compiler#218).
- **Rule**: in a straight run of declarations `var name = receiver.function(arguments)`, a call is quiet work when
  its receiver is `this` or an attribute of `this`, its arguments and answer are numbers, and its function, through
  every function it calls, belongs to an ordinary class of the program or to the entry class (no singleton), takes
  and answers only numbers, writes only its own locals, reads only its parameters and locals, calls only functions of
  `this`, and holds no object, text or list, no attribute, no fallback (it writes the fallback ring), no foreign call or
  function value, and no recursion. It may halt (D1747): a block that ends the program (a `crash` and its report),
  whole-number arithmetic that keeps its overflow or divisor check, and a narrowing of one number into another.
  Each quiet declaration whose work may halt is marked too (`Declare.quiet_work_may_halt`), found by proving it again
  with nothing that halts allowed. Two quiet calls in a
  row are independent when the later one's arguments read no name the earlier ones of the run declare; neither can
  see the other, since neither writes anything another reads. The proof marks each quiet declaration
  (`Declare.is_quiet_work`) and each that stands apart from the whole run before it
  (`Declare.stands_apart_from_the_run_before`).
- **Buys**: [independent calls in a row run at once](OPTIMIZATIONS.md#independent-calls-in-a-row-run-at-once).
- **Missing**: every other kind of statement (calls answering nothing, attribute and list writes kept apart, output
  kept in order, statements that are not side by side) and work found by the data it touches rather than by call
  (spite_compiler#242).
- **Falls back**: the calls run in order, as written.
- **Lives in**: the speed proof `proofs/independent_work`, registered among the high passes right after
  `banded_loops`; the high pass `overlapped_work` right after it only acts on its marks.
- **Checked by**: tests/overlapped_work, tests/overlapped_work_runs_at_once, tests/overlapped_work_crashes,
  tests/overlapped_work_halts.

### Classes in a list that share nothing written

- **Status**: missing. **Falls back**: a plain loop. **Checked by**: tests/row_of_classes (output only).

### Passes that write only their own item

- **Status**: partly built.
- **Rule**: every pass of `list.each_f()` writes only its own element and reads nothing another pass writes, so the
  passes run in bands.
- **Missing**: `Vector`; writes other than the element's number and enum attributes; calls other than its own
  number functions; a kept thread pool.
- **Falls back**: the loop in order.
- **Lives in**: embedded, the high pass `high_optimization_passes/banded_loops` (`pass_weights.spite`).
- **Checked by**: tests/band_passes, tests/banded_pass_halts (a pass that halts prints what came before the loop
  and nothing after it, as running in order does, spite_compiler#222).

### A pass whose inputs did not change is skipped in a fixed-point loop

- **Status**: missing (spite_compiler#421).
- **Rule**: in `changed = true; while changed [and round < limit] { changed = false; list.each(f) [round = round + 1] }`
  (or the same loop by index), the pass `f(item)` is skipped when nothing it read since its last run has changed,
  and every other pass runs in list order, so rounds, writes and their order stay as written. A skipped pass would
  read the same values, take the same path and write what is already there. It holds when: `f` does no IO and
  depends on no address; every read of state the loop writes is recorded per item (an attribute of one object, a
  key of a `Dictionary`, an item of a `List` used as a set), skipping reads its own run wrote first; every write
  that changes a recorded value marks its readers to run again, the writer included (an `append` that is not
  guarded by `contains` marks its own pass every time); and state every pass writes before reading (a scratch
  attribute) is never read after the loop before it is written again.
- **Missing**: all of it. The two loops it is for do not meet it as written: `Holders.keys_of` (reached from
  `ExactSums.spread_through`) keeps a one-entry memo, `defined_function`, that every pass reads and the next pass
  overwrites, so recording reads marks every pass that reaches it as changed each round, unless a memo whose
  answer depends only on its key is proven; and both loops leave scratch attributes (`current_key`, `aliases`,
  `local_wholes`, `is_local`, `Operands.defines`) whose deadness after the loop no proof answers today.
- **Falls back**: every pass runs every round.
- **Checked by**: tests/fixpoint_rounds (40 rounds, values flowing against the list order, a scratch attribute and a
  memo read after the loop, an unguarded `append`, and a loop stopped by its round limit).

### Passes that write only what they alone reach

- **Status**: partly built (spite_compiler#411).
- **Rule**: a pass of `list.each_f()` that the number rule above refuses still runs in bands when every value it
  handles, through every function it calls (the library's included) and every constructor and attribute defaults
  of what it makes, has a known origin, and it writes only through values that are its own. A value is made in the
  pass (an object or a list it makes), the element itself, or shared (anything else: a text written in the
  source, an attribute of the element or of anything shared, what a shared list holds). A write of an attribute,
  and a write the compiler supplies for a list or a buffer (`_write_value`, `_write_*_at`, `_forget_value`,
  `_reserve`), goes only to the element or to what the pass made. What a pass reads back from an attribute of
  something it made is what any pass stored there, joined, so a shared value kept in a fresh list is read back
  shared. A shared value that could be an element (of the element's class, a union, a shape or a function value)
  refuses the pass, so no pass reads another's element. Each function is studied once for each origin of its
  receiver and arguments; the stores are joined over the whole pass until they settle. A taken `fallback`, and any
  [call that only changes a singleton](#a-call-that-only-changes-a-singleton-waits-for-the-join), is no use of
  it. Refused: any other use of a singleton, a foreign call, a function value, a call
  through a shape, a wait or a handle, recursion, and a function the compiler supplies outside that list. A block
  that only ends the program (a `crash` and its report) is not studied: the pass may halt (D1747).
  A `contains` of a shared list stays a read: [a list used only as a set](#a-list-used-only-as-a-set) keeps no
  index for a list that code run at once searches, unless the pass made that list itself.
- **Buys**: [bands](OPTIMIZATIONS.md#a-loop-whose-passes-write-only-their-own-item-runs-in-bands) for a pass that
  makes objects, lists and texts per element and writes any attribute of its element.
- **Missing** (spite_compiler#411): writes through objects the element alone reaches (a run-time walk that every
  one is held once), reading singletons that never change, function values, the compiler's
  own form of a loop over a list's positions that hands each item to a fresh worker and writes its answer back
  to the item's slot, and appends to shared lists joined in item order.
- **Falls back**: the loop in order, as written. A loop over a list's positions heavy enough for bands that the
  proof refuses is listed by `--optimization-report` under "Loops run in order", with the first thing that refused
  it and the function it was in (and the program's own function that reached it, when that one is the library's).
- **Lives in**: `high_optimization_passes/banded_loops/owned/writes.spite`, tried by the high pass `banded_loops` (and by `position_loops.spite` for a loop over positions)
  when `pass_weights.spite` refuses; the pass is weighed as [calls in a row](OPTIMIZATIONS.md#independent-calls-in-a-row-run-at-once)
  weigh theirs (`overlapped_work/work_weights.spite`), every function it reaches included.
- **Checked by**: tests/band_passes_that_make_objects, tests/loops_run_in_order_reported (the report names a
  pass's fallback and a write into a list the pass does not own).

### An object made for its owner is told apart

- **Status**: missing. **Falls back**: nothing runs at once, so nothing depends on it. **Checked by**: none.

### No other thread counts a class

- **Status**: built.
- **Rule**: code that can run on another thread is every function a `Parallel` or a `Concurrent` starts (a band of
  a banded loop among them: the compiler starts it with the same IR node), every function those call, every constructor and attribute defaults of what they make, and, where they call a function
  value, every function the program takes as a value. A class is counted by another thread when that code names a
  value, a local, a parameter, an answer or an attribute of it, or of anything that holds it (an attribute, a list's
  or a dictionary's items, a union's member, a shape's filler); a function value there counts every class whose
  function is taken as a value, and a union or shape whose members are not known counts every class. A program that
  makes a `ForeignCallback` counts every class atomically.
  A band of a loop over a list's positions is walked on its own, and leaves out the classes its proof
  ([passes that write only what they alone reach](#passes-that-write-only-what-they-alone-reach)) saw only as
  objects the pass made (`Writes.fresh_classes`), less every class a value the pass did not make, or a write
  through its item, can reach (`Writes.held_types`, followed through attributes, list items, union members and
  shape fillers); a block that only ends the program counts every class it names.
- **Buys**: [plain counts](OPTIMIZATIONS.md#plain-counts-where-no-other-thread-counts-a-class) for every other
  class whose objects' class is known where they are counted.
- **Falls back**: an atomic count wherever the class is not known while compiling, or another thread may count it.
- **Lives in**: `proofs/no_thread_counts`, registered among the high passes right after `singleton_locks`, whose
  walk it reads; it records `HighProgram.thread_counted_classes`.
- **Checked by**: tests/plain_counts, tests/thread_counted_classes (output only), tests/plain_counts_in_bands
  (a class only a band's passes make takes no locked count, read from the low representation).

### A function only one thread runs counts plainly

- **Status**: built.
- **Rule**: a function runs alone when no code that may run at once with other code reaches it, by the walk of
  [a list used only as a set](#a-list-used-only-as-a-set) (`high_intermediary_representation/run_at_once.spite`,
  with `reaches_only_handed_values` off, so a function run at once that calls through its parameter reaches every
  function the program hands to it anywhere, not only what the calls run at once hand it as D2290 lets the set walk do):
  not a function the compiler starts on the pool, nor one they reach, nor a `drop`, nor a function that starts work
  itself. Such a function only ever runs while no other thread the compiler made runs: every start is joined in the
  block that made it, and the join waits for the work and everything it let go, so what the bands counted is
  settled before the function goes on. So every count it takes or lets go, of any class, a union, a shape or a
  value whose class is not known, is plain. It holds for the whole program only when nothing else can run beside
  it: no `ForeignCallback` (C may call it on a thread of its own), no start whose join is not in its own block (the
  work may outlive the function that started it), and no interactive build (the prompt and the reloader start
  threads of their own).
  The lowering then checks the rule against what it wrote: from every function that does not run alone (the
  functions the compiler writes itself among them, but `_start`, which runs before any thread), it follows every
  call, function address and thread start it wrote; a function counted plainly that one of those reaches is
  counted atomically again, and so on from it, so a call the lowering adds that the walk did not see never runs a
  plain count beside another thread. A band's `<key>$logged` copy
  ([a call that only changes a singleton waits for the join](OPTIMIZATIONS.md#a-call-that-only-changes-a-singleton-waits-for-the-join))
  never counts alone, whatever its function's mark: only bands call it, and they run at once.
  A function both kinds of code call is written twice: from every function that runs alone (and `_start`, which
  runs before any thread), each direct call the generator writes to a function that does not run alone reaches a
  copy of it, `<key>$alone`, written from the same low function with no `lock` on its count updates (a retain, and
  a count a release takes down), whose own calls reach copies the same way. A function that starts work (a call of
  `_pool_submit` or a thread start), a resumable step and the end of a thread get no copy: the code that calls them
  runs alone again once they answer. A function value always points to the copy with locked counts, and a stop's
  words name the function as written.
- **Buys**: [plain counts in code no other thread runs](OPTIMIZATIONS.md#a-function-only-one-thread-runs-counts-plainly).
- **Missing**: inside a band, an object made and let go there, or held once through its item, still counts
  atomically unless its class does not reach another thread
  ([a class only a band's passes make](OPTIMIZATIONS.md#a-class-only-a-bands-passes-make-is-counted-plainly)).
- **Falls back**: the counts of [no other thread counts a class](#no-other-thread-counts-a-class).
- **Lives in**: the proof `proofs/alone_counts`, registered last among the high passes, which marks
  `HighFunction.runs_alone`; the lowering (`counting.spite`) counts plainly where `FunctionLoweringState.counts_alone`
  holds, and `lowering/alone_counts.spite` checks the calls it wrote; the copies are
  `generators/windows_x64/alone_copies.spite`, written by the emitter after every other function.
- **Checked by**: tests/plain_counts_alone (a function only the program's thread runs lets go of a class the bands
  count without a locked count, while one the bands call too keeps its locked counts; read from the low
  representation), tests/set_searched_in_bands, tests/band_passes (the same output on every run).

### What one of the calls run at once counts

- **Status**: missing. **Falls back**: atomic counts once threads exist. **Checked by**: none.

### Objects of a class made on one thread

- **Status**: missing.
- **Falls back**: blocks come from each thread's own size lists, through a call.
- **Checked by**: tests/class_pools, tests/threaded_class_objects (output only).

### A copy nothing changes is the original

- **Status**: built.
- **Rule**: while a `copy()` or `deep_copy()` kept in a `var` lives, nothing writes anything (no attribute, no list,
  no buffer's bytes, in its statements or in what they call), nothing of it outlives its block, and nothing in the
  program asks a copied class which object it is (`is_same_instance` or another comparison of addresses; the
  `equals` a class is given compares attributes and is not read for this); the copied classes have no `drop()`, no back reference and no
  cycle ([memory.md](https://github.com/Spite-Language/spite_documentation/blob/master/memory.md)).
- **Buys**: the copy is the original, counted once more: no object is made and none let go
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-deep-copy-nothing-changes-is-the-original)).
- **Falls back**: the copy, as written: a write anywhere while it lives, a call whose effects are not known, a copy
  kept or answered, a comparison of a copied class anywhere, threads, work or callbacks, an interactive build.
  Nothing is an error, and nothing changes in what the program prints.
- **Lives in**: the speed proof `proofs/copies_nothing_changes`, registered among the high passes right after
  `no_thread_counts` (it reads what each call may assign, `HighProgram.assignments`, and the waits), which marks the
  declaration (`Declare.shares_the_original`); the high pass `shared_copies` right after it only acts on the mark.
- **Checked by**: tests/shared_copies (output only).

### A fused chain leaves its first list

- **Status**: built.
- **Rule**: no member a chain's steps run (a `filter_`, `map_` or `find_by_` step, or the last step) reaches, through
  everything it calls, a write of the chained list's class: its slots (`_write_value`, `_forget_value`), its growth or
  any of its attributes (`_length` among them). The writes are those `HighIntermediaryRepresentation.Assignments`
  gathers, keyed by class, so a member that writes any list of that class counts. A member read as an attribute writes
  nothing (spite_compiler#240).
- **Buys**: the chain runs as one loop over the first list read in place
  ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#a-chain-of-filter_-steps-runs-as-one-loop)).
- **Falls back**: each step on its own copy, as written, and the optimisation report lists the chain under "Chains run
  step by step" naming the member. Nothing is an error, and the output is the step-by-step output.
- **Lives in**: `proofs/chains_leave_their_list`, asked by the high pass `fused_chains` for each chain it would fuse;
  it reads the program's assignments itself, the first time a chain has a member function, since `call_assignments`
  runs later.
- **Checked by**: tests/fused_chain_changes_its_list.

### Which singletons another thread reaches

- **Status**: built.
- **Rule**: walk the calls from every function the pool can run, and from every function handed to C
  as a `ForeignCallback`, which C may call on a thread of its own (D1137); a reached singleton is made safe, an
  unreached one takes no lock. A reached function that reads or writes an attribute of a singleton of the program
  directly, from another class, reaches that singleton too (D1138).
- **Falls back**: locked.
- **Lives in**: `high_intermediary_representation/waits.spite`, recorded by the high pass `singleton_locks`.
- **Checked by**: tests/foreign_callbacks.

### No other thread touches a singleton

- **Status**: missing (the second walk over the tree-shaken program).
- **Falls back**: the form the first walk chose.
- **Checked by**: none.

### Read-only and atomic singletons

- **Status**: built.
- **Rule**: a singleton nothing changes after it is made takes no lock; one whose changing attributes are numbers
  touched once per function, outside loops, is atomic. In a singleton that keeps its lock, a whole number or `Boolean`
  attribute that each of its functions writes at most once, outside loops, not again through another of its
  functions and not beside a call through a function value or a `type`, is atomic on its own: it is never seen half
  changed, so a read of it from another class takes no lock.
- **Buys**: no lock for the singleton, or for each read of an attribute atomic on its own from another class.
- **Falls back**: the whole singleton takes its lock; a write from another class to an attribute atomic on its own
  still takes it, around the whole statement.
- **Lives in**: `high_intermediary_representation/singleton_forms.spite` and `waits.spite`, recorded by the high pass
  `singleton_locks`; the attributes atomic on their own by the proof `proofs/lone_atomic_attributes`, registered among
  the high passes right after `singleton_locks` (`HighProgram.lone_atomic_attributes`), read by the lowering
  (`singletons.spite`, `reads_under_the_lock`). Not in the inspectable builds.
- **Checked by**: tests/singleton_forms, tests/singleton_lock_calls, tests/lone_atomic_counter,
  tests/steady_singleton_reads (output only).

### A call that only changes a singleton waits for the join

- **Status**: built for calls from bands (spite_compiler#441, D2210, D2211).
- **Rule**: in a pass the band proof studies, a call is written down instead of made when its receiver is a
  singleton made with no arguments, its function answers nothing and is not a constructor, and each of its
  arguments (at most two) is a text written in the source, a whole number, a `Boolean` or an enum. The band
  refuses every other use of a singleton, so nothing a band runs can read what such a call changes, and the
  arguments need no count. A band chunk's calls are replayed in the order of the list's positions after the join,
  so the singleton sees the calls in the order running in order makes them. A pass the number rule bands
  (`pass_weights.spite`) calls no singleton but the fallback ring, through its `fallback`s, whose site texts are
  written in the source. The band calls copies of the functions it reaches (`<key>$logged`), and only the copies
  write the call down; every function a band can reach the call from is copied, reading the lowered calls, with a
  call through a function value taken to reach every function made a value, whose value made in a copy names the
  copy. Code outside bands is lowered as written.
- **Buys**: [bands for passes that take fallbacks](OPTIMIZATIONS.md#a-call-that-only-changes-a-singleton-waits-for-the-join),
  and no lock for a singleton only bands reach this way: the walk of [which singletons another thread
  reaches](#which-singletons-another-thread-reaches) stops at such a function from a band, after every other start
  is walked whole.
- **Missing**: calls from overlapped work and `Parallel` (they keep the lock); arguments other than numbers and
  texts written in the source; a singleton split into one per group of attributes its callers use apart (D2210).
- **Falls back**: the band refuses the pass, which runs in order.
- **Lives in**: `high_optimization_passes/banded_loops/owned/writes.spite` (`is_a_deferred_call`),
  `banded_loops/pass.spite` (`keep_the_fallback_ring`), `high_intermediary_representation/waits.spite`
  (`reach_from_a_band`), the lowering (`band_copies.spite`, `deferred_writing.spite`).
- **Checked by**: tests/band_fallbacks_replayed, tests/band_fallbacks_traced, tests/band_singleton_calls_replayed.

### A function that touches no changing state takes no lock

- **Status**: partly built.
- **Rule**: a function that reads or writes no changing attribute, and calls nothing that does, runs unlocked; a
  call from a locked function to another of the same singleton goes to its unlocked body.
  A read of a number, `Boolean` or enum attribute of its own that nothing assigns after the singleton is made is no
  touch: it holds the same value for the rest of the program.
- **Missing**: a call between two locked functions takes the lock again.
- **Falls back**: the lock, taken again by its owner. A lock that would wait forever is still judged by the
  attributes a function names, so a function naming an attribute nothing changes is
  refused there as before.
- **Lives in**: `high_intermediary_representation/waits.spite` (`touch_what_reads_a_changing_attribute`),
  `function_lowering.spite` (`is_locked_here`), `calls.spite` (`lower_call`).
- **Checked by**: tests/singleton_stateless_calls, tests/singleton_function_values, tests/steady_singleton_reads
  (output only).

### Reading functions share the lock

- **Status**: partly built (D988): only for a counted loop that holds the lock.
- **Falls back**: the lock alone.
- **Lives in**: `high_intermediary_representation/waits.spite` and `coarse_loops.spite`.
- **Checked by**: tests/singleton_reads.

### A counted loop takes a singleton's lock once

- **Status**: built.
- **Rule**: a counted `while` that calls only one singleton's functions and plain helpers, and reaches no wait,
  start or other lock, takes the lock once.
- **Falls back**: a lock per call.
- **Lives in**: `high_intermediary_representation/coarse_loops.spite` and `waits.spite`.
- **Checked by**: tests/coarse_locks.

### A loop that starts no task tests for tasks once

- **Status**: missing. **Falls back**: the task count is tested on every call. **Checked by**: none.

### No attribute is read past the lock

- **Status**: partly built (D1138, D1254).
- **Rule**: no attribute of a locked singleton is read or written directly from another class, except a lone atomic
  one, without its lock.
- **How**: the lowering takes the singleton's lock (re-entered by the thread that holds it) around a load of a
  locked singleton's attribute from a function of another class, and around the whole statement that assigns one,
  so `tally.total = tally.total + 1` from another class adds once per run. An attribute nothing assigns after the singleton is
  made (outside its constructor and defaults) is read with no lock, since it holds the same value for the rest of
  the program. A counted attribute (an object, a list, a text) read this way is counted before the lock is let go,
  so a write on another thread cannot let it go between the load and the count (D1254).
- **Missing**: the old compiler's plain attributes under the lock and atomic attributes are not built.
- **Lives in**: `low_intermediary_representation/lowering/singletons.spite` (`locks_from_outside`), reading
  `waits.spite` (`is_a_locked_class`).
- **Checked by**: tests/singleton_outside_writes.

### A loop that can never end is an error

- **Status**: partly built.
- **Rule**: every `while true` is refused, since a loop states the condition it runs under (D1746, "A condition
  known while compiling is an error"). A loop whose condition reads only locals
  (and parameters) that nothing inside it assigns, and that has no `return`, `fallback` or `crash`, is endless too:
  when it also calls nothing it is refused on its own ("'while running' never ends: nothing inside it changes
  'running', ..."). A condition reading an attribute, a member or a call is not judged.
- **Missing**: a call through a function value, a `type` or a union is not followed.
- **Missing**: a loop on an attribute nothing in it changes is not read as endless, since another thread may set it.
- **Falls back**: refused, "'while true' is decided while compiling and is always true here: ...".
- **Lives in**: `statements.spite` (`note_a_decided_condition`), `validators/abstract_syntax_tree/unchanged_loop`
- **Checked by**: conformance/spinning_loop, conformance/unchanged_loop; tests/parallel_loop_that_leaves.

### A write to an object only this function holds must be read

- **Status**: built.
- **Rule**: a write to a local only this function holds, never read after it, is refused
  ([failure.md](../spite_documentation/failure.md#nothing-fails-silently)). The local holds a constructor's result,
  a copy, or the answer of a function (its own class's, `this`'s or another object's, through any number of calls) whose
  every `return` is such a result or a local made so that it only reads or writes through; the last whole
  assignment before the write (`made = Tally()`) says what it holds. A write inside a branch of an `if` or a
  `switch` to a local an outer block made is judged the same way, when nothing after it in any block around it
  names the local and nothing from the declaration to the write (the conditions and the other branches included)
  can let the object go. A loop between them is crossed only when the loop names the local just to write it
  (`tally.count = round`, `first = round` for a local read from a list item); any other mention in the loop may be
  its next pass reading the write.
- **Falls back**: not refused for a library class's answer or a loop that reads the local.
- **Lives in**: the proof `proofs/lost_writes`, judging every assignment the builder recorded (a `StatementSite`),
  and `validators/high_intermediary_representation/lost_write`, handed whether anything lets the object go.
- **Checked by**: conformance/lost_writes, conformance/lost_write_in_a_branch, conformance/lost_write_in_a_loop,
  conformance/lost_item_in_a_loop, conformance/lost_write_answered_elsewhere, conformance/lost_write_after_a_new_object,
  conformance/lost_write_made_by_a_function, conformance/memory_replaced_depth_5 (an item answered through five calls);
  tests/lost_writes_read_later keeps writes that are read.

### A name read from a list, assigned and never read, is an error

- **Status**: built.
- **Rule**: a local read from a list item, then assigned as its last mention, is refused: the list still holds the
  old item ([memory.md](../spite_documentation/memory.md#a-name-read-from-a-list-names-the-item-until-you-assign-it)).
- **Lives in**: the proof `proofs/lost_writes` (`check_a_replaced_item`), and
  `validators/high_intermediary_representation/lost_write`, handed whether the local still holds the item.
- **Checked by**: conformance/replaced_items, conformance/memory_replaced_branch,
  conformance/memory_replaced_answered, conformance/memory_replaced_unwritten; tests/memory_replaced_allowed.

### Which calls suspend work the compiler starts

- **Status**: built.
- **Rule**: a function the compiler starts as a state machine (a wait in a frame, reads in a row) that can wait, and
  every waiting function it calls, gets a resumable copy.
- **Falls back**: a wait the study does not see as such runs the event loop in place.
- **Lives in**: `high_intermediary_representation/waits.spite`, `lowering/machine_writing.spite`.
- **Checked by**: tests/frame_waits, tests/frame_waits_kept.

### A wait in a frame is started

- **Status**: built.
- **Rule**: in a loop that sleeps, a call with no arguments and no answer that can wait is started as a
  state machine of the compiler's own, unless either side writes back a value read before a wait
  ([concurrency.md](../spite_documentation/concurrency.md#a-wait-in-a-frame-does-not-hold-the-frame)).
- **Falls back**: it waits where it is written, listed under "Waits that hold the frame".
- **Lives in**: `high_intermediary_representation/building/frame_starts.spite`.
- **Checked by**: tests/frame_waits, tests/frame_waits_kept.

### Reads in a row are independent

- **Status**: missing. **Falls back**: the reads run one after another. **Checked by**: tests/overlapped_reads
  (output only).

## Other refusals built on an analysis

### Unused is an error

- **Status**: built.
- **Rule**: a name, parameter or attribute only written and never read is refused
  ([style.md](../spite_documentation/style.md#nothing-unused)). An attribute is read when a built function
  reads it, counted for the class that owns it (every `AttributeRead` of the high representation, whatever made
  it: the program's code, a template's walk, a writer of JSON or binary, `to_debug`), so another class's attribute
  of the same name never hides it. A function no call reaches counts the same way, from the functions
  `Builder.check_the_unreached` builds before it puts them back (`HighProgram.checked_functions`). Code the
  builder does not build still counts from the syntax tree: a bare name as its own class's attribute, and `x.name`
  by name for every class, while a call `x.name()` counts only for an attribute holding a function, so an
  uncalled `list.count()` cannot hide a program's unread `count`; that is a function the unreached check skips (a generic class's, one taking a
  function, a shape or a walked member), an attribute default of a class never made, and a
  whole function from which the builder folded a branch away (it records each one, `Context.folded_functions`).
  Standard library code the builder neither built nor folded counts no `x.name`: it never runs, and the library's
  own attributes are not checked, so its uncalled `other.red` cannot hide a program's unread `red`. Library code the builder
  folded counts no `x.name` either: library code names only library classes and reaches a program's class only
  through a copy made for it, which is built and counted by type. Such an `x.name` in a generic class of the program
  counts only for the classes that template reaches (`proofs/every_attribute_is_read/template_reach.spite`): the
  bound types of its copies, the classes its file names, and, from each of those, the classes its attributes,
  parameters and answers name. An `x.name` on `.attributes[...]` is a
  `Spite.Attribute`'s own value and counts for no attribute. A member of a shape a class fills is read. In a folder the
  program loads only singleton bindings are checked, counting reads from inside that folder.
- **Falls back**: an unread attribute is refused (`the attribute 'label' is never read: remove it`).
- **Lives in**: `validators/abstract_syntax_tree/unused_names`, and the proof `proofs/every_attribute_is_read`
  for attributes, which hands what it found, and whether its fix removed it, to
  `validators/high_intermediary_representation/read_attribute`.
- **Checked by**: conformance/unused_names, written_not_read, unused_attributes, attribute_read_in_another_class,
  loaded_singleton_unread, template_unused_attribute, template_unused_function,
  attribute_hidden_by_an_uncalled_read, attribute_hidden_by_an_uncalled_library_read,
  attribute_hidden_by_an_uncalled_call, attribute_hidden_by_a_library_template,
  attribute_hidden_by_a_program_template; tests/attribute_read_by_an_uncalled_function,
  attribute_read_by_an_uncalled_template.

### A constructed object must be kept and used

- **Status**: built.
- **Rule**: a construction written as a statement of its own is refused
  ([classes_and_files.md](../spite_documentation/classes_and_files.md#a-constructed-object-is-kept-and-used)).
- **Lives in**: `validators/abstract_syntax_tree/dropped_construction`.
- **Checked by**: conformance/dropped_construction.

### Singletons that make each other in a circle are an error

- **Status**: built (D1444).
- **Rule**: following every attribute of every singleton through the objects those attributes make, a path back to
  the start is refused ([classes_and_files.md](../spite_documentation/classes_and_files.md#singletons)). An
  attribute whose default constructs its class links to it: "binds" for a singleton, "makes" for an ordinary
  object. A circle is refused when a singleton is on it, told from the last singleton on it, at that singleton's
  attribute that starts the rest: "singleton 'Metronome' makes 'Tick', which binds 'Metronome': singletons initialise
  each other in a circle, ...". A circle of ordinary objects alone is not this rule.
- **Falls back**: a circle only a constructor's body closes, which this does not follow, halts at run time,
  "spite: singleton ...: singletons initialise each other in a circle".
- **Lives in**: `validators/name_resolution/singleton_circle`.
- **Checked by**: conformance/singleton_circle, conformance/singleton_circle_through_an_object;
  tests/singleton_circle.

### Build settings are constants

- **Status**: built.
- **Rule**: a flag's value has its field's type, an unknown flag is refused, and an `if` around a `load` is decided
  from Build fields and literals ([programs.md](../spite_documentation/programs.md#compile-time-settings-build)).
- **Lives in**: `validators/command_line/known_flag`, `validators/name_resolution/settings`,
  `validators/abstract_syntax_tree/load_statement`.
- **Checked by**: conformance/flag_value, load_unknown_condition, unknown_compiler_flag, bare_flag_not_boolean,
  flag_given_twice, setting_named_like_flag, program_flag, check_and_build_flags, underscore_flag, format_flag.

### A value fits a `type`

- **Status**: partly built.
- **Rule**: a value fits a `type`, and a `$T` its constraint, on its attributes, its functions, their types and
  not-null ([values_and_types.md](../spite_documentation/values_and_types.md#inline-types-and-duck-typing)).
- **How**: a class passed as a `type` must have each attribute with the type's type, and each function with as many
  parameters, the same parameter types and the same answer (D1136), the type's own name meaning the type, any
  class that fits it, never only the class being checked (spite_compiler#545); while a class is judged against a
  `type`, the class counts as fitting it inside the members, so a missing member is what the refusal names. A member whose type is a union is filled by the same union or by one of its classes; one whose type is a
  `type` by the same `type`, or by a class or a union whose classes each have the `type`'s members; one whose type
  is a function value by a function value with the same parameter types and answer (D1255).
- **How, for a `$T`**: the class a `$T` is given is compared with its constraint the same way, each member's types
  as well as its name (D1398), and a `type` member's own members are compared by type too, a pair of class and
  `type` already being compared counting as fitting so a `type` that names itself ends. A `T?` is compared as its `T`,
  and null has to fill every member too: it answers `to_string()` and `to_debug()` with a `String` and nothing else
  (D754, D1934).
- **Missing**: nothing known.
- **Falls back**: refused, "'...' does not fit type '...': it has no function '...'", "... it has no attribute
  '...'", "... attribute 'size' is a String, but the type needs an Integer", "... its 'render' returns an Integer,
  but the type needs a String", "... argument 1 of its 'scaled' is a String, but the type needs an Integer", "... its
  'scaled' takes 2 argument(s), but the type needs 1".
- **Lives in**: embedded, `fitting.spite` (`filled_shape`, `fits_as_a_class`), `constraints.spite`.
- **Checked by**: conformance/shape_mismatch, shape_function_mismatch, shape_attribute_type_mismatch,
  shape_return_type_mismatch, shape_parameter_type_mismatch, generic_constraints, generic_constraint_nullable,
  generic_constraint_not_a_type, shape_operator_without_function, generic_constraint_mistyped,
  tests/nullable_meets_printable.

### A value written through a `type` fits the attribute

- **Status**: built (spite_compiler#414).
- **Rule**: an assignment through a `type`, `keeper.pet = other`, stores a value known only as the member's type
  into the attribute of whichever class the value really is, so it can never store what that attribute does not hold.
- **How**: a call handing a class to a function taking the `type` calls its copy for that class
  ([a function taking a union or a `type` is copied per argument type](#a-function-taking-a-union-or-a-type-is-copied-per-argument-type)),
  where the write is checked as written for the class. What is left is a value whose class is known only while
  running: once the program assigns a member through a `type`, every class that fits the `type` must hold the member's
  own type in that attribute (the member's type fits the attribute's, and an attribute that may hold nothing meets
  a member written with `?`), checked for the classes that already fit when the assignment is built and for each
  class that fits later. Reading alone keeps the wider rule of [a value fits a `type`](#a-value-fits-a-type): a `Cat`
  attribute meets a `pet: Named` member until the program writes `pet` through the `type`.
- **Missing**: nothing known.
- **Falls back**: refused, "'CatKeeper' does not fit type 'Keeper': this program assigns 'pet' through the type,
  which can store a Zoo.Named there, but attribute 'pet' is a Cat".
- **Lives in**: `fitting.spite` (`judge_the_assigned_members`), `validators/high_intermediary_representation/shape_fit`.
- **Checked by**: conformance/type_member_written_wider, tests/type_member_written_where_the_attribute_holds_the_type.

### A function taking a union or a `type` is copied per argument type

- **Status**: built (spite_compiler#496, #414, D2500).
- **Rule**: a call handing a class to a function of the program whose parameter is a `union`, a `type` or a generic
  holding one calls a copy whose parameter is that class, and the copy is checked as if written for it, so nothing
  tests the class while running and a body that does not fit the class is refused.
- **How**: `Arguments.fitted_or_kept` keeps an argument whose type is a class that fits the parameter
  (`TypedCopies.copied_type`: a member of the union, a class with the `type`'s members, the same generic with each
  bound type the same or such a class), and `TypedCopies.copy_for` makes the copy with those parameters retyped,
  which the builder builds from the same declaration. In the copy a class test on a value of one class is decided
  (`Operators.copied_class_test`) and a `switch` on such a parameter builds the case naming its class
  (`Switches.case_of_the_copied_class`); neither is a decided condition to fix, since the copy is walked. Copies whose
  lowered code is the same are folded by `identical_functions`, which compares that code. A parameter the body
  assigns or copies into an untyped local keeps its declared type (`TypedCopies.keeps_its_type`), `==` on a copied
  parameter compares it as its declared type (`TypedCopies.as_declared`), and the function as written is built
  first and dropped by `unreached_functions` when no call reaches it.
- **Missing**: a value whose class is known only while running reaches the function as written.
- **Falls back**: the copy's mistake with ", in its copy for (Link, Chain) that the call at line 10 in Zoo.Zoo makes".
- **Lives in**: `high_intermediary_representation/building/typed_copies.spite`, `arguments.spite`, `calls.spite`.
- **Checked by**: tests/type_parameter_copied_per_class, tests/union_parameter_copied_per_class,
  tests/list_of_a_class_where_anything_is_wanted, tests/type_member_written_in_a_copy_that_fits,
  conformance/list_copy_appends_what_does_not_fit, conformance/type_member_written_in_a_copy.

### A member template fits

- **Status**: built (D1441, D1443).
- **Rule**: the member a template names exists and has the right kind (a Boolean for `filter_`, a number for
  `sum_`), and a passed function takes the element
  ([collections.md](../spite_documentation/collections.md#member-templates-loops-you-do-not-write)).
- **How**: on a library collection, `sum_` needs a number, `count_` a Boolean, `each_` a function, `map_` a member
  that answers something, `sort_by_` a number or a text, and `filter_`, `any_` and `all_` a Boolean, each refused at
  the call with its own text (D1142).
- **Program collections**: the same checks hold for a member template of a program's own class that holds an
  `$element_type`; before, `bag.sum_name()` on a `String` member summed the texts onto "0" (D244). A program class
  with no `$element_type` names its templates as it likes, so its prefixes say nothing.
- **`each` given a value**: "'each' takes a function to call with each element, such as 'each(say_hello)' or
  'each(greeter.say_hello)', and 'engine' is not one".
- **Falls back**: refused with its own text.
- **Lives in**: embedded, `templates.spite` (`specialized_over_a_class`), judged by
  `validators/high_intermediary_representation/member_fit`, `plural_template` and `template_member`.
- **Checked by**: conformance/member_template_mistakes, member_template_map_nothing, member_template_sort_boolean,
  member_template_filter_text, member_template_any_number, own_member_template_mistakes, each_of_a_value,
  conformance/passed_functions.

### A value can be written

- **Status**: built.
- **Rule**: the `T` of a JSON or binary writer or reader holds no union, `type` or function value anywhere
  ([json.md](../spite_documentation/json.md)).
- **Lives in**: `constraints.spite` (`check_the_written_form`, judged by `validators/high_intermediary_representation/generic_constraint`), `validators/high_intermediary_representation/serializer`.
- **Checked by**: conformance/json_unwritable, binary_writer_union, binary_object_key.

### What crosses into C

- **Status**: built.
- **Rule**: numbers, Booleans, enums, text, lists of numbers, number-only `type`s and function values cross into C;
  a callback's parameters and context are checked
  ([foreign_libraries.md](../spite_documentation/foreign_libraries.md#what-crosses)).
- **Lives in**: `high_intermediary_representation/building/foreign_crossing.spite`.
- **Checked by**: conformance/foreign_call_mistakes, foreign_call_through_parameter, foreign_callback_mistakes,
  foreign_callback_context_literal, foreign_callback_named_directly, foreign_callback_needs_singleton,
  foreign_callback_text_parameter, foreign_callback_text_result, foreign_callback_thread_reach,
  foreign_list_of_text, foreign_type_with_text, foreign_size_of_shape, foreign_literal_arguments.

### The short form is proven the same, and the long form refused

- **Status**: built.
- **Rule**: a `while` a member template already says, a chain of `if`s that is a `switch`, the same call opening
  every branch, a switch that is a class test and a text that is one hole are refused, naming the short form
  ([control_flow.md](../spite_documentation/control_flow.md)).
- **Lives in**: `validators/high_intermediary_representation/template_walk` (called from `loops.spite`),
  `validators/abstract_syntax_tree/switch_chain`, `repeated_branch_call`, `switch_cases`, `lone_hole` (run by
  `proofs/rules_after_building`, reading whether the builder built each declared hole as text:
  `statements.spite`, `note_a_lone_hole`, so `'var shown = label'` is named for any text, an attribute or a call
  included).
- **Checked by**: conformance/walk_with_function, argument_walk_without_function, repeated_branch_call,
  repeated_branch_call_chain, switch_chain, switch_chain_else_if, switch_chain_or, lone_hole and its variants.

## Every loop in a proof settles with no round limit

A proof that repeats a step until a round changes nothing has no round limit (#495, #576): a limit that stops it
early leaves an answer that has not settled, which the proofs below then threw away. Each loop ends because what
it changes only goes one way over finitely many things.

- [Passes that write only what they alone reach](#passes-that-write-only-what-they-alone-reach)
  (`high_optimization_passes/banded_loops/owned/writes.spite`): where a name's value may come from (made here, the
  item, shared, owned) and what a pass stores in a class only gain kinds, over a function's names and the
  program's classes. Before, 16 rounds for what is stored and 8 for the names, past which the loop was refused
  ("did not settle").
- [A text is written only while nothing else holds it](#a-text-is-written-only-while-nothing-else-holds-it)
  (`high_optimization_passes/constant_texts/written_texts.spite`): what holds the text at a loop's head is the
  larger of itself and what the body leaves, so it only rises over three states (held by nothing, held alone,
  handed on) and settles in three rounds at most, which the old limit of 3 allowed.
- The registers never negative that [a signed test](#a-counted-loop-reads-its-items-unchecked) proves bounds with
  (`proofs/bounds_proven_by_signed_tests`), and those [the range of a register](#the-range-of-a-register) floors at
  0: a register only loses the mark. [The range of a register](#the-range-of-a-register) learns a register's
  bounds once and never forgets them, so a round that learns nothing ends (8 rounds before).
- The dominators of [a test a dominating test made](#a-test-a-dominating-test-already-made-is-answered)
  (`proofs/dominating_tests`): a block's dominator only moves up the tree towards the first block, as in the
  passes after lowering ([OPTIMIZATIONS.md](OPTIMIZATIONS.md#every-loop-after-lowering-settles-with-no-round-limit)).
  Before, past 64 rounds the proof answered nothing.
- [A signed test](#a-counted-loop-reads-its-items-unchecked) follows a register to the one it copies while both
  are written once, and walks up from a block to the one way into it; [the range of a register](#the-range-of-a-register)
  walks up the same way. Each stops at a register or a block it passed (copies in a ring, or blocks with one way in
  that come round, out of reach from the start), so it passes each once (8 steps before, #581).
- [Passes that write only what they alone reach](#passes-that-write-only-what-they-alone-reach) studies a function
  once per round for each context: where `this` and each argument come from, and the function values its parameters
  hold. Each answer is kept for the round, and a function already being studied in the same context answers
  shared, so a round ends: a program has finitely many functions, origins and function values. Before (#581) it
  gave up past 4 000 studies ("it reaches more than 4000 functions") and ran the loop in order.
- [A write to an object only this function holds](#a-write-to-an-object-only-this-function-holds-must-be-read)
  follows the item a function answers through the attribute it calls on, and stops at a function it asked already;
  whether every return of a function makes a new object asks the functions it returns from, and one asked again on
  the way answers no, so each walk passes a function once on its way. Before (#581), it stopped after four calls,
  so a fifth call's lost write was not refused (now conformance/memory_replaced_depth_5).

Measured (#581) the same way: walking up through blocks with one way in, the range of a register goes up to 508
blocks in the compiler (`Collections.watch_the_shared_lists`; 6 091 functions went past 8) and 596 in the spec
programs (`Color.named_hex`, 4 948 functions past 8), so 8 dropped facts from tests further up in thousands of
functions; the signed tests' copies and blocks never went past 8, and the banded loops' proof never studied 500
functions in one round, far under the old budget of 4 000.

Measured (#576) with every loop counted while building the compiler and the 3 027 spec programs: the registers
never negative of the signed tests need up to 58 rounds (`native_fault_stack`'s constructor, and 56 in
`ForeignSiteIsTheFaultingThreads`), where 32 dropped every mark and the proof answered nothing in those
functions; the ranges settle in at most 5 rounds, the dominators and the banded loops' proof in at most 4, and the
texts in at most 3, so the other limits never stopped a loop.

## Live reload

### A reload compiles only the changed classes

- **Status**: built in part: the proof finds what changed; the compile does not skip the rest yet.
- **Rule**: a reload compile (`--reload-at`) compares a digest of each of the program's files with the one the
  running program's manifest holds. No file changed, added or removed answers `unchanged` before anything is
  lowered; otherwise the classes the changed files declare are the reload's changed classes
  (`HighProgram.reload_changed_classes`), and a removed file counts as changed
  ([repl.md](https://github.com/Spite-Language/spite_documentation/blob/master/repl.md#how-it-works)).
- **What it buys**: a save that changed nothing answers at once, and the generator swaps in only the functions whose
  machine code changed (their digests, [HOT_RELOAD.md](HOT_RELOAD.md#the-parts)), so an unchanged class's functions
  keep the code the program runs.
- **When it does not apply**: the whole program is still compiled to find which functions changed: compiling only
  the changed classes against the manifest's facts is to build.
- **Lives in**: `proofs/reload_changed_classes`.
- **Checked by**: tests/hot_reload_swaps_a_function (a save that changed nothing answers `unchanged`), hot_reload_watches_saved_files.

### A reload reaches every object whose attributes it changes

- **Status**: built as a refusal: objects are not moved yet.
- **Rule**: after the last high pass, every class the running program's manifest describes is compared with the
  layout the reload compiled (its size, and each attribute's name, type and place). A class whose layout differs
  refuses the reload, naming the class and the attributes that are new or gone, since the objects the program holds
  would be read through attributes they do not have; an enum whose values change other than by new ones added last
  refuses it too, since a value the program holds keeps its number. Class ids are seeded from the manifest, so a
  class keeps the id its objects carry. Object literals of one layout in one function are told apart only by their
  place among each other (`Object_<layout>_<n>`), so a reload that changes how many a function writes is refused:
  the running objects of one would take the other's class.
- **What it buys**: no reloaded function ever reads a live object through a layout it was not made with: the reload
  is refused instead, and the program keeps all of its code.
- **When it does not apply**: a build without `--hot-reload` has no reload. Moving the objects to the new layout
  is to build.
- **Lives in**: `proofs/reload_reaches_moved_objects`, registered after `lent_attributes` through
  `HighOptimizationPasses.Proving`.
- **Checked by**: tests/hot_reload_refuses_new_attributes.
