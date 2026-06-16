#include <stdint.h>
/* ~(a & b) — and + not */
uint32_t nand(uint32_t a, uint32_t b) { return ~(a & b); }
