/* lean-capstone FFI shim — disassemble a byte buffer via vendored Capstone.

   Exposes one primitive to Lean: `lean_capstone_disasm`, which disassembles
   `code` at base address `addr` for `(archCode, modeBits)`, and returns the
   listing as a newline-separated string of "address<TAB>mnemonic<TAB>operands"
   lines (TSV transport; Lean parses it). Empty string on a Capstone open
   error.

   Capstone is vendored as a full multi-arch static lib in
   thirdparty/capstone/lib/libcapstone.a (BSD-3; headers in
   thirdparty/capstone/include).
   archCode is a raw `cs_arch` value and modeBits a raw `cs_mode` bitmask, so
   every architecture/mode the vendored build supports is reachable. */

#include <lean/lean.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <capstone/capstone.h>

LEAN_EXPORT lean_obj_res lean_capstone_disasm(uint32_t archCode,
                                              uint32_t modeBits,
                                              b_lean_obj_arg code,
                                              uint64_t addr) {
  csh handle;
  if (cs_open((cs_arch)archCode, (cs_mode)modeBits, &handle) != CS_ERR_OK)
    return lean_mk_string("");

  size_t n = lean_sarray_size(code);
  const uint8_t *buf = (const uint8_t *)lean_sarray_cptr(code);

  cs_insn *insn = NULL;
  size_t count = cs_disasm(handle, buf, n, addr, 0, &insn);

  size_t cap = 8192, len = 0;
  char *out = (char *)malloc(cap);
  out[0] = '\0';
  for (size_t i = 0; i < count; i++) {
    char line[512];
    int m = snprintf(line, sizeof line, "%llx\t%s\t%s\n",
                     (unsigned long long)insn[i].address,
                     insn[i].mnemonic, insn[i].op_str);
    if (m < 0) continue;
    if (len + (size_t)m + 1 > cap) { cap = (len + (size_t)m + 1) * 2; out = (char *)realloc(out, cap); }
    memcpy(out + len, line, (size_t)m);
    len += (size_t)m;
    out[len] = '\0';
  }
  if (count > 0) cs_free(insn, count);
  cs_close(&handle);

  lean_object *s = lean_mk_string(out);
  free(out);
  return s;
}
