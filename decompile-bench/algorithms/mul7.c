#include <stdint.h>
/* x*7 — may emit 3-operand imul eax,edi,7 (untested path) */
uint32_t mul7(uint32_t x) { return x * 7u; }
