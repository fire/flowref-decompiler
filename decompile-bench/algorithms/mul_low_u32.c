#include <stdint.h>
/* Unsigned multiply low half — mul */
uint32_t mul_low_u32(uint32_t x, uint32_t y) {
    uint32_t lo;
    __asm__("mull %2" : "=a"(lo) : "a"(x), "r"(y) : "edx", "cc");
    return lo;
}
