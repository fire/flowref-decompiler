#include <stdint.h>
/* Zero-extension loop — movzx inside a loop body */
uint32_t zero_ext_loop(uint32_t x, uint32_t n) {
    while (n) {
        x = (uint8_t)(x + n);
        n--;
    }
    return x;
}
