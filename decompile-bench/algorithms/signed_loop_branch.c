#include <stdint.h>
/* Loop signed branch — jns/js */
uint32_t signed_loop_branch(int32_t x) {
    uint32_t acc = 0;
    while (x < 0) {
        acc += (uint32_t)x;
        x += 7;
    }
    return acc;
}
