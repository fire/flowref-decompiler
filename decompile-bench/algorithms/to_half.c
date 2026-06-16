#include <stdint.h>
/* (uint16_t)x — movzx eax,word; 16-bit truncation */
uint32_t to_half(uint32_t x) { return (uint32_t)(uint16_t)x; }
