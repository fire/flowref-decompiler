#!/usr/bin/env bash
# autoresearch-training-set.sh — fixed-budget, accept/reject snapshots for the
# self-authored training set.
#
# This ports the useful `karpathy/autoresearch` principles to flowref:
#   * one reproducible training/eval loop,
#   * fixed wall-clock budget for comparable iterations,
#   * explicit metric (`STRICT proven`, lower soundness violations is mandatory),
#   * accept/reject by measured oracle output, not vibes,
#   * durable experiment logs as Parquet, not a persistent database.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
FR="${FLOWREF:-$root/.lake/build/bin/flowref-decompiler}"
CC="${CC:-cc}"
TIME_BUDGET_SECONDS="${FLOWREF_RESEARCH_BUDGET:-300}"
RUN_ID="${FLOWREF_RESEARCH_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUTDIR="${1:-$here/out/autoresearch-training/$RUN_ID}"
BINDIR="$OUTDIR/binaries"
RESULTS="$OUTDIR/training_results.tsv"
PARQUET_DIR="$OUTDIR/parquet"

mkdir -p "$OUTDIR"

start_epoch=$(date +%s)
"$here/build-training-binaries.sh" "$BINDIR" >/tmp/flowref-build-training.$$.log
cat /tmp/flowref-build-training.$$.log
rm -f /tmp/flowref-build-training.$$.log

printf "run_id\tfunction\tverdict\tunsafe_compiles\tstrict_ms\tunsafe_ms\tobject\tsource\tarch\tsymbol_vaddr\tfile_offset\tregion_vaddr\tsize_hex\tsize_dec\n" > "$RESULTS"

while IFS=$'\t' read -r function source object arch symbol_vaddr file_offset region_vaddr size_hex size_dec; do
  [ "$function" = "function" ] && continue
  now=$(date +%s)
  if [ $((now - start_epoch)) -ge "$TIME_BUDGET_SECONDS" ]; then
    echo "budget exhausted after $((now - start_epoch))s; stopping before $function" >&2
    break
  fi

  t0=$(date +%s%3N)
  verdict="$(FLOWREF_EQUIV_TIMEOUT="${FLOWREF_EQUIV_TIMEOUT:-120}" \
    $here/equiv.sh "$object" "$arch" "$symbol_vaddr" "$file_offset" "$region_vaddr" "$size_hex" 2>/dev/null \
    | awk '{print $1; exit}' || true)"
  t1=$(date +%s%3N)

  if "$FR" decompile "$object" "$arch" "$symbol_vaddr" "$file_offset" "$region_vaddr" "$size_hex" --unsafe 2>/dev/null \
      | "$CC" -xc -std=c11 -w -fsyntax-only - 2>/dev/null; then
    unsafe="yes"
  else
    unsafe="no"
  fi
  t2=$(date +%s%3N)

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$RUN_ID" "$function" "${verdict:-?}" "$unsafe" "$((t1 - t0))" "$((t2 - t1))" \
    "$object" "$source" "$arch" "$symbol_vaddr" "$file_offset" "$region_vaddr" "$size_hex" "$size_dec" >> "$RESULTS"
  printf "%-18s %-14s unsafe=%s\n" "$function" "${verdict:-?}" "$unsafe"
done < "$BINDIR/manifest.tsv"

lake -d "$root" build flowref-training-parquet
"$root/.lake/build/bin/flowref-training-parquet" "$BINDIR/manifest.tsv" "$RESULTS" "$PARQUET_DIR"

summary=$(python3 - "$RESULTS" <<'PY'
import csv, sys
rows=list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
proven=sum(r['verdict']=='EQUIVALENT' for r in rows)
viol=sum(r['verdict']=='NOT-EQUIVALENT' for r in rows)
unsafe=sum(r['unsafe_compiles']=='yes' for r in rows)
print(f"STRICT  : {proven}/{len(rows)} proven EQUIVALENT")
print(f"UNSAFE  : {unsafe}/{len(rows)} emit C that compiles")
print(f"SOUNDNESS: {viol} violations")
PY
)
printf '%s\n' "$summary"
if printf '%s\n' "$summary" | grep -q "SOUNDNESS: 0 violations"; then
  # Accept: commit any dirty tracked files in the repo root.
  cd "$root"
  dirty=$(git diff --name-only HEAD)
  if [ -n "$dirty" ]; then
    proven=$(printf '%s\n' "$summary" | grep '^STRICT' | awk '{print $3}')
    git add -u
    git commit -m "Autoresearch run $RUN_ID: $proven proven EQUIVALENT, SOUNDNESS 0"
    echo "committed run $RUN_ID"
  else
    echo "nothing to commit for run $RUN_ID"
  fi
  exit 0
else
  echo "REJECT: SOUNDNESS violation — not committing run $RUN_ID" >&2
  exit 1
fi
