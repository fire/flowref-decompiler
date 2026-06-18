# OPEN_GAPS — unfinished work, open problems

Each item states where the system stands. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Priorities (2026-06-18)

Score: **46/61 EQUIVALENT, SOUNDNESS 0.**

### Production coverage — STRICT count impact

1. **5-block guarded loop CFG fix.** (+5 STRICT) Sum_to_n, factorial, popcount, ctz,
   and log2_floor share a "guard + counted loop" shape. The emitter puts the early-exit
   block inside an if-body and emits a cross-scope `goto` back into it. The oracle
   refuses all five as INCOMPARABLE. Fib_iter has `data16 nopw` and stays INCOMPARABLE
   regardless.

   A prior attempt (`isGuardedLoop5` gate) produced SOUNDNESS: 3 — see TOMBSTONES.md.

   The correct detection uses the plausible witness DAG: the guard block is the
   condBlock (not the loop header) whose `condTgtBlk` leads to an earlyB that has an
   `uncondTgtBlk` pointing to a ret block. The gate expression is all-Bool (`&&`);
   mixing Bool `guardedLoopFaithful` into the Prop-based `faithful` via `∨` silently
   drops it — use `decide guardedLoopFaithful` or rewrite `faithful` with `||`.

   Branch predicate direction depends on mnemonic: ZF-based branches (`je`/`jz`) have
   branch-taken = `!predOf`; comparison-based branches (`jbe`/`jae` etc.) have
   branch-taken = `predOf`. The guard return value traces through `latestDefIn` on the
   source register of B_merge's copy instruction from B_early's context; re-emitting
   B_merge's statements produces the wrong SSA binding.

   Gate validation requires `FLOWREF_EQUIV_TIMEOUT=60` on each newly faithful function.
   `russian_mul` has `data16 nopw` and fails `allModeled`; it stays INCOMPARABLE.

   WIP lives in `git stash@{0}` ("WIP: guardedLoopFaithful gate + emitter fix").

2. **Provably-bounded unrolling for small fixed-count loops.** (+N STRICT, blocked on
   item 1) The infrastructure for loop-carried SSA and the guarded-loop emitter, once
   landed, enables a straight-line unroll gate for loops with a statically constant
   trip count. No implementation exists yet.

3. **isqrt oracle gap.** (+1 STRICT) `isqrt` is in `simpleLoopFaithful` and the
   emitted C is correct, but the dynamic oracle times out: `isqrt(UINT_MAX)` runs
   ~65535 iterations and the plausible search exhausts its budget before finding a
   witness.

   Capping the oracle range is wrong — see TOMBSTONES.md.

   The witness DAG holds all three ingredients for a machine-checked induction proof,
   consistent with the hard rule in CHANGELOG ("CFG recovery reuses the plausible
   witness DAG — do not write new dataflow/CFG analysis"):

   - **State vector:** `reachingDefsB` and loop-carried SSA injection already identify
     the exact registers that cross the back-edge. These are the inputs to the
     `isqrtIter` recursive fold.
   - **Step function:** the DAG isolates the basic blocks between the loop header and
     the back-edge. The emitter has enough structure to slice out the step function
     mechanically; `bv_omega` closes the per-step arithmetic.
   - **Termination bound:** `reachingDefsB` and `resolveReachingDef` carry a `fuel`
     parameter for Lean 4's totality checker. For `isqrt` the static bound is
     ⌊√UINT_MAX⌋ ≈ 65535; this is the induction limit in the Lean statement, not an
     oracle input cap.

   The only non-mechanical step is stating the invariant:
   `isqrtLoop k init = ⌊√(init² + k)⌋`. `induction k` + `bv_omega` closes it.

   One open question: `reachingDefsB`'s return type and `backEdges` may not expose
   enough to emit the step function without threading extra data out of CFG recovery.
   That needs inspection before the IL proof is written. The proof target is
   `isqrtIter` + `isqrtIter_correct` in `IL.lean`; `EquivCheck.lean` is not touched.

### Proof track — formal moat

4. **SIMT program-level embedding incomplete.** `FlowrefDecompiler/IL/SIMT.lean` has
   one-step bridge theorems for arbitrary single binds, stores, and calls. Statement-
   list simulation is not composed, and `fromSoundSProg` preserving `SProg.eval` is
   not proved.

### Readability — no STRICT impact

5. **Variable coalescing gap.** The emitter produces `eax_0`, `eax_1` SSA-versioned
   names. Non-overlapping live ranges of the same physical register are not collapsed,
   so output reads as compiler intermediate text rather than idiomatic C. A live-range
   analysis over the SSA def/use graph feeds a rename pass in the emitter.

6. **Constraint-based type propagation gap.** The emitter infers types from physical
   width only (`uint32_t`). A value used as a base address in `[reg+offset]` memory
   operands is not tagged as a pointer type. A data-flow pass propagating
   pointer-constraint facts through def/use chains is absent.

### Minor

7. **`slangcheck` whileLoopShader body is dead-code-eliminated.** The shader emits
   168 bytes because the loop body has no side effects. A side-effecting body is
   not yet written.

## Known latent caveats

- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is stopped. The Hermes cron fires every 5 minutes.
