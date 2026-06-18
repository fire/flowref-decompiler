/* 64bit-class.c — Class B: 64-bit instruction blockers.
 *
 * The flowref emitter models Word = BitVec 32 only. Functions whose loop
 * bodies use 64-bit general-purpose registers (rax, rcx, rdi, ...) are
 * correctly refused by the guardedLoopFaithful gate (64-bit operand check
 * at FlowrefDecompiler.lean:1019).
 *
 * Sub-class B1: magic-multiplier division (highest value, same pattern)
 * -----------------------------------------------------------------------
 * The compiler strength-reduces integer division by a constant d into:
 *   mov  $MAGIC, %rcx          ; magic = ⌈2^(32+k) / d⌉
 *   imul %rcx, %rdi             ; 64-bit product (upper 32 bits = quotient)
 *   shr  $k,    %rdi            ; extract quotient
 *
 * This is a 64-bit multiply: both operands and the result are 64-bit.
 * The 32-bit Word IL cannot model the upper 32 bits of the product.
 *
 * Affected functions:
 *   digit_count  — div by 10  (magic 0xCCCCCCCD, shift 35)
 *   isqrt        — div by constant in Newton step
 *   pow_uint     — mul accumulation (uses imul in 64-bit form)
 *   is_prime     — trial division pattern
 *
 * Fix: add a compound-instruction recogniser for the magic-multiplier pattern.
 * Lean proof: ∀ x : Word, (x.toNat * MAGIC) >> (32 + k) = x.toNat / d
 * is decidable by bv_decide (all inputs are 32-bit, result fits uint32_t).
 * Pattern to match in the emitter:
 *   insn[q]   = imul r64_src, r64_dst   (with r64_dst = rdi typically)
 *   insn[q+1] = shr  $SHIFT, r64_dst
 * Emit as: `uint32_t <dst> = (uint32_t)((uint64_t)<src> * MAGIC >> SHIFT);`
 * Gate addition: allow this compound when MAGIC and SHIFT are immediate constants.
 *
 * Sub-class B2: general integer division (div instruction)
 * ---------------------------------------------------------
 * Functions: count_divisors, gcd, lcm, is_prime
 * The x86 `div` instruction is a 64-bit operation (rdx:rax / r32 → rax, rdx).
 * Faithfully emitting `div` as C `/` and `%` is correct for non-zero divisors.
 * Gate condition to add: the divisor register has no reaching def from 0.
 * This requires a simple non-zero analysis (beyond current scope).
 *
 * Sub-class B3: other
 * -------------------
 * russian_mul  — complex phi variables (eax_phi); phi check correctly excludes it.
 * collatz_steps — uses `cmove` (conditional-move-if-equal); not yet in gate.
 * lcm          — also has a `call` to gcd; call support absent.
 */

#include <stdint.h>

/* B1: magic-multiplier division — reference implementations */
uint32_t digit_count_ref(uint32_t x) { uint32_t n = 1; while (x >= 10u) { x /= 10u; n++; } return n; }
uint32_t isqrt_ref(uint32_t n)        { uint32_t r = 0; while ((r+1)*(r+1) <= n) r++; return r; }

/* B1: the compiled assembly pattern for digit_count:
 *   mov    $0xcccccccd, %ecx   ← magic for /10
 *   imul   %rcx, %rdi          ← 64-bit: rdi = x * magic (upper 32 = x/10)
 *   shr    $0x23, %rdi         ← shift by 35: rdi >>= 35 → quotient
 *   ...
 * Proof obligation: ∀ x : UInt32, (x.toNat * 0xCCCCCCCD) >>> 35 = x.toNat / 10
 * This is a bv_decide-sized claim (32-bit input → decidable).
 */

/* B2: scalar div — reference */
uint32_t gcd_ref(uint32_t a, uint32_t b) { while (b) { uint32_t t = b; b = a % b; a = t; } return a; }
