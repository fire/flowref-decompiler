#include <stdint.h>
/* Bit-scan reverse nonzero — bsr */
uint32_t bsr_nonzero(uint32_t x) { return 31u - (uint32_t)__builtin_clz(x | 1u); }
