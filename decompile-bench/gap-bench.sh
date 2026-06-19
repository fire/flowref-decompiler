#!/usr/bin/env bash
# gap-bench.sh — test fixtures for each open gap in OPEN_GAPS.md
#
# For each gap, this script:
# 1. Compiles a representative fixture (C → .o)
# 2. Attempts faithful decompilation (strict mode)
# 3. Reports: CLOSED (EQUIVALENT) vs OPEN (refusal or NOT-EQUIV)
#
# Gaps are ranked by impact (see OPEN_GAPS.md):
#   1. Scalar div/idiv with zero-divisor preconditions (HIGH)
#   2. 64-bit magic-constant division (MEDIUM)
#   3. Chained branch-phi resolution (MEDIUM)
#   4. Loop oracle proof (FORMAL)
#   5. Constraint-based type propagation (FUTURE)
#   6. Variable coalescing (READABILITY)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
FR="${FLOWREF:-$root/.lake/build/bin/flowref-decompiler}"
CC="${CC:-cc}"
TMPD="$(mktemp -d /tmp/gap-bench.XXXXXX)"
trap 'rm -rf "$TMPD"' EXIT

# ── helper: compile and attempt decompilation ─────────────────────────────────
test_gap() {
  local gap_name="$1"
  local fixture="$2"
  local expect="$3"  # "EQUIVALENT" or "REFUSES" or "NOT-EQUIV"
  local obj="$TMPD/${fixture}.o"
  
  # Compile
  "$CC" -O1 -fcf-protection=none -fno-stack-protector -c "$here/algorithms/${fixture}.c" -o "$obj" 2>/dev/null || {
    echo "  $gap_name: COMPILE_FAILED"
    return 1
  }
  
  # Get function region
  read tvma toff < <(readelf -SW "$obj" | awk '/[ \t]\.text[ \t]/{for(i=1;i<=NF;i++)if($i=="PROGBITS"){print "0x"$(i+1),"0x"$(i+2);exit}}')
  read sval szdec < <(readelf -sW "$obj" | awk -v s="$fixture" '$8==s{print "0x"$2, $3}')
  [ -n "${sval:-}" ] || { echo "  $gap_name: SYMBOL_NOT_FOUND"; return 1; }
  local szhex; szhex=$(printf "0x%x" "$szdec")
  local foff; foff=$(printf "0x%x" $((sval - tvma + toff)))
  
  # Try strict decompilation
  local verdict
  verdict="$(timeout 10 "$here/equiv.sh" "$obj" x64 "$sval" "$foff" "$sval" "$szhex" 2>/dev/null | awk '{print $1; exit}' || true)"
  
  if [ "$verdict" = "EQUIVALENT" ]; then
    echo "  $gap_name: CLOSED ($verdict)"
    return 0
  elif [ "$verdict" = "NOT-EQUIVALENT" ]; then
    echo "  $gap_name: OPEN ($verdict)"
    return 1
  else
    # Try unsafe to see if it compiles
    if "$FR" decompile "$obj" x64 "$sval" "$foff" "$sval" "$szhex" --unsafe 2>/dev/null | "$CC" -xc -std=c11 -w -fsyntax-only - 2>/dev/null; then
      echo "  $gap_name: OPEN (unsafe compiles, strict refuses)"
    else
      echo "  $gap_name: OPEN (unsafe also fails)"
    fi
    return 1
  fi
}

echo "=== Gap benchmark (OPEN_GAPS.md) ==="
echo ""

# Gap 1: Scalar div/idiv with zero-divisor preconditions
# Fixture: a simple division with a guard that proves divisor != 0
test_gap "Gap 1: div/idiv guard" "div_guarded" "EQUIVALENT" || true

# Gap 2: 64-bit magic-constant division  
# Fixture: div_by_10 which uses imul r64; shr $k pattern
test_gap "Gap 2: 64-bit magic div" "div_by_10" "EQUIVALENT" || true

# Gap 3: Chained branch-phi resolution
# Fixture: nested_select_cfg or a new nested-diamond fixture
test_gap "Gap 3: chained branch-phi" "nested_select_cfg" "EQUIVALENT" || true

# Gap 4: Loop oracle proof (formal, no runtime change)
# This is a proof gap, not a runtime gap — check that the loop fixtures still pass
test_gap "Gap 4: loop oracle" "sum_to_n" "EQUIVALENT" || true

# Gap 5: Constraint-based type propagation (future, no strict impact yet)
# No specific fixture — this is about C readability, not equivalence
echo "  Gap 5: type propagation: PENDING (readability-only, no fixture)"

# Gap 6: Variable coalescing (readability-only)
# No specific fixture — this is about C readability, not equivalence
echo "  Gap 6: variable coalescing: PENDING (readability-only, no fixture)"

echo ""
echo "=== Gap benchmark complete ==="
