#include <stdint.h>
/* (int8_t)x sign-extended — movsx eax,dil (validates movsx path) */
uint32_t to_sbyte(uint32_t x) { return (uint32_t)(int32_t)(int8_t)x; }
