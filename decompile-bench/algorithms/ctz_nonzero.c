#include <stdint.h>
/* Bit-scan count trailing zeros — bsf */
uint32_t ctz_nonzero(uint32_t x) { return (uint32_t)__builtin_ctz(x | 1u); }
