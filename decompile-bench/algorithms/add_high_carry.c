#include <stdint.h>
/* Carry arithmetic high-limb add — adc */
uint32_t add_high_carry(uint32_t alo, uint32_t ahi, uint32_t blo, uint32_t bhi) {
    uint32_t lo = alo + blo;
    return ahi + bhi + (lo < alo);
}
