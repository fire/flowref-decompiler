#!/usr/bin/env bash
# flowref test runner — builds, runs the demos, and verifies the emitted C
# compiles with gcc. Exits non-zero on ANY failure.
set -euo pipefail

cd "$(dirname "$0")"

# Make the Lean toolchain visible if Homebrew installed it.
if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
  export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

GCC="${GCC:-gcc}"
BIN=".lake/build/bin/flowref"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

echo "== 1. lake build =="
lake build || fail "lake build failed"
pass "build clean"

echo "== 2. --version / --help =="
"$BIN" --version    | grep -q "flowref" || fail "--version"
"$BIN" --help       | grep -q "USAGE"  || fail "--help"
pass "version/help"

echo "== 3. --demo runs =="
"$BIN" --demo > /dev/null || fail "--demo crashed"
pass "demo runs"

echo "== 4. --demo --emit-c compiles with gcc -fsyntax-only =="
"$BIN" --demo --emit-c | "$GCC" -xc -std=c11 -w -fsyntax-only - \
  || fail "demo C does not compile"
pass "demo C compiles (-fsyntax-only)"

echo "== 5. --demo --emit-c compiles to an object (gcc -c) =="
tmpc="$(mktemp /tmp/flowref-demo.XXXXXX.c)"
tmpo="$(mktemp /tmp/flowref-demo.XXXXXX.o)"
"$BIN" --demo --emit-c > "$tmpc"
"$GCC" -xc -std=c11 -w -c "$tmpc" -o "$tmpo" || fail "demo C does not compile to .o"
rm -f "$tmpc" "$tmpo"
pass "demo C compiles to object"

echo "== 6. iterative-deepening escalation demonstrated =="
out="$("$BIN" --demo-deep)"
echo "$out"
echo "$out" | grep -q "L0 (walkSteps=64.*UNRESOLVED" || fail "L0 should be unresolved"
echo "$out" | grep -q "L1 (walkSteps=512.*RESOLVED"   || fail "L1 should resolve"
pass "shallow L0 unresolved; deepened L1 resolves"

echo "== 7. real-function decompile compiles (if test binary present) =="
REALBIN="${FLOWREF_REALBIN:-/tmp/hdkout/app/dev/bin/HUBAtgiToAnim.exe}"
if [ -f "$REALBIN" ]; then
  "$BIN" decompile "$REALBIN" x86 0x401010 0x1010 0x401010 0x2c 2>/dev/null \
    | "$GCC" -xc -std=c11 -w -fsyntax-only - || fail "real-function C does not compile"
  pass "real-function C compiles (-fsyntax-only)"
else
  echo "skip: real test binary not present ($REALBIN)"
fi

echo "== 8. error handling: unreadable file exits non-zero =="
if "$BIN" decompile /nonexistent-file x86 0x1 0x1 0x1 0x1 2>/dev/null; then
  fail "expected non-zero exit on missing file"
fi
pass "missing file yields non-zero exit"

echo
echo "ALL TESTS PASSED"
