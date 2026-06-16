#include <stdint.h>
/* x*101 — forces 3-operand imul eax,edi,101 */
uint32_t mul_imm(uint32_t x) { return x * 101u; }
