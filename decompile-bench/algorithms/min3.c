#include <stdint.h>
/* min of three — two cmov (mirror of max3) */
uint32_t min3(uint32_t a, uint32_t b, uint32_t c) {
  uint32_t m = a < b ? a : b;
  return m < c ? m : c;
}
