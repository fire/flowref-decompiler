#include <stdint.h>
/* parity of popcount via xor-fold — register-only leaf */
uint32_t parity(uint32_t x) { x ^= x >> 16; x ^= x >> 8; x ^= x >> 4; x ^= x >> 2; x ^= x >> 1; return x & 1u; }
