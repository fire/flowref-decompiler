#include <stdint.h>
/* (int16_t)x sign-extended — movsx eax,di */
uint32_t to_shalf(uint32_t x) { return (uint32_t)(int32_t)(int16_t)x; }
