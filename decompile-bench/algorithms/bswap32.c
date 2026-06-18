#include <stdint.h>
/* Byte-swap endian flip — bswap */
uint32_t bswap32(uint32_t x) {
    return __builtin_bswap32(x);
}
