#include <stdint.h>
/* variable right shift — shr eax,cl (x86 masks count to 5 bits) */
uint32_t shift_r(uint32_t x, uint32_t n) { return x >> (n & 31u); }
