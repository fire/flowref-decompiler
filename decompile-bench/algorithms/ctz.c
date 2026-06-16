#include <stdint.h>
/* count trailing zeros (x!=0 assumed) — while loop */
uint32_t ctz(uint32_t x) { uint32_t n = 0; while ((x & 1u) == 0u) { x >>= 1; n++; } return n; }
