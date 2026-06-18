#include <stdint.h>
/* signed absolute value — neg + cmovs pattern (SF-based cmov) */
uint32_t abs_int(int32_t x) { return (uint32_t)(x < 0 ? -x : x); }
