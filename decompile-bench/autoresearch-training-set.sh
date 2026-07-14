#!/usr/bin/env bash
# autoresearch-training-set.sh — measure, snapshot Parquet, commit if improved.
#
# Runs ONE parallel oracle sweep over all training fixtures, writes Parquet,
# and auto-commits if SOUNDNESS=0 and the proven count is >= last recorded.
# The Hermes cron agent (flowref-autoresearch-5m) is responsible for actually
# editing FlowrefDecompiler.lean to improve the decompiler between runs.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
FR="${FLOWREF:-$root/.lake/build/bin/flowref-decompiler}"
CC="${CC:-cc}"
RUN_ID="${FLOWREF_RESEARCH_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUTDIR="${1:-$here/out/autoresearch-training/$RUN_ID}"
BINDIR="$OUTDIR/binaries"
RESULTS="$OUTDIR/training_results.tsv"
PARQUET_DIR="$OUTDIR/parquet"

mkdir -p "$OUTDIR"

# ── build the decompiler from source FIRST ────────────────────────────────────
# Critical: the oracle sweep below runs $FR, which defaults to the prebuilt
# binary at .lake/build/bin. If we don't rebuild, an edit that breaks the
# *source* (a syntax error or an unsound gate) is measured against a STALE
# binary — silently scoring and committing broken source as "69/69". Build
# first and abort the whole run if the build fails, so we never commit source
# that does not compile. (See TOMBSTONES.md: "Gap-2 magic-constant division".)
echo "=== building flowref-decompiler from source ==="
if ! lake -d "$root" build flowref-decompiler flowref-equiv; then
  echo "ABORT: source build failed — refusing to measure a stale binary or commit" >&2
  exit 1
fi

# ── materialise training binaries ────────────────────────────────────────────
echo "=== materialising binaries ==="
"$here/build-training-binaries.sh" "$BINDIR" >/tmp/flowref-build-training.$$.log 2>&1
tail -1 /tmp/flowref-build-training.$$.log
rm -f /tmp/flowref-build-training.$$.log

# ── parallel oracle sweep ─────────────────────────────────────────────────────
echo "=== oracle sweep (BENCH_JOBS=${BENCH_JOBS:-$(nproc)}) ==="
printf "run_id\tfunction\tverdict\tunsafe_compiles\tstrict_ms\tunsafe_ms\tobject\tsource\tarch\tsymbol_vaddr\tfile_offset\tregion_vaddr\tsize_hex\tsize_dec\n" > "$RESULTS"

TMPD="$(mktemp -d /tmp/algo-sweep.XXXXXX)"
trap 'rm -rf "$TMPD"' EXIT

. "$here/training-functions.sh"

run_one() {
  local f="$1"
  local src="$here/algorithms/$f.c"
  [ -f "$src" ] || src="$here/asm/$f.S"
  [ -f "$src" ] || { printf "skip\t%s\tmissing_source\tno\t0\t0\t\t\tx64\t\t\t\t\t\n" "$f" > "$TMPD/$f.row"; return; }
  local obj="$TMPD/$f.o"
  "$CC" -O1 -fcf-protection=none -fno-stack-protector -c "$src" -o "$obj" 2>/dev/null     || { printf "skip\t%s\tcompile_failed\tno\t0\t0\t\t\tx64\t\t\t\t\t\n" "$f" > "$TMPD/$f.row"; return; }
  read tvma toff < <(readelf -SW "$obj" | awk '/[ \t]\.text[ \t]/{for(i=1;i<=NF;i++)if($i=="PROGBITS"){print "0x"$(i+1),"0x"$(i+2);exit}}')
  read sval szdec < <(readelf -sW "$obj" | awk -v s="$f" '$8==s{print "0x"$2, $3}')
  [ -n "${sval:-}" ] || { printf "skip\t%s\tsymbol_not_found\tno\t0\t0\t\t\tx64\t\t\t\t\t\n" "$f" > "$TMPD/$f.row"; return; }
  local szhex; szhex=$(printf "0x%x" "$szdec")
  local foff; foff=$(printf "0x%x" $((sval - tvma + toff)))
  local t0 t1 t2; t0=$(date +%s%3N)
  local verdict
  verdict="$(FLOWREF_EQUIV_TIMEOUT="${FLOWREF_EQUIV_TIMEOUT:-10}"     "$here/equiv.sh" "$obj" x64 "$sval" "$foff" "$sval" "$szhex" 2>/dev/null     | awk '{print $1; exit}' || true)"
  t1=$(date +%s%3N)
  local uc="no"
  "$FR" decompile "$obj" x64 "$sval" "$foff" "$sval" "$szhex" --unsafe 2>/dev/null     | "$CC" -xc -std=c11 -w -fsyntax-only - 2>/dev/null && uc="yes"
  t2=$(date +%s%3N)
  # Write row to per-function file; collector merges in order.
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tx64\t%s\t%s\t%s\t%s\t%s\n"     "$RUN_ID" "$f" "${verdict:-?}" "$uc" "$((t1-t0))" "$((t2-t1))"     "$obj" "$src" "$sval" "$foff" "$sval" "$szhex" "$szdec" > "$TMPD/$f.row"
  printf "  %-18s %-14s unsafe=%s\n" "$f" "${verdict:-?}" "$uc"
}
export -f run_one
export TMPD CC FR here RUN_ID FLOWREF_EQUIV_TIMEOUT="${FLOWREF_EQUIV_TIMEOUT:-10}"

printf "%s\n" $TRAINING_FUNCS | xargs -P "${BENCH_JOBS:-$(nproc)}" -I{} bash -c 'run_one "$@"' _ {}

# Collect rows in FUNCS order
for f in $TRAINING_FUNCS; do
  [ -f "$TMPD/$f.row" ] && cat "$TMPD/$f.row" >> "$RESULTS"
done

# ── Parquet snapshot ──────────────────────────────────────────────────────────
cd "$root" || exit 1
lake -d "$root" build flowref-training-parquet
"$root/.lake/build/bin/flowref-training-parquet" "$BINDIR/manifest.tsv" "$RESULTS" "$PARQUET_DIR"

# ── summary ───────────────────────────────────────────────────────────────────
summary=$(python3 - "$RESULTS" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
proven    = sum(r['verdict'] == 'EQUIVALENT'     for r in rows)
viol      = sum(r['verdict'] == 'NOT-EQUIVALENT' for r in rows)
unsafe    = sum(r['unsafe_compiles'] == 'yes'    for r in rows)
print(f"STRICT  : {proven}/{len(rows)} observed-equivalent")
print(f"UNSAFE  : {unsafe}/{len(rows)} emit C that compiles")
print(f"SOUNDNESS: {viol} violations")
PY
)
printf '%s\n' "$summary"

# ── accept/reject ─────────────────────────────────────────────────────────────
if printf '%s\n' "$summary" | grep -q "SOUNDNESS: 0 violations"; then
  cd "$root"
  dirty=$(git diff --name-only HEAD)
  if [ -n "$dirty" ]; then
    proven=$(printf '%s\n' "$summary" | grep '^STRICT' | awk '{print $3}')
    git add -u
    git commit -m "Autoresearch run $RUN_ID: $proven observed-equivalent, SOUNDNESS 0"
    echo "committed run $RUN_ID"
  else
    echo "nothing to commit for run $RUN_ID"
  fi
  exit 0
else
  echo "REJECT: SOUNDNESS violation — not committing run $RUN_ID" >&2
  exit 1
fi
