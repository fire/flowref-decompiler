#include <stdint.h>
/* b*8 + a — lea with scale, no disp */
uint32_t scale8(uint32_t a, uint32_t b) { return b*8u + a; }
