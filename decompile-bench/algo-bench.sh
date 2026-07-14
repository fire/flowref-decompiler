#!/usr/bin/env bash
# algo-bench.sh — decompilation faithfulness on our own textbook algorithms.
#
# We wrote decompile-bench/algorithms/*.c plus a few decompile-bench/asm/*.S
# branch-shape fixtures (one function per file), so we own the ground truth. For
# each file this compiles it to its own object, then reports:
#   STRICT : the equivalence oracle's verdict on flowref's faithful-or-refuse
#            lift — EQUIVALENT (observed over a sampled input domain, not a Lean
#            proof) / INCOMPARABLE (refused = unknown, never wrong).
#   UNSAFE : whether flowref's --unsafe best-effort C at least compiles
#            (syntax-correct C), a coverage signal for the refused class.
#
# Parallelism: BENCH_JOBS (default: nproc) oracle workers run concurrently.
# Each function compiles, runs the oracle, and writes a single-line result to
# a temp dir; the collector merges them in FUNCS order at the end.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
FR="${FLOWREF:-$here/../.lake/build/bin/flowref-decompiler}"
CC="${CC:-cc}"
JOBS="${BENCH_JOBS:-$(nproc)}"
# Fast default timeout: INCOMPARABLE functions always exhaust the oracle anyway;
# EQUIVALENT ones finish in under 2s. Override with FLOWREF_EQUIV_TIMEOUT=120
# for targeted single-function checks on new loop classes.
export FLOWREF_EQUIV_TIMEOUT="${FLOWREF_EQUIV_TIMEOUT:-10}"
SRCDIR="$here/algorithms"
ASMDIR="$here/asm"
. "$here/training-functions.sh"

FUNCS="$TRAINING_FUNCS"

# Scratch dir — one file per function: "<verdict>\t<uc>"
TMPDIR="$(mktemp -d /tmp/algo-bench.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# Worker: compile, oracle, unsafe-compile for a single function.
run_one() {
  local f="$1"
  local src="$SRCDIR/$f.c"
  [ -f "$src" ] || src="$ASMDIR/$f.S"
  if [ ! -f "$src" ]; then
    echo "source_not_found	no" > "$TMPDIR/$f"
    return
  fi
  local obj
  obj="$(mktemp /tmp/algo.$f.XXXXXX.o)"
  if ! "$CC" -O1 -fcf-protection=none -fno-stack-protector -c "$src" -o "$obj" 2>/dev/null; then
    echo "cannot_compile	no" > "$TMPDIR/$f"
    rm -f "$obj"
    return
  fi

  read TVMA TOFF < <(readelf -SW "$obj" | awk '/[ \t]\.text[ \t]/{for(i=1;i<=NF;i++)if($i=="PROGBITS"){print "0x"$(i+1),"0x"$(i+2);exit}}')
  read SVAL SZDEC < <(readelf -sW "$obj" | awk -v s="$f" '$8==s{print "0x"$2, $3}')
  if [ -z "${SVAL:-}" ]; then
    echo "symbol_not_found	no" > "$TMPDIR/$f"
    rm -f "$obj"
    return
  fi
  local SSIZE
  SSIZE=$(printf "0x%x" "$SZDEC")
  local FOFF
  FOFF=$(printf "0x%x" $((SVAL - TVMA + TOFF)))

  local verdict
  verdict="$("$here/equiv.sh" "$obj" x64 "$SVAL" "$FOFF" "$SVAL" "$SSIZE" 2>/dev/null | awk '{print $1; exit}')"

  local uc="no"
  if "$FR" decompile "$obj" x64 "$SVAL" "$FOFF" "$SVAL" "$SSIZE" --unsafe 2>/dev/null \
       | "$CC" -xc -std=c11 -w -fsyntax-only - 2>/dev/null; then
    uc="yes"
  fi

  echo "${verdict:-?}	$uc" > "$TMPDIR/$f"
  rm -f "$obj"
}

export -f run_one
export TMPDIR CC FR here SRCDIR ASMDIR

# Run all workers — up to JOBS concurrent.
printf "%s\n" $FUNCS | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

# Collect results in FUNCS order and tally.
total=0; proven=0; unsafe_ok=0; violations=0
printf "%-15s %-14s %s\n" "function" "STRICT" "UNSAFE-compiles"
printf "%-15s %-14s %s\n" "--------" "------" "---------------"
for f in $FUNCS; do
  result_file="$TMPDIR/$f"
  if [ ! -f "$result_file" ]; then
    printf "%-15s %s\n" "$f" "(no result)"; continue
  fi
  IFS=$'\t' read -r verdict uc < "$result_file"
  case "$verdict" in
    source_not_found|cannot_compile|symbol_not_found)
      printf "%-15s %s\n" "$f" "($verdict)"; continue ;;
  esac
  total=$((total+1))
  case "$verdict" in
    EQUIVALENT)     proven=$((proven+1)) ;;
    NOT-EQUIVALENT) violations=$((violations+1)) ;;
  esac
  [ "$uc" = "yes" ] && unsafe_ok=$((unsafe_ok+1))
  printf "%-15s %-14s %s\n" "$f" "$verdict" "$uc"
done

echo
echo "STRICT  : $proven/$total observed-equivalent (oracle: sampled domain, not a proof)"
echo "UNSAFE  : $unsafe_ok/$total emit C that compiles (best-effort coverage signal)"
if [ "$violations" -gt 0 ]; then
  echo "SOUNDNESS: $violations/$total strict lifts were NOT-EQUIVALENT — flowref emitted"
  echo "           wrong C while claiming 'faithful'. This must be 0; the faithfulness"
  echo "           gate must REFUSE instructions it cannot model (e.g. cmov/setcc)."
  exit 1
fi
echo "SOUNDNESS: 0 violations (no strict lift was wrong)."
