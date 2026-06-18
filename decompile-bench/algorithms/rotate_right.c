#include <stdint.h>

/* Bitwise rotate — ror */
uint32_t rotate_right(uint32_t x, uint32_t n) {
    return (x >> (n & 31)) | (x << ((32 - n) & 31));
}
