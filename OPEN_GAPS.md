# OPEN_GAPS — unfinished work, open problems (present tense)

Each item names the next decisive action when known. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Reranked priorities (2026-06-18)

The leaf/flag/select/forwarding-call class is saturated. Loop coverage is next.
The autoresearch loop is running every 5 minutes; priorities below drive it.

Current score: **46/61 EQUIVALENT, SOUNDNESS 0.**

### Immediate production coverage (highest impact on STRICT count)

1. **5-block guarded loop CFG fix.** Sum_to_n, factorial, popcount, ctz, log2_floor,
   fib_iter share a 5-block "guard + counted loop" shape. The emitter puts the
   early-exit block inside an if-body, then emits a cross-scope `goto` back into it.
   A previous attempt (`isGuardedLoop5` gate) caused SOUNDNESS: 3 because the gate
   also matched `russian_mul` and the 10s oracle timeout didn't catch it (see
   TOMBSTONES.md). **Correct approach:**
   - Detect the guard block via the plausible witness DAG: the condBlock (not the
     loop header) whose `condTgtBlk` jumps to a block that has `uncondTgtBlk` pointing
     to a ret block. Use `&&` (Bool) not `∧` (Prop) throughout.
   - Verify with full oracle timeout (`FLOWREF_EQUIV_TIMEOUT=60`) on each newly
     faithful function BEFORE claiming SOUNDNESS=0.
   - The emitter rewrite: emit guard inverted (early-exit inline, walking B_early +
     B_merge statements), then fall through to init + loop.
   Unlocks ≥6 functions if C is correct and oracle passes with full timeout.
   **Next decisive action:** reimplement the gate with the DAG-based detection, run
   full oracle on russian_mul/sum_to_n/fib_iter to confirm they are INCOMPARABLE
   (NOT the new class), then only then add sum_to_n/factorial/etc. to the gate.

2. **isqrt — prove via loop-invariant induction in IL.lean, not a capped oracle.**
   `isqrt` is already in `simpleLoopFaithful` and the C is manually verified correct,
   but the dynamic oracle times out: `isqrt(4294967295)` loops ~65535 iterations, and
   the plausible search cannot exhaust 2³² inputs in 10s (or even 60s). Capping the
   test range is **wrong** — it is probabilistic thinking that violates the
   faithful-or-refuse contract and exactly the class of bug that already bit us
   (see TOMBSTONES.md `isGuardedLoop5`: 10s timeouts masked SOUNDNESS: 3).

   **Why `bv_decide` cannot close this:** `bv_decide` bitblasts a *finite* term.
   For `times8` (fixed 3-iteration unrolled loop) it works. For `isqrt` the trip
   count is runtime-symbolic (`⌊√n⌋` iterations), so the term is not finite and
   `bv_decide` cannot blast it.

   **Correct path — loop-invariant induction (the `addLoop_correct` pattern):**
   `IL.lean` already proves the template: `addLoop_correct` uses `induction n with`
   + `bv_omega` for per-step arithmetic. For `isqrt`, the invariant is:
   `isqrtLoop k = ⌊√(k + init²)⌋` — i.e., after `k` iterations the accumulator
   equals the integer square root of the initial input. Steps:
   1. Define `isqrtIter : Nat → Word → Word` as a recursive fold (like `addLoop`).
   2. State the invariant as a Lean theorem on `isqrtIter`.
   3. Prove by `induction k` with `bv_omega` closing the per-step obligation.
   4. Connect the IL `SProg` evaluation to `isqrtIter` via `fromSoundSProg`.
   5. This yields a machine-checked theorem over all 2³² inputs — stronger than
      any dynamic oracle, and provably sound.

   **Next decisive action:** add `isqrtIter` + `isqrtIter_correct` to `IL.lean`,
   following the `addLoop_correct` pattern exactly. Do not touch `EquivCheck.lean`.

3. **Variable coalescing.** The emitter produces `eax_0`, `eax_1` SSA versioned names.
   For human-readable output, collapse non-overlapping live ranges of the same physical
   register into a single C variable (e.g. `eax_0`/`eax_1` both become `eax` when
   their live ranges don't overlap). This is the "human-readable" pass described by
   decompiler MVP analysis — it doesn't affect correctness but dramatically improves
   readability. **Next decisive action:** implement a live-range analysis over the SSA
   def/use graph, then rename vars in the emit pass.

4. ~~**Graceful degradation for unmodeled instructions.**~~ **VETOED.** Emitting
   partial bodies with `/* unmodeled: <insn> */` comments directly contradicts the
   faithful-or-refuse contract (rule I0 in CHANGELOG). A user reading decompiled C
   has no way to know which parts are correct and which are gaps — the result is
   plausible-looking but wrong output, which is strictly worse than a hard refusal.
   The correct path for coverage is to **model the instruction** (add it to the
   emitter and prove the gate), not to silently skip it. Moved to TOMBSTONES.md.

5. **Constraint-based type propagation.** The emitter infers types from physical width
   only (`uint32_t`). A proper MVP needs: if a value is used as a pointer base with
   multiple offsets, infer a struct pointer type. Requires a data-flow pass that
   propagates pointer-constraint facts through def/use chains.
   **Next decisive action:** add a type-annotation pass that tags SSA values with
   pointer hints when they appear as base addresses in `[reg+offset]` memory operands.

### Ongoing proof work (parallel track)

6. **Finish general SIMT program-level embedding.**
   `FlowrefDecompiler/IL/SIMT.lean` — arbitrary single binds, stores, and calls now
   have one-step bridge theorems. Next: compose into statement-list simulation, then
   prove `fromSoundSProg` preserves `SProg.eval`.

7. **Loops** — provably-bounded unrolling for small fixed-count loops is next after
   the 5-block CFG fix lands.

8. **`slangcheck`** — periodic health check in `/tmp/lean-slang`.

## MVP gap analysis (added 2026-06-18)

The engine has two distinct tracks:

**Track A — coverage (fixes STRICT count):** The 5-block loop CFG fix is the single
highest-leverage remaining structural change. It unlocks factorial, popcount, sum_to_n,
ctz, log2_floor, fib_iter in one shot. The approach is heuristic, not a full
interval-analysis pass: detect the specific 5-block "guarded loop" topological pattern
and emit a guard-first `if (n==0) return 0; do { ... } while (cond);` instead of the
cross-scope goto currently produced.

**Track B — readability (moves toward production quality):**
- Variable coalescing: rename `eax_0`/`eax_1` into a single `eax` when live ranges
  don't overlap. Purely aesthetic — doesn't affect correctness or STRICT count.
- Graceful degradation: emit `/* unmodeled: <insn> */` inline rather than refusing
  the whole function. Increases coverage on real binaries.
- Type propagation: tag SSA values as struct pointers when used as base addresses.

**Track C — formal advantage (unique to this decompiler):**
The IL (`FlowrefDecompiler/IL.lean`) uses `bv_decide` to bitblast the IL to SAT,
proving equivalence as a theorem rather than via testing. This is what no commercial
decompiler does. The SIMT core, loop-carried embedding proofs, and `CallEnv`
uninterpreted-summary approach are the formal verification moat.

Track A is required before Track B is worth doing — unreadable but correct output
is better than readable but wrong output.

## Honest coverage gap

46/61 = 75% on the self-authored training set.
Of the 15 INCOMPARABLE: 6 are 5-block loops (fixable), 1 is isqrt (oracle timeout),
the remaining 8 have `div`/`call`/multiple nested loops.

The emitter is alpha-stage mature:
- Structural control flow (if/while/do-while) from plausible witness DAG ✓
- SSA phi lowering ✓
- Loop-carried SSA assignment injection ✓
- Differential oracle pipeline ✓
- Parallel oracle sweep ✓

Remaining delta to production-quality faithful decompiler: variable coalescing,
constraint-based type propagation, graceful degradation for unmodeled instructions.

## Known latent caveats

- `whileLoopShader` in lean-slang `slangcheck` emits 168 bytes (trivial shader):
  the loop body is dead-code-eliminated. Give it a side-effecting body.
- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd loop fires every 5 min; the Hermes cron fires every 5 min.
  Both commit to main when SOUNDNESS=0. Monitor with:
    `journalctl --user -fu flowref-autoresearch.service`
    `git log --oneline -10`
