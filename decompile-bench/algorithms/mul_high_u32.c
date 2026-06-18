#include <stdint.h>
/* Unsigned multiply high half — mul */
uint32_t mul_high_u32(uint32_t x, uint32_t y) {
    uint32_t hi;
    __asm__("mull %2" : "+a"(x), "=d"(hi) : "r"(y) : "cc");
    return hi;
}
