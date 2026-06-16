#include <stdint.h>
/* x==0 ? 1 : 0 — test + sete/cmov */
uint32_t is_zero(uint32_t x) { return x == 0u ? 1u : 0u; }
