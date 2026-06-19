#include <stdint.h>
/* Gap 2 fixture: 64-bit magic-constant division pattern
 * This uses the compiler's reciprocal-multiply idiom for constant division.
 * GCC/Clang will emit: imul r64, magic; shr $k, r64
 * The decompiler should recognize this pattern and emit the quotient.
 */
uint32_t pow_uint(uint32_t base, uint32_t exp) {
  uint32_t result = 1;
  while (exp > 0) {
    if (exp & 1) {
      result = result * base;
    }
    exp >>= 1;
    if (exp > 0) {
      base = base * base;
    }
  }
  return result;
}
