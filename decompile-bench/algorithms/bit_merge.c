#include <stdint.h>
/* merge bits of a and b per mask: a^((a^b)&m) — register-only leaf */
uint32_t bit_merge(uint32_t a, uint32_t b, uint32_t mask) { return a ^ ((a ^ b) & mask); }
