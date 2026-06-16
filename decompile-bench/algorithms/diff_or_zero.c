#include <stdint.h>
/* monus: max(a-b,0) — cmp + cmov */
uint32_t diff_or_zero(uint32_t a, uint32_t b) { uint32_t d = a - b; return a < b ? 0u : d; }
