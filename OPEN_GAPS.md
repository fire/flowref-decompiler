# OPEN_GAPS — unfinished work, open problems (present tense)

Each item names the next decisive action when known. Completed items move to
`CHANGELOG.md`; abandoned approaches move to `TOMBSTONES.md`.

## Reranked priorities (2026-06-17)

The leaf/flag/select/forwarding-call class is saturated, so the old "raise strict
count on leaves" is essentially exhausted. Real benchmark coverage now comes from
shipping memory, calls, and then broader control flow. Proof-generalization work
continues in parallel but should not outrank production coverage unless it blocks
soundness. Current order, highest first:

1. **Single-block memory in production.** Loads/stores for register+memory leaves.
   The IL already proves load/store/aliasing on real bytes; no CFG work needed —
   likely the fastest real-class win. Production `emitC` currently refuses any
   non-`lea` memory operand (`hasMemOp`).

2. **General calls (combine, not just forward).** ~87% of real functions call
   something. The IL proves `callDouble`; lift `call; <combine result with ALU>`
   from real multi-instruction sequences. The production emitter refuses calls.

3. **Broaden branch→select lifting beyond compact diamonds.**
   Strict bridges are done for compact 3-block forward branch diamonds that select
   the return register (`branch_select`, signed and unsigned predicates) and for
   merge-φ values consumed multiple times in the merge block (`branch_phi_add`,
   `branch_phi_twouse`). The next gateway is diamonds whose branch arms compute
   more than one live selected value.
   **Next decisive action:** add the smallest fixture where both branch arms define
   two live registers, prove both selected values lower without scope leaks, then
   widen the faithful gate only after the oracle proves it.

4. **Canonical-machine adapters for every Capstone arch.** The mapping contract
    now names all Capstone architectures in `FlowrefDecompiler/CanonicalMachine.lean`.
    Every row, including x86 and PPC, is an explicit adapter contract into the
    same small IL: lower register, immediate, memory, branch, call, and ABI facts
    into the canonical machine instead of growing per-architecture decompilers.

5. **Prove complete-IL source/refinement/render semantics.**
    `FlowrefDecompiler.IL.Complete` now names the full target machine shape
    (regs/flags/memory/PC, scalar ops, branches, calls, traps, syscalls, fences)
    and proves concrete expression reads for register/temp/flag/PC atoms plus
    step semantics for register/temp/flag assignment, byte memory stores, and
    branch PC updates. Replace placeholder `Nat` bits with width-indexed `BitVec`, then
    prove real source-ISA adapter semantics, an embedding from the existing sound
    `SProg` fragment, and complete renderer correctness.

6. **Finish general SIMT program-level embedding.**
   `FlowrefDecompiler/IL/SIMT.lean` is the tinygrad-style minimal kernel core,
   separate from machine IL. Atom, scalar-op, and RHS embedding correctness are
   proved for ALU, global loads, and selects. Program-level slices now prove the
   embedded `store_two` read-after-write fixture and `callDouble` via
   `intrinsic "call:f"` agree with existing `SProg.eval`; arbitrary single calls
   now have an `IntrinsicRefinesCallEnv` bridge. Next, generalize the fixture
   proofs into a statement-list simulation over arbitrary stores, calls, and
   temporary slots, then prove `fromSoundSProg` preserves existing `SProg.eval`
   before adding backend renderers for `Special`, `barrier`, guarded stores, and
   WMMA/intrinsics.

7. **Loops** (gcd/is_prime/factorial/…). Biggest single corpus unlock, hardest
   (CFG structuring + invariant synthesis). Start with provably-bounded unrolling;
   defer general induction-from-bytes. Currently refused (multi-block).

8. **Harden/broaden leaves + oracle** — opportunistic background; diminishing but
   still occasionally finds bugs.

9. **`slangcheck`** — periodic health check (every few ticks): in `/tmp/lean-slang`
   ensure the vendor SDK (`vendor/fetch.sh` if `libslang.so` missing), pull if main
   moved, run `lake exe slangcheck`.

## Honest coverage gap

Faithful straight-line leaves are only ~4–13% of real Decompile-Bench functions
(register/memory-only, call-free). The formal IL *proves* loops, branches, and
calls, but the **lifter from real bytes** only handles straight-line + flag +
forwarding-call — wiring branch/loop CFG recovery end-to-end is the major remaining
engineering. "General-purpose faithful decompiler" is ~25–35% complete; the
straight-line slice is ~90%.

## Known latent caveats

- `whileLoopShader` in lean-slang `slangcheck` emits 168 bytes (== trivial shader):
  the loop body is dead-code-eliminated (no output buffer). Give it a side-effecting
  body so the SPIR-V actually exercises loop codegen.
- Variable-shift lifts (`a0 >> a1`, unmasked) are UB-reliant in C but recompile to
  the same count-masking `shr cl` as the binary — sound under the oracle's
  compiled-candidate-vs-binary contract, but a portability caveat for other
  toolchains.
