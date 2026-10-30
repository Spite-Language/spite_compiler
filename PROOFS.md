# Proofs

A **proof** is a fact the compiler establishes while compiling: that a `T?` holds a value here, that an index is in
range, that an object never leaves its function, that no other thread reaches a singleton. With the fact in hand
the compiler **accepts** code it would otherwise refuse, **drops** a check it would otherwise emit, **chooses
cheaper code**, or **refuses** code that would go wrong (D276). A proof emits nothing of its own: what it costs is
the check it leaves in place when it does not hold, and a proof that does not hold never fails silently (D244):
the code is refused, saying what to write, or the run-time check stays.

The rules are the language's, in `../SpiteLanguage/specs`; this page says, for each proof, what this compiler does
with it. Each section has the same parts:

- **Status**: built, partly built (what is missing is its issue labelled `proof`), or
  missing.
- **Rule**: what is proven and how, with a link to the specification that states it in full.
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

Of the 92 proofs the old compiler made, 40 are built, 32 are partly built and 20 are missing (audit of
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
| `StatementSite` | `statements.spite` (`note_a_block`, `note_a_statement`), every block entered and left and every statement of the program's own code, before it is built | the statement list and index, the blocks around it, the line, and a `ScopeView`: every name in scope with its internal name, its narrowed type and its declared type | `proofs/lost_writes`, `proofs/borrowed_items` |
| `PresenceSite` | `values.spite` (`note_a_maybe_null`, `note_a_maybe_null_type`), `statements.spite` (`note_a_maybe_boolean`) | a value that may be null where a value is needed: its type, the value (for the list read it came from), what was wanted, the member or operator | `proofs/present_values` |
| `CheckSite` | `statements.spite` (`note_a_proven_check`, `note_a_proven_read_check`, `note_a_check_of_a_plain_value`, `note_a_narrowed_copy`) | the check written and what the scope says already proved it, the checked type, the copy and its source | `proofs/proven_checks` |
| `CheckSite` | `statements.spite` (`note_an_undone_loop_check`, `note_an_undone_path`) | a path assigned a value that may be null inside a loop: whether it was narrowed before the loop and read in it, or whether the end of the body left it narrowed | `proofs/loop_narrowings` |
| `GuardSite` | `statements.spite` (`default_return`, `note_a_terminal_if`) | a guard `fallback` with no "nothing" to answer, or an `if` that may be the last statement | `proofs/guard_asserts` |
| `ParallelSite` | `values.spite` (`handle_value`, `member_call`) | a `Parallel(...)`, the block around it and a `ScopeView` | `proofs/parallel_reach` |
| `SwitchSite`, `VectorSite` | `statements.spite`, `constraints.spite` | a switch's cases and members, a `Vector` made | `proofs/switch_cover`, `proofs/vector_fit` |

`building/function_entry.spite` puts a proof back inside the function of a site (its class, its function, its line,
and the member a member template binds), so a validator names the same place it named while building.

The builder also lists every site in the order it recorded them (`context.recorded_sites`), and the proof
`proofs/recorded_sites` walks that list, handing each site to the proof of its kind (a statement to `lost_writes`,
then to `borrowed_items`), so the first error is the one in the earliest code, whichever proof finds it. A refusal
the builder still makes itself first asks the same walk to judge what was recorded before it
(`Context.judge_what_is_recorded`, from `Typing.Validator.stop`; the proofs stage hands its walk to the high
representation stage before the build), and the rules of the syntax tree that need the built program run as the
proof `proofs/rules_after_building`, right after the walk. A program with several errors is told the same first one
as when each was refused while building.

## Presence and control flow

### Narrowing a `T?`

- **Status**: built.
- **Rule**: only a call-free name or path narrows; `if` narrows its block and not its `else`; `fallback` and `crash`
  narrow the rest of the block; `while` narrows its body; a `switch` `T:` case narrows its case; one check narrows
  every link of the path before it. It tests presence, never the value
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule),
  [control_flow.md](../SpiteLanguage/specs/control_flow.md#control-flow-in-full)).
- **Buys**: reads, calls and stores through a `T?` are accepted, and the narrowed read has no test.
- **Falls back**: refused, "this value may be null (it is a ...), so '...' cannot be read from it yet: narrow it
  first with 'if value { }', 'fallback value' or 'crash value'". Put a call's result in a `var` and narrow that.
- **Lives in**: the narrowing itself is building, since it decides the type of every read:
  `high_intermediary_representation/building/statements.spite` (`read_facts`, `read_a_fact`, `narrowed_block_of`),
  `scope.spite` (`narrow`), `values.spite` (`narrowed`, `with_its_links`). The refusal of a value that may be null
  where a value is needed is the proof `proofs/present_values`, which judges every `PresenceSite` the builder
  recorded (`values.spite`: `note_a_maybe_null`), a `Boolean?` condition among them.
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

- **Status**: built.
- **Rule**: after an `if` with no `else` whose block always leaves (a `return`, a bare `crash`, a `switch` whose
  every case leaves, an `if`/`else` that both leave), the opposite of its condition holds: each `or`
  side written `not path` narrows that path, each side read with the sides before it narrowed (`if not holder or
  not holder.weapon { return }` proves both), and other sides turned around prove `[]` reads and divisors
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule),
  [control_flow.md](../SpiteLanguage/specs/control_flow.md#switch-over-values)).
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
  it unnarrowed (a check later in the same pass keeps it)
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: nothing stale is read: a narrowed read has no run-time test.
- **Falls back**: refused, "assigning to '...' inside this loop undoes a narrowing made before the loop, and the
  next pass would read it unproven: narrow it inside the loop instead"; after the assignment, a read is refused
  until it is proven again.
- **Lives in**: forgetting is building, `statements.spite` (`assign_a_name`, `assign_an_attribute`,
  `forget_the_stored_items`), `scope.spite` (`forget`, `forget_below`, `forget_below_the_items`, `keep_present`); the
  refusals in a loop are the proof `proofs/loop_narrowings`, judging what `note_an_undone_loop_check` and
  `note_an_undone_path` recorded.
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
  `high_intermediary_representation/assignments.spite` read for narrowings (`read_for_narrowings`).
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

- **Status**: built (D1445 to D1447).
- **Rule**: a check of a `T?` already narrowed (by a `fallback`, a `crash`, the `if`, `while` or `switch` around
  it), a `[]` read already proven (by a bound, a count or an earlier check), a divisor already proven (`name != 0`
  after `name != 0` or `name > 0`, `name > 0` after `name > 0`), a class test the type already answers, the same
  call-free condition on the very next statement of the same block, a `fallback`/`crash` that folds true, and a check
  of a value that cannot be null are refused, naming where it was proven
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
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
  `note_one_check`) and `values.spite` (`note_an_answered_class_test`).
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
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: one name per value.
- **Falls back**: refused, "'watcher' only copies 'tracker' so it can be narrowed: narrow 'tracker' itself ('fallback
  tracker') and use it directly".
- **Lives in**: the proof `proofs/proven_checks`, judging each copy `statements.spite` recorded when the copy is
  narrowed (`note_a_copy`, `note_a_narrowed_copy`, `note_a_loop_copy`, `note_a_tested_copy`, `build_switch`).
- **Checked by**: conformance/copy_to_narrow, conformance/copy_to_narrow_conditions,
  conformance/copy_to_narrow_not_leaving; tests/narrowing_snapshot_copy.

### A value proven present is a `T`

- **Status**: partly built (D1719): the local, attribute and answer proofs are built; the answer of a call the
  compiler evaluates while compiling (spite_compiler#229, #230) is missing.
- **Rule**: a `T?` the compiler proves present is a `T` where it is read, with nothing written: a local every
  assignment of which in its function is present, an attribute of a program class whose default and every
  assignment anywhere in the built program are present, and a function of the program every `return` of which is
  present, at every call of it. A value is present when its type is not a `T?`, when it is a read of a proven local
  or attribute or a call of a proven function, or a `T` made a `T?` to fit; a read of the name itself (a copy
  assigning an attribute from the same attribute) and an `else` taken only when the name tested is null keep the
  proof. The proofs are run together until neither proves more, so a local holding a proven answer, or an answer
  returning a proven attribute, is proven too
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
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
  ([repl.md](../SpiteLanguage/specs/repl.md)).
- **Buys**: a reload or a REPL assignment can never break a proof the running objects were built under. Those builds
  are for iteration time, not for the checks a proof drops.
- **Falls back**: the attribute keeps its narrowing: a check of it is written and is not the "already narrowed" error.
- **Lives in**: `proofs/present_assignments` (`is_an_eligible_attribute`), told by `proofs/proven_present`.
- **Checked by**: tests/proven_present_hot_reload, tests/proven_present_repl.

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
  case ends, or a folded condition whose taken branch ends; a function that answers something and
  has a path that reaches its end is refused ([failure.md](../SpiteLanguage/specs/failure.md#fallback-is-control-flow)).
- **Buys**: no caller gets a value nobody wrote.
- **Falls back**: refused, "'...' answers ..., but ... it reaches its end without a 'return' ...: end that path with
  'return <value>', or with 'crash' if it cannot happen".
- **Lives in**: `high_intermediary_representation/building/endings.spite` (`check`, `always_leaves`), its own class,
  run by the builder on each function body.
- **Checked by**: conformance/falling_end; tests/every_path_returns, tests/control_while_running.

### A fallback answers what its answer type builds with no arguments

- **Status**: built.
- **Rule**: a `fallback` whose condition fails returns what the function's answer type builds with no arguments
  (D1765): nothing, `null` for a `T?`, `0` for a number, `false`, `""`, an empty collection, or the object of a class
  with no constructor or a constructor without parameters. It is refused where the answer type has no such value (an
  enum, a class whose constructor takes arguments, a singleton) and in a constructor; an `if` that only returns that
  value, or a last `if` with no `else` that only checks presence, is refused naming the `fallback`
  ([failure.md](../SpiteLanguage/specs/failure.md#fallback-is-control-flow)).
- **Buys**: a guard written once, whose answer the answer type states.
- **Falls back**: refused, "'fallback' returns what the answer type builds with no arguments, and a ... has none ...".
- **Lives in**: `statements.spite` (`default_return`, `is_built_with_no_arguments`), the proof `proofs/guard_asserts`,
  judging every `fallback` whose answer type has no such value and every `if` the builder recorded
  (`note_a_terminal_if`), and `validators/abstract_syntax_tree/default_guard`.
- **Checked by**: tests/fallback_answers, conformance/default_answer_enum,
  conformance/fallback_built_with_arguments, conformance/default_guard, conformance/returning_guard,
  conformance/empty_collection_guard, conformance/terminal_if, conformance/assert_in_constructor,
  conformance/constructor_guard, conformance/guard_de_morgan, conformance/guard_inside_loop,
  conformance/assert_is_fallback.

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
  `fallback`, `crash`, `if`, `while`, the right of an `and`, and after an `if` that leaves
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a proven read answers `T`, not `T?`.
- **Bounds written with `<=`**: `crash p + k <= list.count()` (in a `fallback`, a `crash` or an `if`), and the `if
  p + k > list.count()` that leaves, prove `list[p]` to `list[p + k - 1]`, as `p + (k - 1) < list.count()` would.
- **In a `while`** (D1448): a `<=` bound and the count facts prove the reads of its body as they do after a `crash`:
  `while at + 3 <= values.count()` proves `values[at]` to `values[at + 2]`, `while queue.count() > 1` proves
  `queue[0]` and `queue[1]`.
- **Missing**: undoing a proof inside the loop that read it is not refused, and a shrinking call inside an
  assignment or an argument does not undo it (each read still halts when its list changed, see the next section).
- **Falls back**: an unproven read is a `T?`; where a `T` is needed it is refused, "'...' may be missing, since every
  '[ ]' answers a 'T?' ...: ..., or prove the count first, 'crash list.count() > 2'".
- **Lives in**: the proving is building, since it decides whether a read is a `T`: `statements.spite`
  (`read_a_bound`, `read_a_counted_list`, `read_a_counted_member`, `read_a_turned_bound`, `whole_index_of`,
  `note_a_counted_list`, `forget_after_a_shrinking_call`), `values.spite` (`index_value`, `proven_by_its_path`); the
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
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
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
  literal ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
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
  `column` forgets the read ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
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
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: a slice of a list is read with one guard.
- **Falls back**: the read is a `T?` and is narrowed. The guard proves only the top: a negative base or counter
  halts at the read, as every proven read does ("... is outside its list ...").
- **Lives in**: `high_intermediary_representation/building/windows.spite`, called by `statements.spite` from the
  leaving `if`, the `fallback`, the `crash` and the loop condition.
- **Checked by**: tests/list_base_counter.

### A counted loop reads its items unchecked

- **Status**: partly built (done differently).
- **Rule**: inside `while index < values.count()` with the counter stepped last, the count is read once and the
  items with no test; a second list indexed by the counter is tested once before the loop
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)). A window read
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
- **Rule**: a comparison made in its branch's own block, of two registers each written once (or parameters) whose
  writes dominate an earlier branch on the same comparison of the same registers (or its opposite: `<` against
  `>=`, `==` against `!=`), is answered while compiling when the block one side of that earlier branch enters has no
  other way in and dominates the later branch. The answer is that side's.
- **Buys**: a second bound test of an index already tested (`crash values[at]` then `values[at]`) and any repeated
  test of the same values are not made; the branch becomes a jump.
- **Missing**: a register written twice (a loop's counter), a comparison made in another block than its branch, a
  decimal comparison, a function of more than 2000 blocks.
- **Falls back**: the test is made again.
- **Lives in**: the low proof `proofs/dominating_tests`, run in each cleaning after the signed-test proof, which
  adds its answers to the same record on each function; the pass `low_optimization_passes/proven_bounds` writes
  them (the comparison becomes its constant answer) and the folding and jump threading after it take the branch.
- **Checked by**: tests/dominated_tests.

### A proven divisor is not checked

- **Status**: built (by ranges, wider than the old rule).
- **Rule**: a divisor that is a non-zero constant, or whose range leaves out 0 (and -1 when the dividend may be the
  smallest value), is divided with no test ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#numeric-types)).
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
- **Missing**: a `Long` counter whose bound has no range keeps its check. Interactive builds prove ranges like
  every build: a range is about a function's own locals, which nothing typed at the REPL and no reload writes. The constant overflow error is made for `Integer` arithmetic only, as the old compiler made it: other
  widths are folded in their own type and checked where they are narrowed.
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
- **Missing**: loop locals other than counters; types wider than 4 bytes only where a value gives a range.
  `absolute` bounds its answer by its receiver's range, and a counter only stepped down by constants under `>` or
  `>=` keeps a floor and counts its passes like one stepped up (D1515).
- **Falls back**: the check stays and is listed by `--optimization-report`.
- **Lives in**: the proof `proofs/ranges`, a speed proof run after the acceptance proofs, over every function built from
  the source; it records its fact on each operation (`proves_no_ranges`, the unchecked arithmetic) for the lowering.
- **Checked by**: tests/proven_ranges, tests/optimization_report, tests/counter_room, tests/down_counter_ranges.

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
  (eight at most), each test of the register against another register's bounds (signed: `<`, `<=`, `>`, `>=`,
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
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md)).
- **Buys**: generic code compiles only the branch its class takes.
- **Missing**: `function_waits` and `function_writes_parameter` are answered after every function is built, so both
  branches are built and checked (D673); a codegen number compared with a literal folds only when one side is a
  call; a function taking a `type` has no copy per class. `x and $flag` and `x or $flag` fold whatever `x` is (in
  plain code a condition that folds is refused, D1746): one
  that only reads names, attributes and tests is left out (D1143), and one that calls something is run on its own,
  once, before the statement, and its answer dropped (D1513).
- **Falls back**: a run-time test of a constant, removed later by constant folding; both branches must compile.
- **Lives in**: the builder, `statements.spite` (`build_a_decided_if`), `values.spite` (`condition_of`,
  `folded_logic`, `decided_comparison`, `reflection_question`): deciding a condition is choosing what to build, and
  the branch not taken is never built, so nothing is left for a proof to judge (D1110).
- **Checked by**: tests/codegen_member_fold, tests/walked_class_fold, tests/private_walk, tests/codegen_short_circuit,
  tests/codegen_kind_tests, tests/codegen_class_test, tests/build_settings, tests/folded_helpers,
  tests/folded_functions, tests/folded_argument_count, tests/decided_and_false, tests/decided_and_false_after_a_call.

### Whether a function waits

- **Status**: built (D1134, D1253).
- **Rule**: waiting spreads from `sleep`, console, file and socket reads and joins, through calls, function values
  (to every function taken as a value with the same signature) and `type` dispatch, to a fixed point; letting go of
  a `Concurrent` waits; where it cannot tell, the answer is true
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks),
  [concurrency.md](../SpiteLanguage/specs/concurrency.md)).
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
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks)).
- **Buys**: generic code chooses its call by the count.
- **Falls back**: refused, "'...' has no function named '...', so 'argument_count' has nothing to count ...", or
  "... has no one answer: the functions of 'Painter' that fit it take different numbers of arguments ('update_each'
  1, 'render_each' 2), so ask 'phase.argument_count()' in a template over them, where each is walked on its own";
  asked of a walk that is not over functions, "'argument.argument_count()' is how many arguments the function a walk
  over functions stands for takes, so it is asked with no name in a template over functions, such as
  'run_phase_each(phase: Spite.FunctionDeclaration)'".
- **Lives in**: embedded, `values.spite` (`counted_arguments`, `refuse_disagreeing_counts`,
  `pattern_argument_count`).
- **Checked by**: tests/folded_argument_count, tests/system_phases, tests/streamed_rows; conformance/argument_count,
  conformance/argument_count_missing, conformance/passed_argument_count, conformance/argument_count_disagrees,
  conformance/argument_count_outside_walk.

### Whether a class fits a `Vector`

- **Status**: partly built.
- **Rule**: every attribute is a number, a Boolean, a text, an enum, a symbol, a singleton or a `T?` of those; no
  `drop()`; no function uses `this` as a value; not a generic template. `fits_vector()`, `is_fixed_size` and
  `any_attribute_fits_vector` fold, and an `Items<T>` stores its items inline exactly when a `Vector<T>` could be
  made ([collections.md](../SpiteLanguage/specs/collections.md)).
- **Buys**: items inline, lent rather than counted.
- **Generic templates**: every generic class is made once per set of type arguments before anything asks, so no
  `fits_vector()` is ever asked of an unbound template and the old compiler's "not a generic template" test has
  nothing to refuse here.
- **Missing**: the borrow study (`borrows.spite`) keeps its own copy of the answer, which
  does not test `this` yet, so it may refuse a borrow of an `Items` item that is held by reference.
- **Falls back**: refused for a `Vector<T>`, "'...' uses 'this' as a value, and an item of a Vector is borrowed ...";
  an `Items<T>` holds such items by reference.
- **Lives in**: the proof `proofs/vector_fit` refuses a `Vector` of a class that does not fit, judging every
  `Vector` the builder recorded making (`context.vector_sites`); the test itself, `constraints.spite`
  (`fits_a_vector`, with `uses_this_as_a_value`, and `is_kept_inline` for each attribute, which the proof asks
  too, so its refusal and the answer an `Items<T>` folds never disagree), is still asked while building by `values.spite`, `borrows.spite`
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

- **Status**: partly built.
- **Rule**: `$T.is_stateful` folds to "some function other than the constructor and `drop()` writes its own object
  or a singleton, or a singleton it binds keeps state"; where it cannot tell (a function it cannot build, such as a
  member template or one taking a `Spite.*` parameter), true
  ([metaprogramming.md](../SpiteLanguage/specs/metaprogramming.md#walks)).
- **Buys**: generic code shares an object nothing changes.
- **How**: the study (`building/facts.spite`) gives every singleton a slot of its own (`s:<class>`), reached by
  naming the singleton, by an attribute or a local holding it, and through every call that writes one; a program
  class whose writers can all be built asks the proof whether one of them writes its object or any singleton
  (the fact `keeps_state`), with or without attributes of its own (D1135).
- **Missing**: it is a filled reflection value, not a folded constant, so an `if` on it builds both branches.
- **Falls back**: true when a bound singleton has attributes, when a function of a program class cannot be built,
  and for a library class with attributes.
- **Lives in**: the proof `proofs/compile_time_facts` answers the fact; `reflection.spite` (`fill_the_state`,
  `every_writer_can_be_built`, `writes_its_object`) asks it.
- **Checked by**: tests/class_walk, tests/run_time_kinds, tests/reflection_objects, tests/stateful_singleton_writes.

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

### A condition known while compiling is an error

- **Status**: built (D1746).
- **Rule**: outside a generic class and a walk, an `if` or `while` whose condition the builder decides while
  compiling, and a `fallback` that folds false, are refused: the condition is always true or always false, so writing
  it tells a reader nothing. A condition that reads a `Build` field is kept, since the field is set from the command
  line and choosing the branch is its purpose; the literal `while true` is refused like any other (a loop states
  the condition it runs under). A
  bare name is judged by the narrowing errors instead ("already narrowed", a plain value). A `fallback` or `crash`
  that folds true is "Proving what is proven is an error"; a `crash` that folds false is the next section
  ([failure.md](../SpiteLanguage/specs/failure.md#nothing-fails-silently-the-rule)).
- **Buys**: no dead branch in the source.
- **Falls back**: refused, "'if 2 > 1' is decided while compiling and is always true here, so it tells a reader
  nothing: remove the 'if' and keep the code it runs".
- **Lives in**: `statements.spite` (`note_a_decided_condition`, from `build_if`, `build_while` and `build_assert`),
  judged by `proofs/proven_checks`; `values.spite` counts each `Build` read it folds (`folded_build_read`).
- **Checked by**: conformance/decided_if_true, conformance/decided_if_false, conformance/decided_while,
  conformance/decided_assert_false; tests/decided_conditions_kept.

### A `crash` that folds false is a compile error

- **Status**: built.
- **Rule**: a `fallback` or a `crash` that asks only compile-time questions folds; a `crash` that folds false in a
  function the program reaches is refused, naming the instance and each side of an `and`; a `fallback` that folds
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

- **Status**: missing (no reload: the compiler refuses `--hot-reload`, so no build can swap stale code in).
- **Rule**: a `--hot-reload` build records every fact one class took from another; a reload replays them, compiles
  the changed classes, and falls back to a whole compile, saying why, when a fact differs
  ([repl.md](../SpiteLanguage/specs/repl.md)).
- **Lives in**: none (`HOT_RELOAD.md` is the design).
- **Checked by**: none.

### A reload reaches every object whose attributes it changes

- **Status**: missing (no reload: the compiler refuses `--hot-reload`, so no object can be left on an old layout).
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
  the fields it has. It runs once more right after the first cleaning, for an object stored only into one placed
  then. The pass `low_optimization_passes/object_placement` right after it only writes
  what was recorded.
- **Checked by**: tests/generic_vectors, tests/written_codegen_in_frame, tests/owned_objects (output only).

### Local and variadic lists in the frame

- **Status**: partly built (D991).
- **Rule**: a local list made by a literal or `List<T>()` and filled at its own level, then only read, lives in the
  frame; a variadic list its callee only reads lives in the caller's frame
  ([functions_and_operators.md](../SpiteLanguage/specs/functions_and_operators.md)).
- **Buys**: no allocation.
- **Missing**: variadic lists; lists of objects or texts; reads other than `count()` and `[]`; constant data.
- **Falls back**: a heap list.
- **Lives in**: the speed proof `proofs/lists_in_the_frame`, run on the high representation after the acceptance
  proofs, which records on the list's declaration (and on a name that only holds it) how many items it holds
  (`Declare.frame_items`); the lowering lays out what was recorded. A name declared twice in one function is never
  placed in the frame.
- **Checked by**: tests/frame_lists, tests/frame_lists_of_decimals, tests/variadic_answers_in_frame,
  tests/text_building (output only).

### A function value its callee only calls lives in the frame

- **Status**: partly built (only through inlining and known closures, D1043).
- **Rule**: a function value passed to a function whose every mention of it is a call lives in the caller's frame,
  uncounted ([functions_and_operators.md](../SpiteLanguage/specs/functions_and_operators.md)).
- **Missing**: the "only calls it" proof over the callee, so a callee not inlined gets a counted heap value.
- **Falls back**: a heap function value with a counted receiver.
- **Lives in**: indirectly, `compile_time_evaluation/partial_evaluation.spite` (an optimisation, which calls a
  known closure directly) and the low proof `proofs/objects_in_the_frame` (a closure object the inlined callee only
  calls never leaves the caller).
- **Checked by**: tests/function_value_in_frame, tests/held_value_functions, tests/function_values.

### A back reference read holds its object

- **Status**: built (D1251).
- **Rule**: a back reference (the attribute of a cycle the compiler picks to hold no count,
  [memory.md](../SpiteLanguage/specs/memory.md)) answers `null` once its object is freed, and a read of it holds its
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
  `function_lowering.spite` (`held_back`).
- **Checked by**: tests/back_reference_calls, tests/back_reference_gone, tests/parent_back_reference.

### A back reference is picked from how the program links its objects

- **Status**: partly built (D759, D1396).
- **Rule**: an attribute `a: T?` of a class `C` holds no count when one function both sets `c.a = t` and stores `c`
  into `t`'s attribute `f`, which holds a `C` ([memory.md](../SpiteLanguage/specs/memory.md)); never from the class
  graph alone, since taking an owning reference for a back one would free an object the program still holds.
- **How**: each function of the program is read for the stores it makes: `x.a = y`, `x.f.append(y)` (and
  `insert`, `prepend`, `add`, `set_at`), `x.f[k] = y`, and a constructor that keeps its argument in an attribute. A
  call of a program function whose name only one class declares adds that function's own stores, with `this` and
  its parameters replaced by the call's receiver and arguments, so `team.recruit(player)` beside `player.play_for(team)`
  links the two as `team.players.append(player)` beside `player.team = team` would (D1396). A function's own stores
  include those of the program functions it calls, found in three rounds over the program (each round expanding
  the calls by the summaries of the round before), so a link made three calls down counts (D1663). A link found in one
  function decides the attribute for the whole program.
- **Missing**: a link through a function named by two classes (the library's included: a `join` is `String.join`'s name too), a call more than three deep, two objects neither of which
  the function made linked directly (not through a collection), one attribute pointing both ways (`partner`), a
  cycle through a union or a `type`, and a back attribute that cannot be null: each keeps its counts and leaks,
  which `--debug-memory` names at exit.
- **Falls back**: counted; the cycle leaks until the program clears the `T?` field that closes it.
- **Lives in**: `model/back_references.spite`, asked by `ProgramModel.holds_no_count`.
- **Checked by**: tests/parent_back_reference, tests/back_reference_two_functions, tests/back_reference_calls,
  tests/back_reference_two_levels.

### A deep copy copies a graph with its shape

- **Status**: partly built (D724, D1252, D1397).
- **Rule**: a class whose attributes can reach itself, or reach a back reference, is copied through a table made
  for the call, so a cycle is copied once per object
  ([memory.md](../SpiteLanguage/specs/memory.md)).
- **How**: a class reaches another through an object attribute, a bound type, or a union attribute (each member of
  the union); a union attribute inside a table copy is copied through its member's `_deep_copy_in`, dispatched on
  the class it holds, with the same table. A class that reaches a `type` attribute is copied through a table
  whatever fills it, since the classes that fill a `type` are known only once the whole program is built (D1397),
  and the `type` value is copied through `_deep_copy_in` with the same table.
  A `List`, `Dictionary` or `Items` whose items reach such a class (or a union or a `type`) is copied through one
  table for all its items (`_deep_copy_through_a_table`, made when a `deep_copy()` of it is built), so items that
  hold each other stay one graph; one reached inside a table copy uses that table (its `_deep_copy_in`)
  (`tests/deep_copy_list_graph`). A collection whose items need no table copies them one by one and makes none.
- **Missing**: a `Vector` copies its items as values; the table finds a copy through a `Dictionary<Long, Long>`.
- **Falls back**: a class that reaches a `type` pays for a table even when no filler reaches it back.
- **Lives in**: embedded, `high_intermediary_representation/building/copying.spite` (`uses_a_table`, `holds_a_type`,
  `copy_in_call`).
- **Checked by**: conformance/deep_copy_graphs, tests/deep_copy_union_cycles, tests/deep_copy_type_cycles.

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

These proofs belong to the ownership analysis of the high representation. The analysis is
`high_intermediary_representation/building/borrows.spite`; the proof `proofs/borrowed_items` runs it over every
statement the builder recorded (a `StatementSite`, with the names in scope), and `proofs/lent_parameters` over the
bodies of the calls it lends to. The counts it saves are in the lowering.

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

- **Status**: partly built (D730, D1140, D1399).
- **Rule**: a borrowed name is not read after anything that may resize its collection, followed through calls; a
  resize anywhere in a loop ends the borrow for the loop
  ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)). Assigning the collection again,
  a local as well as an attribute, is a resize, and so is assigning an object that holds it at any depth, through
  the program's classes and the items of the library's collections (`world = World()` ends what was borrowed from
  `world.holder.velocities`), and so is a library call that removes items (`remove_at`, `remove_first`,
  `remove_last`, `remove_swapping`, `truncate`, `clear`, `remove`, `remove_where...`) from a collection whose items
  hold one (D1399).
- **How**: a function's effects found while another call of it is still being followed (a recursion) are kept only
  for that one question, not cached, so a later question follows it whole (D1399).
- **Missing**: a value of unknown type fans out to every function of the name (strict, not silent).
- **Falls back**: refused, "'...' is borrowed from '...', and '...' on line ... may move the items ...".
- **Checked by**: conformance/vector_borrow_call_grows, vector_borrow_loop, vector_borrow_removed, vector_borrow_local_assigned, vector_borrow_holder_assigned, vector_borrow_owner_assigned,
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

- **Status**: partly built.
- **Rule**: a `return` of an item read straight from a singleton's `Vector` or fitting `Items` lends it: every
  return is such an item or null, the caller borrows it, and it is called only by name
  ([memory.md](../SpiteLanguage/specs/memory.md#borrowed-items-of-a-vectort)). A borrowed item returned through a
  name (`var h = lookup.of(0); return h`) is refused like any borrowed item (D1139).
- **Missing**: the uncounted return; `is_fixed_size` and `functions[...]` folded in its conditions.
- **Falls back**: refused, "'...' lends its caller an item of '...' ...".
- **Checked by**: conformance/lent_escapes, lent_results, lent_function_type, lent_function_value,
  lent_result_name_reused, lent_result_other_value, lent_result_returned_further, lent_result_returned_through_a_name; tests/lent_results,
  narrowed_lends, folded_lends.

### An item lent to a call

- **Status**: partly built (D1400).
- **Rule**: a borrowed item passed to a program function called by name is lent for the call; the callee is
  compiled under the borrow rules, and the call may not resize the source. Where the compiler cannot follow the
  item (a function value, a function of a value typed by a `type` or known only while the program runs, a library
  function, a variadic position or a union parameter) it is not lent: the item stays counted, as every item of a
  `List` is, and nothing is refused (D1781 under D1758; before, each was an error, D1400, D1512).
- **How**: a lent parameter the callee passes on by name to a program function called by name is lent to that
  function too, for the call, and its body is judged the same way, through any depth of calls (D1141); passed on
  where it cannot be followed, it is not followed further.
- **Missing**: nothing borrows since `Vector` and `Items` left (D1707), so the rule waits for the compiler's own
  inline storage (#205, #274).
- **Falls back**: the item is counted.
- **Lives in**: the proof `proofs/borrowed_items` records each lent call in the context (`borrows.spite`,
  `check_the_lent_body`); the proof `proofs/lent_parameters`, after it, judges the callee's body.
- **Checked by**: tests/lent_items_passed_on, lent_to_calls, lent_arguments, ignored_lent_argument.

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
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_steady_attribute`), `high_intermediary_representation/assignments.spite`
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
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_borrowed_local`, `gather_the_sources`).
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
- **Lives in**: the lowering, `function_lowering.spite` (`write_back_of`, `is_a_write_back`,
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
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_borrowed_item`), `list_reads.spite` (`held_item`).
- **Checked by**: tests/held_items, tests/slot_write_backs.

### A list item read only to test it is not counted

- **Status**: partly built.
- **Rule**: a presence test of `list[index]` tests the slot in place.
- **Missing**: lists of nullable items, and a test of a path through the item.
- **Falls back**: a counted read and its release.
- **Lives in**: the lowering, `function_lowering.spite` (`lower_presence_test`), `list_reads.spite`.
- **Checked by**: tests/tested_items, tests/items_presence.

### An item used at once is not counted

- **Status**: partly built.
- **Rule**: a proven `list[index]` used once, as a receiver or passed to a call that cannot change the list, is
  read in its slot.
- **Missing**: indices and arguments that are not plain reads (or such item reads), and a call through a function
  value.
- **Falls back**: a counted read.
- **Lives in**: the lowering, `function_lowering.spite` (`is_a_held_receiver`, `is_a_held_item`,
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

## Threads and locks

The rules are in [concurrency.md](../SpiteLanguage/specs/concurrency.md) and, for the counts,
[memory.md](../SpiteLanguage/specs/memory.md#the-memory-model).

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
- **Checked by**: tests/overlapped_work, tests/overlapped_work_runs_at_once.

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
- **Checked by**: tests/band_passes.

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
- **Buys**: [plain counts](OPTIMIZATIONS.md#plain-counts-where-no-other-thread-counts-a-class) for every other
  class whose objects' class is known where they are counted.
- **Falls back**: an atomic count wherever the class is not known while compiling, or another thread may count it.
- **Lives in**: `proofs/no_thread_counts`, registered among the high passes right after `singleton_locks`, whose
  walk it reads; it records `HighProgram.thread_counted_classes`.
- **Checked by**: tests/plain_counts, tests/thread_counted_classes (output only).

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
  program asks a copied class which object it is; the copied classes have no `drop()`, no back reference and no
  cycle ([memory.md](https://github.com/Spite-Language/spite_spec/blob/master/specs/memory.md)).
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

### Which singletons a `Parallel` reaches

- **Status**: built.
- **Rule**: walk the calls from every function a `Parallel` or the pool can run, and from every function handed to C
  as a `ForeignCallback`, which C may call on a thread of its own (D1137); a reached singleton is made safe, an
  unreached one takes no lock. A reached function that reads or writes an attribute of a singleton of the program
  directly, from another class, reaches that singleton too (D1138).
- **Falls back**: locked.
- **Lives in**: `high_intermediary_representation/waits.spite`, recorded by the high pass `singleton_locks`.
- **Checked by**: tests/singleton_forms, tests/singleton_race, tests/unshared_locks, tests/singleton_lock_calls,
  tests/singleton_outside_writes, tests/foreign_callbacks.

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
  (`function_lowering.spite`, `reads_under_the_lock`). Not in the inspectable builds.
- **Checked by**: tests/singleton_forms, tests/singleton_lock_calls, tests/lone_atomic_counter,
  tests/steady_singleton_reads (output only).

### A function that touches no changing state takes no lock

- **Status**: partly built.
- **Rule**: a function that reads or writes no changing attribute, and calls nothing that does, runs unlocked; a
  call from a locked function to another of the same singleton goes to its unlocked body.
  A read of a number, `Boolean` or enum attribute of its own that nothing assigns after the singleton is made is no
  touch: it holds the same value for the rest of the program.
- **Missing**: a call between two locked functions takes the lock again.
- **Falls back**: the lock, taken again by its owner. A lock that would wait forever is still judged by the
  attributes a function names (`proofs/parallel_reach`), so a function naming an attribute nothing changes is
  refused there as before.
- **Lives in**: `high_intermediary_representation/waits.spite` (`touch_what_reads_a_changing_attribute`),
  `function_lowering.spite`.
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
- **Lives in**: `low_intermediary_representation/lowering/function_lowering.spite` (`locks_from_outside`), reading
  `waits.spite` (`is_a_locked_class`).
- **Checked by**: tests/singleton_outside_writes.

### A lock that would wait forever is an error

- **Status**: built.
- **Rule**: a locked function that waits for a `Parallel` whose work calls back into the same singleton, or a loop
  that never ends inside a locked function, is refused.
- **Falls back**: refused, "'...' waits for '...' while it holds ...'s lock ...: each would wait for the other
  forever ...". A handle passed or returned is not judged.
- **Lives in**: the proof `proofs/parallel_reach` (`thread_reach.spite`), judging every `ParallelSite`.
- **Checked by**: conformance/locked_wait, conformance/endless_locked_loop; tests/locked_waits,
  tests/locked_bare_return.

### A loop that can never end is an error

- **Status**: partly built.
- **Rule**: every `while true` is refused, since a loop states the condition it runs under (D1746, "A condition
  known while compiling is an error"); in `Parallel` work and in a locked singleton function an endless `while true`
  is refused with the reason that is worse there, when it is judged first. The work's functions are followed through every call whose class is known
  while compiling: a function of its own class, of `this`, of a parameter's or an attribute's class, of a path of
  attributes, of a local made by a constructor or answered by a call whose answer's class is known, and a
  constructor called by its class's name; a class of the library is not followed. A singleton reached that way is
  read for a lock held around an endless loop, and for a call back into a lock its caller holds.
  In `Parallel` work a loop is refused when the function holding it never waits, by the waits fact (a sleep, a
  blocking read or write, a join, through every call): a loop that calls only the console is refused while the site
  is judged, and one that calls anything else is refused once the whole program is built, when the waits are known.
- **Missing**: a call through a function value, a `type` or a union is not followed.
- **Missing**: a loop on a condition nothing in it changes (`while running` with no `running = false`) is not
  read as endless.
- **Falls back**: refused, "'while true' is decided while compiling and is always true here: ...".
- **Lives in**: `statements.spite` (`note_a_decided_condition`), the proof `proofs/parallel_reach`
  (`thread_reach.spite`: `refuse_endless_work`, which refuses a loop that only prints and records the others in the
  context, `context.endless_work`), and the proof `proofs/endless_parallel_work`, right after the recorded sites,
  which asks `HighIntermediaryRepresentation.Waits` whether each recorded function waits.
- **Checked by**: conformance/spinning_loop, conformance/endless_parallel_work, conformance/endless_parallel_work_calls;
  tests/parallel_loop_that_leaves.

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
  A write inside a branch of an `if` or a `switch` to a local an outer block made is judged the same way, when
  nothing after it in any block around it names the local and nothing from the declaration to the write (the
  conditions and the other branches included) can let the object go; a loop between them stops the search, since
  its next pass may read the write.
- **Falls back**: not refused where the always-new answer comes from another class.
- **Lives in**: the proof `proofs/lost_writes`, judging every assignment the builder recorded (a `StatementSite`).
- **Checked by**: conformance/lost_writes, conformance/lost_write_in_a_branch.

### A name read from a list, assigned and never read, is an error

- **Status**: built.
- **Rule**: a local read from a list item, then assigned as its last mention, is refused: the list still holds the
  old item ([memory.md](../SpiteLanguage/specs/memory.md#assigning-a-name-read-from-a-list-changes-only-the-name)).
- **Lives in**: the proof `proofs/lost_writes` (`check_a_replaced_item`).
- **Checked by**: conformance/replaced_items, conformance/memory_replaced_branch,
  conformance/memory_replaced_answered, conformance/memory_replaced_unwritten; tests/memory_replaced_allowed.

### What a `Parallel` may reach

- **Status**: partly built.
- **Rule**: a `Parallel` work reaches only its own value attributes, its locals and
  singletons; it writes a value attribute only of an object handed over to it, never of `this`, an attribute, a
  parameter or a local used again ([concurrency.md](../SpiteLanguage/specs/concurrency.md)).
- **Missing**: reach is followed only through calls of the work's own class.
- **Falls back**: refused, "'...' runs '...' on another thread, so it may reach only ...", or "'Parallel(kept.bump)'
  writes 'count' of this 'Counter' on another thread while this thread may write it too, so one write would be lost
  ...".
- **Lives in**: the proof `proofs/parallel_reach` (`work_reach.spite`), judging every `Parallel` the builder recorded
  (a `ParallelSite`).
- **Checked by**: conformance/parallel_function_reach, parallel_handover, parallel_shared_writes,
  parallel_shared_value_writes, parallel_held_value_writes, foreign_callback_thread_reach; tests/parallel_work,
  parallel_handover, parallel_receivers.

### Which calls suspend a `Concurrent`

- **Status**: built.
- **Rule**: a function given to a `Concurrent` that can wait, and every waiting function it calls, gets a resumable
  copy.
- **Falls back**: a wait the study does not see as such runs the event loop in place.
- **Lives in**: `high_intermediary_representation/waits.spite`, `lowering/machine_writing.spite`.
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
  ([style.md](../SpiteLanguage/specs/style.md#unused-is-an-error)). An attribute is read when a built function
  reads it, counted for the class that owns it (every `AttributeRead` of the high representation, whatever made
  it: the program's code, a template's walk, a writer of JSON or binary, `to_debug`), so another class's attribute
  of the same name never hides it. Code the builder does not build still counts from the syntax tree: a bare name
  as its own class's attribute, and `x.name` by name for every class; that is a function no call reaches, an
  attribute default of a class never made, and a whole function from which the builder folded a branch away (it
  records each one, `Context.folded_functions`). A member of a shape a class fills is read. In a folder the
  program loads only singleton bindings are checked, counting reads from inside that folder.
- **Falls back**: an unread attribute is refused (`the attribute 'label' is never read: remove it`).
- **Lives in**: `validators/abstract_syntax_tree/unused_names`, and the proof `proofs/every_attribute_is_read`
  for attributes.
- **Checked by**: conformance/unused_names, written_not_read, unused_attributes, attribute_read_in_another_class,
  loaded_singleton_unread, template_unused_attribute, template_unused_function.

### A constructed object must be kept and used

- **Status**: built.
- **Rule**: a construction written as a statement of its own is refused
  ([classes_and_files.md](../SpiteLanguage/specs/classes_and_files.md#a-constructed-object-must-be-kept-and-used)).
- **Lives in**: `validators/abstract_syntax_tree/dropped_construction`.
- **Checked by**: conformance/dropped_construction.

### Singletons that make each other in a circle are an error

- **Status**: built (D1444).
- **Rule**: following every attribute of every singleton through the objects those attributes make, a path back to
  the start is refused ([classes_and_files.md](../SpiteLanguage/specs/classes_and_files.md#singleton-rules)). An
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
  from Build fields and literals ([programs.md](../SpiteLanguage/specs/programs.md#build-settings-build)).
- **Lives in**: `validators/command_line/known_flag`, `validators/name_resolution/settings`,
  `validators/abstract_syntax_tree/load_statement`.
- **Checked by**: conformance/flag_value, load_unknown_condition, unknown_compiler_flag, bare_flag_not_boolean,
  flag_given_twice, setting_named_like_flag, program_flag, check_and_build_flags, underscore_flag, format_flag.

### A value fits a `type`

- **Status**: partly built.
- **Rule**: a value fits a `type`, and a `$T` its constraint, on its attributes, its functions, their types and
  not-null ([values_and_types.md](../SpiteLanguage/specs/values_and_types.md#inline-types-and-duck-typing-in-full)).
- **How**: a class passed as a `type` must have each attribute with the type's type, and each function with as many
  parameters, the same parameter types and the same answer, the type's own name standing for the class that fits
  (D1136). A member whose type is a union is filled by the same union or by one of its classes; one whose type is a
  `type` by the same `type`, or by a class or a union whose classes each have the `type`'s members; one whose type
  is a function value by a function value with the same parameter types and answer (D1255).
- **How, for a `$T`**: the class a `$T` is given is compared with its constraint the same way, each member's types
  as well as its name (D1398), and a `type` member's own members are compared by type too, a pair of class and
  `type` already being compared counting as fitting so a `type` that names itself ends.
- **Missing**: nothing known.
- **Falls back**: refused, "'...' does not fit type '...': it has no function '...'", "... it has no attribute
  '...'", "... attribute 'size' is a String, but the type needs an Integer", "... its 'render' returns an Integer,
  but the type needs a String", "... argument 1 of its 'scaled' is a String, but the type needs an Integer", "... its
  'scaled' takes 2 argument(s), but the type needs 1".
- **Lives in**: embedded, `values.spite` (`filled_shape`, `fits_as_a_class`), `constraints.spite`.
- **Checked by**: conformance/shape_mismatch, shape_function_mismatch, shape_attribute_type_mismatch,
  shape_return_type_mismatch, shape_parameter_type_mismatch, generic_constraints, generic_constraint_nullable,
  generic_constraint_not_a_type, shape_operator_without_function, generic_constraint_mistyped.

### A member template fits

- **Status**: built (D1441, D1443).
- **Rule**: the member a template names exists and has the right kind (a Boolean for `filter_`, a number for
  `sum_`), and a passed function takes the element
  ([collections.md](../SpiteLanguage/specs/collections.md#standard-library-metaprogramming)).
- **How**: on a library collection, `sum_` needs a number, `count_` a Boolean, `each_` a function, `map_` a member
  that answers something, `sort_by_` a number or a text, and `filter_`, `any_` and `all_` a Boolean, each refused at
  the call with its own text (D1142).
- **Program collections**: the same checks hold for a member template of a program's own class that holds an
  `$element_type`; before, `bag.sum_name()` on a `String` member summed the texts onto "0" (D244). A program class
  with no `$element_type` names its templates as it likes, so its prefixes say nothing.
- **`each` given a value**: "'each' takes a function to call with each element, such as 'each(say_hello)' or
  'each(greeter.say_hello)', and 'engine' is not one".
- **Falls back**: refused with its own text.
- **Lives in**: embedded, `values.spite` (`specialized_over_a_class`), `validators/high_intermediary_representation/typing`.
- **Checked by**: conformance/member_template_mistakes, member_template_map_nothing, member_template_sort_boolean,
  member_template_filter_text, member_template_any_number, own_member_template_mistakes, each_of_a_value,
  conformance/passed_functions.

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
  `validators/abstract_syntax_tree/switch_chain`, `repeated_branch_call`, `switch_cases`, `lone_hole` (run by
  `proofs/rules_after_building`, reading whether the builder built each declared hole as text:
  `statements.spite`, `note_a_lone_hole`, so `'var shown = label'` is named for any text, an attribute or a call
  included).
- **Checked by**: conformance/walk_with_function, argument_walk_without_function, repeated_branch_call,
  repeated_branch_call_chain, switch_chain, switch_chain_else_if, switch_chain_or, lone_hole and its variants.

## Live reload

### A reload compiles only the changed classes

- **Status**: built in part: the proof finds what changed; the compile does not skip the rest yet.
- **Rule**: a reload compile (`--reload-at`) compares a digest of each of the program's files with the one the
  running program's manifest holds. No file changed, added or removed answers `unchanged` before anything is
  lowered; otherwise the classes the changed files declare are the reload's changed classes
  (`HighProgram.reload_changed_classes`), and a removed file counts as changed
  ([repl.md](https://github.com/Spite-Language/spite_spec/blob/master/specs/repl.md#live-reload-in-detail)).
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
- **When it does not apply**: a build without `--hot-reload` has no reload. Moving the objects to the new layout,
  which the specification asks for, is to build.
- **Lives in**: `proofs/reload_reaches_moved_objects`, registered after `lent_attributes` through
  `HighOptimizationPasses.Proving`.
- **Checked by**: tests/hot_reload_refuses_new_attributes.
