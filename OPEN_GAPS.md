# OPEN_GAPS — unfinished work, open problems

Each item states where the system stands. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Score (2026-06-29): 71/71 EQUIVALENT, SOUNDNESS 0

> Build health: the full `lake build` is green from source again. A run of
> autoresearch "69/69" commits (19 Jun) had committed source that never compiled
> (a broken Gap-2 magic-div gate + a type-broken Gap-1 path-fact change in
> `Lift.lean`), because the harness scored a stale prebuilt binary. Reverted; the
> harness now builds-or-aborts before committing. See TOMBSTONES.md.
>
> Gaps 1 (guarded scalar division) and 2 (64-bit magic-constant division) are now
> CLOSED — `div_guarded` and `div_by_10` are in the training set and EQUIVALENT
> under the full oracle. See CHANGELOG.md. The gaps below are renumbered.

North star: point at a binary, get back compilable C you can read.

---

## Gaps

The emitter's faithful class is intentionally smaller than the unsafe emitter.
Every gap below describes a present refusal reason, the proof shape that makes
the refusal removable, and the oracle signal that marks the gap closed. The order
uses four signals: STRICT impact, dependency unblocking, soundness risk, then
effort.

> Closed: Gaps 1 (guarded scalar `div`/`idiv`) and 2 (64-bit magic-constant
> division) are done — see CHANGELOG.md. The wider division-heavy fixtures
> (`gcd`, `count_divisors`, `is_prime`, `lcm`, `pow_uint`) remain out of the
> training set because they carry *other* unmodeled instructions or loop shapes;
> the scalar-division and `imul r64; shr` idioms they need are now handled.

1. Chained branch-phi resolution. Impact: medium STRICT coverage and high gate
   soundness sensitivity. The current `simpleDiamondPhiExpr` resolves one branch
   diamond by proving which reaching definition comes from the taken arm and
   which comes from the fallthrough arm. `subOf` and the block-entry phi
   assignment call this helper once, so a value selected by one diamond can feed
   later straight-line code, and `russian_mul` is not an open blocker: its current
   object decompiles faithfully and the full-timeout oracle returns `EQUIVALENT`.
   The remaining gap is a true chain of merge values, where a later phi depends
   on an earlier resolved phi or where a nested diamond consumes a merge value in
   its predicate. This can be solved by chaining the search, but only as an
   acyclic, DAG-witnessed resolver: carry a visited `(use-index, register)` set
   or bounded fuel, recursively expand only `simpleDiamondPhiExpr` witnesses whose
   branch arms reconverge at the current block, and refuse cycles or any
   expression that still contains `_phi`. The closure signal is a nested-diamond
   fixture that emits no `_phi` locals in strict mode and returns `EQUIVALENT`; a
   broad transitive search without CFG witnesses is not sound enough for the
   faithful gate.

   The selected implementation is an expression resolver, not another SSA pass.
   Define a helper shaped like `resolvePhiExpr(q, r, fuel, seen)` that first asks
   `simpleDiamondPhiExpr` for the local diamond expression, then recursively
   substitutes any operand whose reaching name is itself a recorded phi at the
   same or dominating merge. The resolver composes ternaries only when each
   nested diamond has a concrete `(taken def, fallthrough def)` witness and both
   arms dominate the consumer. It stops at `fuel = 0`, at repeated `(q,r)` pairs,
   or at branch arms that do not reconverge at the claimed merge. The faithful
   gate then checks the resolved expression text for `_phi` before accepting.
   This design preserves the current safety property: unresolved control-flow
   joins stay explicit refusals instead of becoming guessed locals.

2. Loop oracle proof. Impact: formal assurance only, with no runtime STRICT
   change. `sumLoop_snd_double` and `sumLoop_inv_double` in
   `FlowrefDecompiler/IL.lean` have `sorry` stubs. The induction step for
   `sumLoop_snd_double` is the first blocker: after `simp only [sumLoop]` and
   `rw [ih]`, the goal contains the bilinear polynomial
   `k * (2*i + k - 1)` over `BitVec 32`. `bv_omega` is linear, and
   `bv_decide` abstracts the non-linear term too coarsely, so neither tactic is
   the right backend.

   The selected design is the Lean-native `grind` CommRing path, not the
   lambdaclass e-graph integration. The repo already runs Lean 4.30, so the
   smallest proof-maintenance path is to expose a Mathlib-compatible
   `CommRing (BitVec 32)` instance to `IL.lean`, import the ring-normalizer
   support, and replace the `sorry` in the successor branch with a local
   polynomial-normalization step (`grind` after the induction hypothesis). The
   lambdaclass e-graph remains useful prior art, but bringing in an optimizer
   stack just for one modular arithmetic identity adds more surface area than
   this proof needs.

   The implementation shape is narrow: first add a tiny scratch theorem that
   proves the post-`rw [ih]` polynomial identity over `BitVec 32` with `grind`,
   then use that theorem in `sumLoop_snd_double`, then specialize it at
   `(i, s) = (1, 0)` to discharge `sumLoop_inv_double`. The closure signal is
   `lake build FlowrefDecompiler.IL` with no `sorry` warnings for those two
   declarations and no change to the runtime oracle result; this remains a
   formal proof-track gap only because emitted C is already checked dynamically.

3. Constraint-based type propagation. Impact: dependency unblocking for future
   memory work, with no immediate STRICT change. Values used as pointer base
   addresses in `[reg+offset]` operands are not tagged as pointer types. All
   variables emit as `uint32_t`. The missing piece is a constraint pass that
   records pointer-like uses from memory operands and propagates them through
   copies, arithmetic with small offsets, and call/return boundaries without
   inventing types for pure integer arithmetic. This has no STRICT impact until
   memory fixtures enter the faithful class; the closure signal is readable
   pointer C with unchanged oracle results.

   The selected design is a conservative type-constraint pass that runs before
   declaration emission. Memory operands create `ptr(base)` and `index(index)`
   constraints; `lea` with small constants propagates pointer-plus-offset;
   arithmetic that mixes two pointer candidates clears the pointer tag unless a
   later memory use re-establishes it. The output type set stays intentionally
   small: `uint32_t` for scalar values, `uintptr_t` for address arithmetic, and
   `uint32_t *` only when a dereference width is known and aligned with the
   emitted load/store. The first accepted use should stay in unsafe/readability
   output until the memory faithful class exists, because type names alone do
   not prove memory semantics. The closure signal is a pointer-heavy unsafe
   fixture whose C becomes clearer without changing strict acceptance or oracle
   counts.

4. Variable coalescing. Impact: readability only. `eax_0`/`eax_1` SSA names are
   not collapsed into a single source-like local when live ranges do not overlap.
   Output is correct but verbose. The missing piece is a liveness-aware coalescer
   that runs after faithful SSA construction and before C rendering, preserving
   parameter names and refusing merges across live-overlapping values. This has no
   STRICT impact; the closure signal is readability-only diff coverage with the
   same `SOUNDNESS: 0` benchmark result.

   The selected design is post-SSA copy coalescing over emitted C names. Build
   live intervals from `defIdxByName`, `useIdxByName`, `retNameBase`, and phi-use
   consumers, then group names by canonical register and compatible C type.
   Parameters (`a0`, `a1`, ...) are fixed roots and cannot be renamed. A group is
   mergeable only when intervals are disjoint and neither member crosses a scope
   boundary that `inlineDef` relies on. The renderer can then print a single local
   name for the group while retaining the original SSA graph internally. The
   first fixture should assert cosmetic output only, for example a straight-line
   ALU chain that changes from `eax_0`, `eax_1`, `eax_2` to one readable local,
   while `flowref-equiv` and `algo-bench.sh` remain unchanged.

---

## Known latent caveats

- `sumLoop_snd_double` in `IL.lean` carries a `sorry` — the loop accumulator
  closed-form proof is incomplete (bilinear BitVec). Does not affect runtime
  soundness; oracle verifies dynamically.
- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is stopped. The Hermes cron fires every 5 min.