#include <stdint.h>

/* Loop signed branch — jle/jg */
uint32_t loop_signed_jg(int32_t n) {
    uint32_t acc = 0;
    for (int32_t i = 0; i < n; i += 2) {
        acc += (uint32_t)i;
    }
    return acc;
}
