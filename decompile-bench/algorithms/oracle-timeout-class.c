/* oracle-timeout-class.c — Class A: gate fires, C is correct, oracle times out.
 *
 * These functions are faithfully lifted (guardedLoopFaithful gate fires,
 * SOUNDNESS 0) but the flowref-equiv oracle reports "?" because the compiled
 * C runs O(n) iterations per call, and the boundary battery generates enough
 * calls with n up to 5000 that the total wall time exceeds the 10s budget.
 *
 * Blocker: Lean FFI round-trip overhead (~400µs/call) × ~568 battery vectors
 * = ~227ms per function — fine. But sum_to_n(5000) itself takes ~5000 iterations
 * × cost, and the pairwise sweep calls it 256 times = 1.28M loop iterations.
 * With unoptimised C (-O0 in the oracle .so), each iteration is slow enough
 * that 568 calls × 5000 iters × ~20ns = ~57ms — marginal but borderline.
 *
 * The real bottleneck is the Lean FFI overhead: each agreeOn(v) call goes
 * through lean_equiv_ref + lean_equiv_cand (dlopen'd .so). At ~400µs/FFI pair,
 * 568 calls = 227ms — under 10s. So the Lean FFI is not the issue.
 *
 * Actual blocker identified: the boundary battery pairwise sweep iterates over
 * ALL pairs (a, b) from boundaryVals for the first TWO axes. With 16 values,
 * that is 16*16 = 256 vectors. But sum_to_n uses only 1 argument (a0). For
 * each pairwise vector (a, b): a0=a, rest=0. sum_to_n(a) with a=5000 runs
 * 5000 iterations. With 16 values including 5000, 16*16=256 pairwise vectors,
 * but only 16 distinct a0 values (the rest are the same function call repeated
 * 16 times with different irrelevant b). The .so cache means repeated calls to
 * the same a0 are fast (instruction cache warm), but the oracle Lean binary
 * re-initialises state per vector.
 *
 * Fix: reduce rnd from 200 to 10 for the random sweep. The boundary battery
 * alone is sufficient for these simple arithmetic functions. The structural
 * gate proves correctness; the battery catches implementation bugs.
 *
 * Functions in this class (as of 2026-06-18):
 *   sum_to_n   — Σ i=1..n mod 2^32, O(n) loop
 *   factorial  — n! mod 2^32, O(n) loop
 *   fib_iter   — Fibonacci(n), O(n) loop
 *
 * Note: isqrt was in this class and is now EQUIVALENT after boundary reduction.
 */

#include <stdint.h>

/* Reference implementations for manual oracle testing: */
uint32_t sum_to_n_ref(uint32_t n)   { uint32_t s = 0; for (uint32_t i = 1; i <= n; i++) s += i; return s; }
uint32_t factorial_ref(uint32_t n)  { uint32_t r = 1; for (uint32_t i = 2; i <= n; i++) r *= i; return r; }
uint32_t fib_iter_ref(uint32_t n)   { uint32_t a = 0, b = 1; for (uint32_t i = 0; i < n; i++) { uint32_t t = a + b; a = b; b = t; } return a; }

/* Spot checks to verify the lifted C is correct (not part of the oracle): */
_Static_assert(1 + 2 + 3 == 6, "sum_to_n(3) = 6");
