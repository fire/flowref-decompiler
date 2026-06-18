#!/usr/bin/env bash
# build-training-binaries.sh — materialize the self-authored training-set binaries.
#
# The normal algo-bench harness compiles each fixture to a temporary object and
# deletes it after oracle evaluation. This script keeps those object files under
# decompile-bench/out/training-binaries/ and writes a manifest with the exact
# region tuple needed by flowref/equiv.sh:
#
#   function source object arch symbol_vaddr file_offset region_vaddr size_hex size_dec
#
# The generated directory is intentionally ignored by git; the source fixtures
# and this reproducible build script are the tracked artifact.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-cc}"
OUTDIR="${1:-$here/out/training-binaries}"
SRCDIR="$here/algorithms"
ASMDIR="$here/asm"

# Keep in sync with algo-bench.sh: one training fixture per named function.
FUNCS="id32 add2 umax umin abs_diff gray_code avg_floor \
       isolate_lowest_bit clear_lowest_bit clamp max3 min3 sat_add sat_sub diff_or_zero \
       parity bit_merge mul5 lin2 combine4 pack16 mul7 to_byte to_half med3 \
       to_sbyte to_shalf shift_r shift_l mul_imm addr_calc scale8 nand \
       sel_nz is_zero cmp_lt cmp_le cmp_eq nonzero is_even in_range branch_select branch_select_slt branch_phi_add branch_phi_twouse \
       russian_mul count_divisors \
       sum_to_n factorial fib_iter popcount log2_floor reverse_bits ctz digit_count \
       gcd isqrt pow_uint is_prime collatz_steps lcm"

mkdir -p "$OUTDIR"
manifest="$OUTDIR/manifest.tsv"
printf "function\tsource\tobject\tarch\tsymbol_vaddr\tfile_offset\tregion_vaddr\tsize_hex\tsize_dec\n" > "$manifest"

built=0
for f in $FUNCS; do
  src="$SRCDIR/$f.c"
  [ -f "$src" ] || src="$ASMDIR/$f.S"
  [ -f "$src" ] || { echo "missing source for $f" >&2; exit 1; }

  obj="$OUTDIR/$f.o"
  "$CC" -O1 -fcf-protection=none -fno-stack-protector -c "$src" -o "$obj"

  read tvma toff < <(readelf -SW "$obj" | awk '/[ \t]\.text[ \t]/{for(i=1;i<=NF;i++)if($i=="PROGBITS"){print "0x"$(i+1),"0x"$(i+2);exit}}')
  read sval szdec < <(readelf -sW "$obj" | awk -v s="$f" '$8==s{print "0x"$2, $3}')
  [ -n "${sval:-}" ] || { echo "symbol not found for $f in $obj" >&2; exit 1; }
  size_hex=$(printf "0x%x" "$szdec")
  foff=$(printf "0x%x" $((sval - tvma + toff)))

  printf "%s\t%s\t%s\tx64\t%s\t%s\t%s\t%s\t%s\n" \
    "$f" "$src" "$obj" "$sval" "$foff" "$sval" "$size_hex" "$szdec" >> "$manifest"
  built=$((built + 1))
done

echo "built $built training-set objects in $OUTDIR"
echo "manifest: $manifest"
