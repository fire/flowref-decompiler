#include <stdint.h>
/* median of 3 — typically THREE cmov; gate must refuse (cmovCount>2) */
uint32_t med3(uint32_t a, uint32_t b, uint32_t c) {
  uint32_t lo = a < b ? a : b, hi = a < b ? b : a;
  uint32_t m = hi < c ? hi : c;
  return lo < m ? m : lo;
}
