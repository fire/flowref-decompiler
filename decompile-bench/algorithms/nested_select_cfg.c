#include <stdint.h>

/* Nested select CFG — branch diamond feeding a second branch diamond */
__attribute__((optimize("no-if-conversion")))
uint32_t nested_select_cfg(uint32_t a, uint32_t b, uint32_t c) {
    uint32_t x;
    if (a < b) x = a + 1; else x = b + 2;
    if (x < c) x = x + 3; else x = x + 4;
    return x;
}
