#include <stdint.h>
/* Gap 2 fixture: simpler 64-bit magic-constant division
 * Divide by a constant that triggers the imul r64; shr $k pattern.
 */
uint32_t div_by_10(uint32_t x) {
  return x / 10;
}
