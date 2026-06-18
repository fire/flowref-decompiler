# OPEN_GAPS — unfinished work, open problems (present tense)

Each item names the next decisive action when known. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Reranked priorities (2026-06-18)

The leaf/flag/select/forwarding-call class is saturated. Loop coverage is next.
The autoresearch loop is running every 5 minutes; priorities below drive it.

Current score: **46/61 EQUIVALENT, SOUNDNESS 0.**

### Immediate production coverage (highest impact on STRICT count)

1. **5-block loop CFG fix.** Sum_to_n, factorial, popcount, ctz, log2_floor, fib_iter
   share the same 5-block "check-init-loop-exit-early" shape:
   B0(entry check) → B1(init) → B2(loop ↔ B2) → B3(exit-mov) → B4(early-ret).
   The emitter puts B4 inside the if-block, then B4's `goto L3` jumps into the
   if-body (B3). Fix: detect this shape and emit as:
   ```c
   if (!test) return 0;
   init; do { body; } while (cond); return result;
   ```
   Unlocks ≥6 functions if C becomes correct and oracle passes.
   **Next decisive action:** add an `earlyExitLoopFaithful` gate + emitter rewrite
   for this specific 5-block shape.

2. **isqrt oracle timeout.** isqrt is already in `simpleLoopFaithful` and the C is
   correct (manually verified), but the oracle times out at 10s because the plausible
   search hits n≈4B → 65535 iterations. Fix: in `EquivCheck.lean`, add a smarter
   boundary battery that caps the search range to `sqrt(UINT_MAX)` for functions
   whose loop count is data-dependent and bounded by the square root of the input.
   Alternatively: use the plausible witness DAG's back-edge count to bound the input.
   **Next decisive action:** patch `EquivCheck.lean` to restrict the test range for
   loop functions, re-run oracle on isqrt expecting EQUIVALENT.

3. **Variable coalescing.** The emitter produces `eax_0`, `eax_1` SSA versioned names.
   For human-readable output, collapse non-overlapping live ranges of the same physical
   register into a single C variable (e.g. `eax_0`/`eax_1` both become `eax` when
   their live ranges don't overlap). This is the "human-readable" pass described by
   decompiler MVP analysis — it doesn't affect correctness but dramatically improves
   readability. **Next decisive action:** implement a live-range analysis over the SSA
   def/use graph, then rename vars in the emit pass.

4. **Graceful degradation for unmodeled instructions.** Currently strict mode refuses
   any function with an unmodeled instruction. MVP quality requires embedding a fallback
   inline hint (e.g. `/* unmodeled: <insn> */`) rather than refusing entirely, so
   coverage includes partial decompilations. **Next decisive action:** widen the
   faithful gate to also classify "partial" functions that have ≤N unmodeled instrs,
   emit the body with `/* unmodeled */` comments, and verify the oracle reports
   INCOMPARABLE (never NOT-EQUIVALENT) for them.

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
