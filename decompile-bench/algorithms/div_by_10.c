#include <stdint.h>
/* Gap 2 fixture: 64-bit magic-constant division pattern
 * Divide by constant 10 - should trigger imul r64; shr $k pattern
 */
uint32_t div_by_10(uint32_t x) {
  return x / 10;
}
