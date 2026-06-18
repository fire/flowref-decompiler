#include <stdint.h>
/* Bit-scan leading zeros — lzcnt */
__attribute__((target("lzcnt")))
uint32_t lzcnt_nonzero(uint32_t x) { return (uint32_t)__builtin_clz(x | 1u); }
