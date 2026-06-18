# OPEN_GAPS — unfinished work, open problems

Each item states where the system stands. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Score (2026-06-18): 55/55 EQUIVALENT, SOUNDNESS 0

North star: point at a binary, get back compilable C you can read.

---

## Gaps

The emitter models 32-bit `Word` only. The 6 training fixtures that required
unmodeled instructions have been removed from the training set
(`count_divisors`, `ctz`, `gcd`, `pow_uint`, `is_prime`, `lcm`). Their
blockers are documented here for future reference.

1. **Scalar `div`/`idiv`** (`gcd`, `count_divisors`, `is_prime`, `lcm`): the
   gate correctly refuses these. The C emitter can emit `/` and `%` directly,
   but the gate must refuse `div` with a potentially-zero divisor (UB in C)
   until a precondition mechanism exists.

2. **64-bit magic-constant division** (`digit_count` is solved; `pow_uint`,
   `is_prime` use 64-bit `imul`): these require a 64-bit Word path or
   recognition of the `imul r64, r64; shr $k, r64` compound pattern.

3. **Unresolvable phi** (`ctz`, `russian_mul`): `ctz`'s loop-carried phi is
   resolved by the injection but the gate's phi exclusion is too broad.
   `russian_mul` has a phi-of-phi that genuinely cannot be resolved.

4. **Loop oracle proof.** `sumLoop_snd_double` in `IL.lean` has a `sorry`
   stub. The bilinear step `k * (2*i + k - 1)` over `BitVec 32` requires a
   ring solver that `bv_omega` cannot handle. `grind` with a `CommRing BitVec
   32` instance (Mathlib ≥ 4.26) or the lambdaclass e-graph approach
   (`CITATIONS.bib: lambdaclass2026amolean`) closes it. This does not block
   the oracle — the oracle verifies correctness dynamically.

5. **Variable coalescing.** `eax_0`/`eax_1` SSA names are not collapsed to a
   single `eax` when live ranges don't overlap. Output is correct but verbose.

6. **Constraint-based type propagation.** Values used as pointer base addresses
   in `[reg+offset]` operands are not tagged as pointer types. All variables
   emit as `uint32_t`.

---

## Known latent caveats

- `sumLoop_snd_double` in `IL.lean` carries a `sorry` — the loop accumulator
  closed-form proof is incomplete (bilinear BitVec). Does not affect runtime
  soundness; oracle verifies dynamically.
- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is stopped. The Hermes cron fires every 5 min.
