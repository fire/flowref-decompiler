#include <stdint.h>
/* saturating subtract — sub sets borrow -> cmov */
uint32_t sat_sub(uint32_t a, uint32_t b) { return a > b ? a - b : 0u; }
