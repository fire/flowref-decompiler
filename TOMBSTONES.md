# TOMBSTONES — dead ends, refuted hypotheses, blocked avenues

Why each was abandoned, and where any surviving knowledge lives. Keeps us from
re-trying what already failed.

## `-fno-if-conversion` does NOT force a branch for a pure value-select

Tried to get a real branch-diamond test case (for branch→select lifting) by
compiling `a < b ? b : a` with `gcc -O1 -fno-if-conversion -fno-if-conversion2`.
gcc still emits `cmp; mov; cmovnb` — the backend lowers a select to `cmov`
regardless of the if-conversion passes. **Surviving knowledge:** to get a genuine
branch, use `-O0` or an arm the backend cannot cmov (memory effect / call).

## `plausible` `Fin 65536` sampler as the equivalence oracle — replaced

The oracle's `∀ args` search over `Fin 65536` was size-biased toward small values
and almost never tested args ≥ 256, passing **false EQUIVALENTs** for bugs that
only diverge at large inputs (e.g. a dropped `movzx` truncation). Replaced by a
deterministic boundary battery + full-range random sweep (now in `EquivCheck.lean`;
see `CHANGELOG.md`). Note: `plausible` is still correct and used for the
reaching-def witness search, where it hunts for *any* counterexample to existence,
not value-equivalence over the full input range.

## Capping the dynamic oracle range for symbolic loops — vetoed

Proposed for `isqrt`: restrict the plausible/`equiv.sh` input battery to the range
`[0, sqrt(UINT_MAX)]` to avoid 65535-iteration runs timing out.

**Why this is wrong:** it reduces a universal statement over 2³² inputs to a
probabilistic one over ~65535. It is precisely the mindset that caused the
`isGuardedLoop5` SOUNDNESS: 3 regression — 10s timeouts hid bugs that only
manifest at specific large inputs (see above). Capping the range for `isqrt`
would produce a false EQUIVALENT for any bug that only triggers near n=4B.

**Correct path:** the `addLoop_correct` proof in `IL.lean` shows the template.
For a symbolic-bound loop, state a loop invariant and prove by `induction n with`
+ `bv_omega` for per-step arithmetic. This yields a machine-checked theorem over
all 2³² inputs — not just the tested subset. See OPEN_GAPS.md item 2.

## Graceful degradation via `/* unmodeled */` inline comments — vetoed

Proposed: when a function contains unmodeled instructions, emit the body anyway
with `/* unmodeled: <insn> */` comment placeholders instead of refusing entirely.

**Why this is wrong:** the faithful-or-refuse contract (rule I0) exists precisely
because partial output is more dangerous than no output. A caller reading decompiled
C with silent `/* unmodeled */` gaps cannot tell which parts are correct. The result
looks plausible, compiles, and may pass a quick smoke test — but embeds holes that
cause wrong behaviour. This is strictly worse than a hard refusal, which forces the
caller to acknowledge the gap.

The `--unsafe` flag already exists for exploratory inspection of unlifted functions.
It carries an explicit "NOT faithful — do not trust" banner and is never recorded as
EQUIVALENT by the oracle. That is the correct safety valve.

**Surviving knowledge:** if a class of unmodeled instructions is worth handling,
the right path is: add the instruction to `modeledX86`, add an emitter case in
`renderExprC`, prove the gate extension sound via the oracle, widen the faithful gate
only after `SOUNDNESS: 0` is confirmed with a full oracle timeout.

## `isGuardedLoop5` gate — widened without full oracle check, reverted

The Hermes autoresearch cron committed a `isGuardedLoop5 : Bool` gate that widened
the faithful class to 5-block "guarded loop" functions. The oracle sweep at the time
used `FLOWREF_EQUIV_TIMEOUT=10s` — too short to check `russian_mul`, `sum_to_n`, and
`fib_iter` which were previously INCOMPARABLE (strict refused them). Once the gate
flagged them faithful, a full oracle run revealed SOUNDNESS: 3 NOT-EQUIVALENT.

Root cause: the gate checked `nB==5 ∧ b==0 ∧ tb==4 ∧ condBlocks.contains 2` which
also matched `russian_mul` (a different 5-block shape). The emitter then emitted wrong
C with the inverted guard + B3 inline path, producing wrong return values.

Lesson: when widening the faithful gate, run `./decompile-bench/algo-bench.sh` with
**full oracle timeout** (`FLOWREF_EQUIV_TIMEOUT=60` minimum) on all functions that
newly become EQUIVALENT. A 10s timeout that reports INCOMPARABLE (timeout) is NOT
proof of soundness — it just means the oracle didn't have time to find the bug.

Surviving knowledge: the correct generalisation uses the plausible witness DAG to
detect the guard block as "the condBlock whose condTgtBlk has an uncondTgtBlk to a
ret block", not by hardcoding block indices. See OPEN_GAPS.md item 1.

## Gap-2 magic-constant division (`imul r64; shr $k`) — reverted, never compiled

The autoresearch cron added a `magicDivsModeled` gate (`isMagicDivPattern` in
`FlowrefDecompiler.lean`) plus an `imul` branch in `Emit.lean/renderExprC` to lift
the compiler's reciprocal-multiply division idiom. It was committed across several
"69/69" runs but **never built**: `isMagicDivPattern` was a `def` nested inside the
`emitC` `do`-block (illegal), and the Emit branch hardcoded `s!"({srcReg} / 10u)"`
for *any* 64-bit `imul`+`shr` — wildly unsound and clobbering normal `imul`
multiply rendering. The gate itself was also unsound: requiring *every* `imul` to be
a magic-div pattern would refuse legitimate multiply fixtures (`mul5`/`mul7`/`lin2`).

**How it got committed:** `autoresearch-training-set.sh` ran the *prebuilt* binary
(`$FR`) and never rebuilt the decompiler from source, so the broken source was
scored against a stale binary and auto-committed as "69/69, SOUNDNESS 0". The same
process error also shipped a type-broken Gap-1 path-fact addition to `Lift.lean`
(`cmp : Option (String × String)` vs a stored `Option String`).

**Fix:** reverted both Gap-2 changes; made the Gap-1 `Lift.lean` path-fact handling
type-correct and sound (only assert a zero/nonzero fact for a genuine zero-test
`test r,r` or `cmp r,0`). Added a build-or-abort guard to
`autoresearch-training-set.sh` so a non-compiling source can never be committed.

**Surviving knowledge / resolution:** Gap 2 was later closed (2026-06-29) without a
divisor recognizer at all. The 64-bit `imul` was simply being emitted as a 32-bit
multiply (operands typed `uint32_t`), dropping the high half. `renderExprC` now
widens a 2-operand `imul` with a 64-bit destination to `(uint64_t)(d) * (uint64_t)(s)`,
which is faithful to `imul r64` and makes the reciprocal-multiply correct — `div_by_10`
is EQUIVALENT under the full oracle (see CHANGELOG.md). The lesson: a hardcoded `/ 10u`
guessed the *meaning*; the real fix was to emit the *instruction* at its true width and
let the oracle confirm equivalence. A readable `x / 10` surface form (recovering the
divisor from the magic constant) remains a separate, lower-priority readability task.

## `cmovCount ≤ 2` gate cap — removed

Was a workaround for the cmov-feeds-cmp SSA bug. Once the single-block reaching-def
became cmov-aware (canonReg + latest-def-before-use), arbitrary cmov chains lift
soundly (med3 = 4 cmovs proven), so the cap was removed.
