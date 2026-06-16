#include <stdint.h>
/* c ? a : b — test c,c + cmov (ZF condition) */
uint32_t sel_nz(uint32_t c, uint32_t a, uint32_t b) { return c ? a : b; }
