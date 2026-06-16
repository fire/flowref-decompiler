#include <stdint.h>
/* (uint8_t)x — movzx eax,dil; tests sub-register truncation */
uint32_t to_byte(uint32_t x) { return (uint32_t)(uint8_t)x; }
