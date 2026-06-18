# CHANGELOG — completed work, decisions, durable rules

State that is **done and verified** lives here. Unfinished work → `OPEN_GAPS.md`;
dead ends → `TOMBSTONES.md`. Each fact lives in exactly one of the three.

## Durable project rules (do not break)

- **Faithful-or-refuse (I0).** Strict mode emits C only for the modeled class; any
  unmodeled instruction ⇒ refuse (hard error, nothing on stdout). Widen the gate
  ONLY after the equivalence oracle proves the new lift EQUIVALENT. `algo-bench.sh`
  must always report `SOUNDNESS: 0`.
- **Verify + commit discipline.** Every change is checked with `lake build
  flowref-decompiler` AND `./decompile-bench/algo-bench.sh` (SOUNDNESS 0); commit
  each green step.
- **Build Lean tools, not CLIs.** lean-slang compiles to SPIR-V in-process via a
  libslang FFI, never the `slangc` CLI.
- **No `objdump`.** It is denied in `.claude/settings.json`. Use flowref's own
  disassembler or `gcc -S`.
- **Generated C contains no inline assembly.** Assembly fixtures may exist only as
  binary-side inputs for shape coverage; flowref's converted C output must stay
  portable C, not `asm`.
- **CFG recovery reuses the plausible witness DAG.** Do not write new dataflow/CFG
  analysis — reuse `reachingDefsB`/`resolveReachingDef`/`certifyReaching`,
  `condBlocks`, `predOf`, and the plausible back-edge check. It works and is fast.
- **Minimal executable machine first.** Follow the tinygrad-style insight: encode
  executable semantics through a small canonical machine/IL, not by solving every
  architecture independently. Architecture adapters feed the same core. The
  Capstone-wide mapping contract lives in
  `FlowrefDecompiler/CanonicalMachine.lean`; adding a new Capstone arch upstream
  should make that exhaustive mapping fail to compile until it is classified.

## Done — production decompiler (faithful-or-refuse)

- The MVP vertical slice (bytes → compilable C, return provably equal, or refuse):
  decode → CFG/reaching-defs/params → emit+gate → `flowref-equiv` oracle. See the
  `flowref-mvp` skill for the load-bearing core.
- **Modeled & proven leaf/flag/select class is saturated** (every single-block
  function in the bench proven), and compact branch-diamond select bridges are now
  strict for return-register selects and the first merge-φ value-select use. Strict
  **44/60 EQUIVALENT, 0 violations**, UNSAFE 60/60 compile. Modeled: ALU,
  neg/not, movzx/movsx (both signs), variable shifts,
  scaled+displaced `lea`, 1/2/3-operand `imul`, register-width aliasing (canonReg),
  cmp+cmov chains of any length, add/sub-carry (CF) cmov, test-ZF cmov, and `setcc`
  (the comparison-returning class). Flag conditions share one `condFromFlags` helper
  feeding both cmov and setcc.
- **Equivalence oracle hardened.** `flowref-equiv` replaced its size-biased
  `plausible` sampler with a deterministic boundary battery (sub-register/sign/
  extreme edges) + full-range random sweep. This closed a soundness blind spot that
  had passed false EQUIVALENTs for bugs only diverging at large inputs.
- **ETNF normaliser restored.** `flowref-etnf` is again a Lake executable backed by
  `lean_duckdb`; `./run-tests.sh` step 13 builds it, writes
  `etnf_{file,source,asm,function}.parquet`, and verifies the lossless join on the
  committed fixture.
- Self-authored benchmark: `decompile-bench/algorithms/<name>.c` plus narrow
  `decompile-bench/asm/<name>.S` branch-shape fixtures, one function per file;
  `algo-bench.sh` compiles each and runs the oracle. Decompiler output remains C,
  never inline assembly.

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
