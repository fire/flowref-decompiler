#include <stdint.h>
/* variable left shift — shl eax,cl */
uint32_t shift_l(uint32_t x, uint32_t n) { return x << (n & 31u); }
