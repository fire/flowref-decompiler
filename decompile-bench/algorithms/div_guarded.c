#include <stdint.h>
/* Gap 1 fixture: guarded unsigned division
 * The guard (b != 0) dominates the division, so the decompiler should
 * be able to prove the divisor is nonzero and emit C with / operator.
 */
uint32_t div_guarded(uint32_t a, uint32_t b) {
  if (b == 0) {
    return 0;  /* divisor zero case */
  }
  return a / b;  /* here b is provably nonzero */
}
