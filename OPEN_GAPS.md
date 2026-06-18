# OPEN_GAPS — unfinished work, open problems (present tense)

Each item names the next decisive action when known. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Priorities (2026-06-18)

Current score: **46/61 EQUIVALENT, SOUNDNESS 0.**

### Immediate production coverage (highest impact on STRICT count)

1. **5-block guarded loop CFG fix.** Sum_to_n, factorial, popcount, ctz, log2_floor,
   fib_iter share a "guard + counted loop" shape. The emitter currently puts the
   early-exit block inside an if-body and emits a cross-scope `goto` back into it.

   A previous attempt (`isGuardedLoop5` gate) caused SOUNDNESS: 3 — see TOMBSTONES.md.

   **Correct approach (DAG-based, no hardcoded block indices):**
   - Detect the guard block as the condBlock (not the loop header) whose `condTgtBlk`
     jumps to earlyB, where earlyB has an `uncondTgtBlk` pointing to a ret block.
   - Use `&&` (Bool) not `∧` (Prop) throughout the gate; do not mix them into `faithful`.
   - Branch predicate direction: ZF-based branches (`je`/`jz`) → guard uses `!predOf`;
     comparison-based branches (`jbe`/`jae` etc.) → guard uses `predOf` directly.
   - Return value: use `latestDefIn` on the source register of B_merge's copy insn,
     traced from B_early's context — do not re-emit B_merge's stmts.
   - Verify with `FLOWREF_EQUIV_TIMEOUT=60` on each newly faithful function before
     committing. `russian_mul` must remain INCOMPARABLE (data16 nopw fails allModeled).

   **WIP in stash:** `git stash pop` — emitter fix is correct (manually tested),
   gate is structurally right but `guardedLoopFaithful : Bool` is being silently
   dropped when combined via `∨` into the Prop-based `faithful`. Fix: rewrite
   `faithful` as all-Bool with `||`, or wrap with `decide guardedLoopFaithful`.

   Unlocks ≥5 functions (sum_to_n, factorial, popcount, ctz, log2_floor).

2. **isqrt — prove via loop-invariant induction in IL.lean.**
   `isqrt` is in `simpleLoopFaithful` and the C is correct, but the dynamic oracle
   times out (65535 iterations for large inputs). Capping the oracle range is wrong
   (see TOMBSTONES.md). Correct path:
   1. Define `isqrtIter : Nat → Word → Word` as a recursive fold (like `addLoop`).
   2. State invariant: after k iterations the accumulator = ⌊√input⌋.
   3. Prove by `induction k` + `bv_omega` per step.
   4. Connect to `SProg.eval` via `fromSoundSProg`.
   **Next decisive action:** add `isqrtIter` + `isqrtIter_correct` to `IL.lean`.
   Do not touch `EquivCheck.lean`.

3. **Variable coalescing.** Collapse non-overlapping live ranges of the same physical
   register into a single C variable (`eax_0`/`eax_1` → `eax`). Purely aesthetic,
   does not affect correctness or STRICT count. Do after Track A loop fixes.
   **Next decisive action:** live-range analysis over SSA def/use graph, then rename
   in the emit pass.

4. **Constraint-based type propagation.** Tag SSA values as struct pointers when used
   as base addresses in `[reg+offset]` memory operands. Do after Track A + B.

### Ongoing proof work (parallel track)

6. **Finish general SIMT program-level embedding.**
   `FlowrefDecompiler/IL/SIMT.lean` — arbitrary single binds, stores, and calls have
   one-step bridge theorems. Next: compose into statement-list simulation, then prove
   `fromSoundSProg` preserves `SProg.eval`.

7. **Provably-bounded unrolling for small fixed-count loops** — after the guarded-loop
   fix lands (item 1).

8. **`slangcheck`** — `whileLoopShader` emits 168 bytes because the loop body is
   dead-code-eliminated. Give it a side-effecting body.

## Known latent caveats

- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is currently stopped. Hermes cron fires every 5 min.
  Monitor: `journalctl --user -fu flowref-autoresearch.service` / `git log --oneline -10`
