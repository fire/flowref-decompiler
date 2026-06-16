#include <stdint.h>
/* base-10 digit count — while loop with div */
uint32_t digit_count(uint32_t x) { uint32_t n = 1; while (x >= 10u) { x /= 10u; n++; } return n; }
