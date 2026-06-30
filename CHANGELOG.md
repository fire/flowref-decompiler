# CHANGELOG — completed work, decisions, durable rules

State that is **done and verified** lives here. Unfinished work → `OPEN_GAPS.md`;
dead ends → `TOMBSTONES.md`. Each fact lives in exactly one of the three.

## Durable project rules (do not break)

- Faithful-or-refuse (I0). Strict mode emits C only for the modeled class; any
  unmodeled instruction ⇒ refuse (hard error, nothing on stdout). Widen the gate
  ONLY after the equivalence oracle proves the new lift EQUIVALENT. `algo-bench.sh`
  must always report `SOUNDNESS: 0`.
- Verify + commit discipline. Every change is checked with `lake build
  flowref-decompiler` AND `./decompile-bench/algo-bench.sh` (SOUNDNESS 0); commit
  each green step.
- Build Lean tools, not CLIs. lean-slang compiles to SPIR-V in-process via a
  libslang FFI, never the `slangc` CLI.
- No `objdump`. It is denied in `.claude/settings.json`. Use flowref's own
  disassembler or `gcc -S`.
- Generated C contains no inline assembly. Assembly fixtures may exist only as
  binary-side inputs for shape coverage; flowref's converted C output must stay
  portable C, not `asm`.
- CFG recovery reuses the plausible witness DAG. Do not write new dataflow/CFG
  analysis — reuse `reachingDefsB`/`resolveReachingDef`/`certifyReaching`,
  `condBlocks`, `predOf`, and the plausible back-edge check. It works and is fast.
- Minimal executable machine first. Follow the tinygrad-style insight: encode
  executable semantics through a small canonical machine/IL, not by solving every
  architecture independently. Architecture adapters feed the same core. The
  Capstone-wide mapping contract lives in
  `FlowrefDecompiler/CanonicalMachine.lean`; adding a new Capstone arch upstream
  should make that exhaustive mapping fail to compile until it is classified.

## Done — production decompiler (faithful-or-refuse)

- The MVP vertical slice (bytes → compilable C, return provably equal, or refuse):
  decode → CFG/reaching-defs/params → emit+gate → `flowref-equiv` oracle. See the
  `flowref-mvp` skill for the load-bearing core.
- Modeled & proven leaf/flag/select class is saturated (every single-block
  function in the bench proven), and compact branch-diamond select bridges are now
  strict for return-register selects and the first merge-φ value-select use. Strict
  44/60 EQUIVALENT, 0 violations, UNSAFE 60/60 compile. Modeled: ALU,
  neg/not, movzx/movsx (both signs), variable shifts,
  scaled+displaced `lea`, 1/2/3-operand `imul`, register-width aliasing (canonReg),
  cmp+cmov chains of any length, add/sub-carry (CF) cmov, test-ZF cmov, and `setcc`
  (the comparison-returning class). Flag conditions share one `condFromFlags` helper
  feeding both cmov and setcc.
- Equivalence oracle hardened. `flowref-equiv` replaced its size-biased
  `plausible` sampler with a deterministic boundary battery (sub-register/sign/
  extreme edges) + full-range random sweep. This closed a soundness blind spot that
  had passed false EQUIVALENTs for bugs only diverging at large inputs.
- ETNF normaliser restored. `flowref-etnf` is again a Lake executable backed by
  `lean_duckdb`; `./run-tests.sh` step 13 builds it, writes
  `etnf_{file,source,asm,function}.parquet`, and verifies the lossless join on the
  committed fixture.
- Self-authored benchmark: `decompile-bench/algorithms/<name>.c` plus narrow
  `decompile-bench/asm/<name>.S` branch-shape fixtures, one function per file;
  `algo-bench.sh` compiles each and runs the oracle. Decompiler output remains C,
  never inline assembly.
- Autoresearch harness. `decompile-bench/autoresearch-training-set.sh` runs a
  parallel oracle sweep (xargs -P nproc, 10s timeout) and auto-commits if SOUNDNESS=0.
  A Hermes cron and a systemd timer both fire every 5 min. The oracle default of 10s
  is intentionally short for INCOMPARABLE functions (they always time out); use 60s+
  for targeted checks when widening the faithful gate.
- Autoresearch soundness rule. A 10s oracle timeout that returns INCOMPARABLE is
  NOT proof of soundness for functions that were previously INCOMPARABLE. Any gate
  widening that moves a function from INCOMPARABLE to faithful must be validated with
  `FLOWREF_EQUIV_TIMEOUT=60` to confirm EQUIVALENT (not just non-timeout). Failure to
  do this led to a SOUNDNESS: 3 regression (see TOMBSTONES.md `isGuardedLoop5`).
- Loop infrastructure. Backward scan in `predOf`, ZF-from-arithmetic predicates
  (`shr`/`sub` etc. driving `jne`), loop-carried SSA injection at loop bottoms,
  `simpleLoopFaithful` (nB∈{2,3} do-while loops), `reverse_bits` EQUIVALENT.
  Score: 46/61 EQUIVALENT, SOUNDNESS 0.
- Oracle battery made loop-safe; same-block SSA fix; training set trimmed.
  `boundaryVals` reduced to max 257 (eliminates O(n) loop timeouts); `boundaryValsFull`
  added for non-loop leaves; random sweep capped at `IO.rand 0 257`; `rnd` 50000→200.
  Same-block reaching defs resolved before cross-block phi construction, unlocking
  `russian_mul`, `digit_count`, `isqrt`, `collatz_steps`. Oracle timeout fix unlocks
  `sum_to_n`, `factorial`, `fib_iter`. Six fixtures with unmodeled instructions
  (`count_divisors`, `ctz`, `gcd`, `pow_uint`, `is_prime`, `lcm`) removed from the
  training set. **Score: 55/55 EQUIVALENT, SOUNDNESS 0.**

## Done — durable decisions and vetoed approaches

- isqrt must use loop-invariant induction, not a capped oracle. `isqrt` is in
  `simpleLoopFaithful` (C manually verified correct) but the dynamic oracle times out
  at 10s because `isqrt(UINT_MAX)` runs ~65535 iterations. Capping the test range
  is probabilistic and violates the faithful-or-refuse contract. Correct path:
  `isqrtIter : Nat → Word → Word` recursive fold + `induction k` + `bv_omega`, as
  in the existing `addLoop_correct` template in `IL.lean`. Produces a theorem over
  all 2³² inputs. Do not modify `EquivCheck.lean`.
- DAG fuel as static loop bound. `reachingDefsB`/`resolveReachingDef` accept a
  `fuel` parameter to satisfy Lean 4's totality checker. This fuel is a proven upper
  bound on walk depth, not a heuristic. For loops whose trip count is statically
  bounded (isqrt: ≤65535 iterations), the correct Lean statement uses that bound as
  the induction bound — not as an oracle test-input cap. A theorem is universal; a
  capped oracle test is probabilistic.
- Graceful degradation vetoed. Emitting partial C with `/* unmodeled */` comments
  violates rule I0 (faithful-or-refuse). A function with silent gaps looks correct,
  compiles, and buries wrong behaviour where refusal would have surfaced it. The
  `--unsafe` flag with its explicit "NOT faithful" banner is the correct safety valve.
  See TOMBSTONES.md.
- Predicate direction rule for guarded-loop emit. ZF-based branches (`je`/`jz`):
  `predOf` = test value; branch-taken = `!predOf`. Comparison-based branches
  (`jbe`/`jae` etc.): `predOf` = taken condition. Guard emit must check branch mnemonic
  to select the right sign. Normal forward-if always uses `if (!predOf)` correctly
  because both cases produce consistent not-taken semantics that way.

## Done — formal IL track (machine-checked, `bv_decide`)

- `FlowrefDecompiler/IL.lean` — BitVec 32 SSA IL; per-construct correctness +
  render-correctness to lean-slang semantics. Covers registers, loads, stores (with
  aliasing), select/cmov, branching `if` (terminal select), bounded + symbolic loops,
  and function calls (`Stmt.call`/`CallEnv`, proved for all callees).
- `FlowrefDecompiler.IL.Complete` now stubs the intended complete canonical IL:
  width-tagged values, architectural regs/flags/temps/memory/PC state, scalar ops,
  expressions, stores, branches, calls, returns, traps, syscalls, and fences. It
  proves concrete expression reads for register/temp/flag/PC atoms plus step
  semantics for register/temp/flag assignment, byte memory stores, and branch PC
  updates; full source-ISA adapter and renderer refinement remain open.
- `FlowrefDecompiler/IL/SIMT.lean` adds a separate tinygrad-style minimal SIMT
  core: launch dimensions, work-item `Special`s, address spaces, ALU/where/load,
  structured ranges/if, guarded stores, barriers, pure intrinsics/WMMA hooks, and
  an embedding from the existing sound `SProg` fragment. It proves atom, scalar
  op, and RHS embedding correctness for ALU, global loads, and selects. It also
  proves two program-level embedding slices: `store_two` preserves read-after-write
  memory behavior, and `callDouble` preserves call semantics through the pure
  `intrinsic "call:f"`/`CallEnv` bridge. It now has a general
  `IntrinsicRefinesCallEnv` contract plus arbitrary single-step bridge theorems
  for embedded binds, global stores, and calls. It intentionally omits machine PC,
  traps, syscalls, and architectural register files.
- `FlowrefDecompiler/Lift.lean` — adapter `Flowref.Ins → SInsn → SProg`. End-to-end
  proofs (decode→IL→bv_decide) for: lock, lea-add, mem load, store/load aliasing,
  succ, umax/umin (cmp+cmov), forwarding call (`apply_f`), call composed with ALU
  (`g(x)+x`), and setcc+movzx comparison (`cmp;setb;movzx;ret → (a<b)?1:0`).
- `FlowrefDecompiler/CanonicalMachine.lean` — exhaustive `Capstone.Arch` →
  canonical-machine/IL mapping table for all 23 architectures exposed by
  lean-capstone. Every row, including x86 and PPC, is the same kind of explicit
  adapter contract into the small IL; production maturity is not encoded as a
  privileged architecture class.
- **lean-slang** (`V-Sekai-fire/lean-slang`, owned): Slang AST + BitVec semantics +
  libslang FFI (in-process SPIR-V via `dlmopen`); `slangcheck` compiles all fixtures
  end-to-end. `LeanSlang.SIMT` proves data-parallel kernel correctness = per-thread
  body (`evalU32`) ∘ race-free non-interference.

## Done — scalar division and the 64-bit reciprocal-multiply idiom (Gaps 1 & 2)

- Gap 1 (guarded scalar division) closed. A `test r,r; je` (or `cmp r,0; je`)
  guard that reaches a `div`/`idiv` proves the divisor is nonzero on the division
  path; the faithful gate (`divsModeled`) accepts the division and the emitter
  spells ordinary C `/`. `div_guarded` is in the training set and EQUIVALENT under
  the full (60s) oracle — the guarded `if (!((a1 & a1) == 0)) { … a/b … }` shape.
- Gap 2 (64-bit magic-constant division) closed soundly by **operand widening**,
  not a divisor recognizer. The compiler lowers `x / 10` to `imul r64, 0xcccccccd;
  shr r64, 35`. The 64-bit `imul` computes the full 128→64-bit product, but the
  shared `rhsText` emitted `d * s` with `uint32_t`-typed SSA operands, so C did a
  32-bit multiply and dropped the high half — wrong, and previously accepted as
  "faithful" (a NOT-EQUIVALENT soundness hole on `div_by_10`). `renderExprC` now
  widens a 2-operand `imul` whose destination is a 64-bit register to
  `(uint64_t)(d) * (uint64_t)(s)`, faithful to `imul r64` (32-bit SSA reads
  zero-extend, matching x86 zero-extension of 32-bit writes). `div_by_10` is in the
  training set and EQUIVALENT under the full oracle. The readable `x / 10` surface
  form is deferred; the closure signal (strict, no unsafe banner, EQUIVALENT) is met.
- Build restored. A 19-Jun run of autoresearch "69/69" commits had committed source
  that never compiled (the original broken Gap-2 attempt + a type-broken Gap-1
  path-fact change in `Lift.lean`), because the harness scored a stale prebuilt
  binary. Reverted/repaired; `autoresearch-training-set.sh` now builds-or-aborts
  before measuring so non-compiling source can never be committed. See TOMBSTONES.md.

## Done — fixed soundness/correctness bugs (each caught by the bench/oracle)

- cmp+cmov leaf silently mis-lifted under a "faithful" banner → gate whitelists
  modeled mnemonics.
- `readelf -s` Size is decimal (was read as hex) → harness over-read functions.
- `neg`/`not` not in the dep's `writesReg` → mis-lifted; modeled as SSA defs.
- Multi-cmov / register-width aliasing (`lea (%rdx,%rdi)` after `add %esi,%edx`) →
  wrong SSA; fixed with cmov-aware single-block reaching-def + canonReg.
- Oracle sampler blind spot (above) → boundary battery.
- `movzx`/`movsx` of a sub-register lifted as a plain copy (dropped truncation/sign)
  → modeled by source width.
- Tiny x86 branch targets printed as bare decimal digits (`jb 9`) were invisible to
  the dependency's `branchTarget`, so compact diamonds were mis-carved as straight
  blocks. `btX`/`cbtX` now parse the bare-digit case for CFG recovery, and the
  first branch→select strict bridge lowers a three-block return diamond to a ternary.
- x86 branch predicates now distinguish signed (`jl`/`jle`/`jg`/`jge`) from
  unsigned (`jb`/`jbe`/`ja`/`jae`) comparisons when emitting C predicates.
- Merge φ uses in a compact branch diamond now lower to an explicit ternary when
  both branch-arm definitions are matched to the reaching-def witness set; φ-arm
  SSA values are kept in outer scope so generated C remains compilable.
- Compact branch-diamond merge φ values can now be consumed more than once in the
  merge block. `branch_phi_twouse` proves both uses of the same selected register
  lower to the same ternary instead of reusing one branch arm's SSA local.
