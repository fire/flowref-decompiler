#include <stdint.h>

// Exercises signed comparison lowering via cmp + setl.
uint32_t signed_lt(uint32_t x, uint32_t y) {
    return (uint32_t)((int32_t)x < (int32_t)y);
}
