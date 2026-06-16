#include <stdint.h>
/* a + b*4 + 10 — lea with base+scale+disp */
uint32_t addr_calc(uint32_t a, uint32_t b) { return a + b*4u + 10u; }
