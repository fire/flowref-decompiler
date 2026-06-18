# OPEN_GAPS — unfinished work, open problems

Each item states where the system stands. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Score (2026-06-18): 55/55 EQUIVALENT, SOUNDNESS 0

North star: point at a binary, get back compilable C you can read.

---

## Gaps

The emitter's faithful class is intentionally smaller than the unsafe emitter.
Every gap below describes a present refusal reason, the proof shape that makes
the refusal removable, and the oracle signal that marks the gap closed.

1. Scalar `div`/`idiv` with zero-divisor preconditions. `gcd`,
   `count_divisors`, `is_prime`, and `lcm` require scalar division. The C
   emitter can spell `/` and `%`, but the faithful gate must refuse `div` or
   `idiv` while the divisor can be zero because C division by zero is undefined.
   The missing piece is a precondition channel from branch facts into the
   instruction renderer, for example a proof that the reaching divisor is
   nonzero on every path to the division. The closure signal is a fixture whose
   guard dominates the division, emits C with an explicit nonzero fact, and
   returns `EQUIVALENT` under the full oracle.

2. 64-bit magic-constant division. `digit_count` is solved in the current
   32-bit faithful class, but `pow_uint` and `is_prime` use the compiler's
   64-bit reciprocal-multiply shape (`imul r64, r64; shr $k, r64`). The current
   `Word` model is 32-bit, so this compound idiom has no faithful semantic
   target. The missing piece is either a 64-bit `Word` lane for register pairs
   and widened arithmetic or a recognized reciprocal-division theorem that
   lowers the whole `imul`/`shr` slice as one proven expression. The closure
   signal is a fixture that contains the magic-constant idiom, decompiles
   strictly without an unsafe banner, and returns `EQUIVALENT`.

3. Chained branch-phi resolution. The current `simpleDiamondPhiExpr`
   resolves one branch diamond by proving which reaching definition comes from
   the taken arm and which comes from the fallthrough arm. `subOf` and the
   block-entry phi assignment call this helper once, so a value selected by one
   diamond can feed later straight-line code, and `russian_mul` is not an open
   blocker: its current object decompiles faithfully and the full-timeout oracle
   returns `EQUIVALENT`. The remaining gap is a true chain of merge values,
   where a later phi depends on an earlier resolved phi or where a nested
   diamond consumes a merge value in its predicate. This can be solved by
   chaining the search, but only as an acyclic, DAG-witnessed resolver: carry a
   visited `(use-index, register)` set or bounded fuel, recursively expand only
   `simpleDiamondPhiExpr` witnesses whose branch arms reconverge at the current
   block, and refuse cycles or any expression that still contains `_phi`. The
   closure signal is a nested-diamond fixture that emits no `_phi` locals in
   strict mode and returns `EQUIVALENT`; a broad transitive search without CFG
   witnesses is not sound enough for the faithful gate.

4. Loop oracle proof. `sumLoop_snd_double` in `IL.lean` has a `sorry`
   stub. The bilinear step `k * (2*i + k - 1)` over `BitVec 32` requires a
   ring solver that `bv_omega` cannot handle. `grind` with a `CommRing BitVec
   32` instance (Mathlib ≥ 4.26) or the lambdaclass e-graph approach
   (`CITATIONS.bib: lambdaclass2026amolean`) closes it. This gap lives on the
   formal proof track only; the runtime oracle still verifies emitted C
   dynamically.

5. Variable coalescing. `eax_0`/`eax_1` SSA names are not collapsed into a
   single source-like local when live ranges do not overlap. Output is correct
   but verbose. The missing piece is a liveness-aware coalescer that runs after
   faithful SSA construction and before C rendering, preserving parameter names
   and refusing merges across live-overlapping values. This has no STRICT impact;
   the closure signal is readability-only diff coverage with the same
   `SOUNDNESS: 0` benchmark result.

6. Constraint-based type propagation. Values used as pointer base addresses
   in `[reg+offset]` operands are not tagged as pointer types. All variables
   emit as `uint32_t`. The missing piece is a constraint pass that records
   pointer-like uses from memory operands and propagates them through copies,
   arithmetic with small offsets, and call/return boundaries without inventing
   types for pure integer arithmetic. This has no STRICT impact until memory
   fixtures enter the faithful class; the closure signal is readable pointer C
   with unchanged oracle results.

---

## Known latent caveats

- `sumLoop_snd_double` in `IL.lean` carries a `sorry` — the loop accumulator
  closed-form proof is incomplete (bilinear BitVec). Does not affect runtime
  soundness; oracle verifies dynamically.
- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is stopped. The Hermes cron fires every 5 min.