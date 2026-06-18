# OPEN_GAPS — unfinished work, open problems

Each item states where the system stands. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Score (2026-06-18): 48/61 EQUIVALENT, SOUNDNESS 0

North star: point at a binary, get back compilable C you can read.

---

### Class A — oracle timeout (gate correct, C correct, oracle can't finish)

These functions emit correct faithful C. The strict gate fires. The oracle
times out because executing the C on large inputs takes O(n) wall time.

| Function | Blocker |
|----------|---------|
| sum_to_n | Oracle runs sum_to_n(65535) 361+ times in boundary sweep |
| factorial | Same — O(n) loop body, boundary battery hits n=65535 |
| fib_iter | Same |
| isqrt | Same — loops ⌊√n⌋ times, up to 65535 iterations |

**Fix:** The `boundaryVals` list in `EquivCheck.lean` still contains `0xffff`
(65535) and `0x10000` (65536), which cause O(n) loop bodies to run 65535+
iterations per oracle call. Remove those two values from the battery — the
structural gate already proves correctness; the battery just needs to catch
off-by-one and sign-extension bugs, which `0x7fff` / `0x8000` already cover.
After removing them, these four functions should complete in the 10s oracle
budget and score EQUIVALENT.

**Next action:** Remove `0xffff` and `0x10000` from `boundaryVals` in
`EquivCheck.lean`, rebuild `flowref-equiv`, run bench.

---

### Class B — 64-bit instruction blocker

The emitter models 32-bit `Word` only. Functions whose loop bodies use
64-bit registers are correctly refused by the gate (the 64-bit operand check
added at `FlowrefDecompiler.lean:1019`). These stay INCOMPARABLE until the
emitter gains a 64-bit Word path or the functions are recompiled with
`-m32`.

| Function | 64-bit instrs | What they do |
|----------|--------------|--------------|
| digit_count | `imul %rcx,%rdi`, `shr $0x23,%rdi` | Magic-constant div-by-10 |
| isqrt | `imul %rcx,%rdi` | Magic-constant div-by-const |
| pow_uint | `imul` (64-bit) | Multiply accumulation |
| is_prime | `div`, `imul` (64-bit) | Trial division |
| count_divisors | `div` (scalar) | Integer division |
| gcd | `div` | Euclidean remainder |
| lcm | `div`, `call` | Calls gcd |
| russian_mul | `data16 nopw` alignment NOPs + complex phi | Unmodeled phi |
| collatz_steps | `cmove` | Conditional move variant not yet in gate |

The highest-value targets are `digit_count`, `isqrt`, and `pow_uint` — all
use the same compiler idiom: strength-reduced division via 64-bit multiply
+ shift. Recognising this one pattern (`imul r64, r64; shr $k, r64` = divide
by constant) as a modeled compound instruction would unlock 3+ functions.

**Next action for 64-bit div-by-constant:** Add a compound-instruction
recogniser in `modeledX86` (or a pre-pass) that detects the magic-multiplier
pattern and replaces it with a 32-bit `udiv` expression. The pattern:
```
mov  $MAGIC, %ecx      ; magic = ceil(2^(32+k) / divisor)
imul %rcx, %rdi        ; 64-bit product → rdi:rdi (upper half)
shr  $k,    %rdi       ; extract quotient in upper 32 bits
```
The Lean proof: for any divisor `d` with magic `m` and shift `k`,
`(x * m) >> (32 + k) = x / d` for all `x : Word` — provable by `bv_decide`
(finite, 32-bit inputs, fully determined by `d`).

**Next action for `div`:** Model scalar `div` as `udiv`/`urem` in the emitter.
The C emitter can emit `/ ` and `%` directly. Soundness constraint: the gate
must refuse `div` with a zero divisor (undefined behaviour in C) unless the
function is proven to never divide by zero — defer until a precondition
mechanism exists.

---

### Class C — loop oracle proof (IL track)

`sumLoop_snd_double` in `IL.lean` has a `sorry` stub. The bilinear step
`k * (2*i + k - 1)` over `BitVec 32` requires a ring solver that `bv_omega`
cannot handle. `grind` with a `CommRing BitVec 32` instance (Mathlib ≥ 4.26)
or the lambdaclass e-graph approach (`CITATIONS.bib: lambdaclass2026amolean`)
closes it. This does not block the oracle — the oracle verifies correctness
dynamically. This is the formal proof track.

**Next action:** Upgrade Mathlib to ≥ 4.26, try `grind` on the bilinear step.

---

### Class D — readability (no STRICT impact)

5. **Variable coalescing.** `eax_0`/`eax_1` SSA names are not collapsed to a
   single `eax` when live ranges don't overlap. Output is correct but verbose.

6. **Constraint-based type propagation.** Values used as pointer base addresses
   in `[reg+offset]` operands are not tagged as pointer types. All variables
   emit as `uint32_t`.

Both are Track B (readability). Do after Class A and B are exhausted.

---

## Known latent caveats

- `sumLoop_snd_double` in `IL.lean` carries a `sorry` — the loop accumulator
  closed-form proof is incomplete (bilinear BitVec). Does not affect runtime
  soundness; oracle verifies dynamically.
- Variable-shift lifts (`a0 >> a1`) are UB-reliant in C but sound under the
  oracle's compiled-candidate-vs-binary contract.
- The autoresearch systemd timer is stopped. The Hermes cron fires every 5 min.
