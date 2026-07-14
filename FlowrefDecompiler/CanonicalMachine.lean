import FlowrefDecompiler.IL

/-! # Canonical machine/IL ISA mapping (hexagon CORE)

flowref follows the tinygrad-style rule captured in `CHANGELOG.md`: do not build
one decompiler per ISA. Every target architecture maps into the same small
canonical executable machine:

* 32-bit two's-complement words (`FlowrefDecompiler.IL.Word`) for the current
  proven core;
* SSA bindings over the canonical `FlowrefDecompiler.IL.Op` set;
* explicit memory loads/stores and explicit calls at the IL boundary;
* thin ISA adapters that only decode registers, immediates, memory operands,
  branches, and calling-convention facts into that core.

This module is the domain-owned, **dependency-free** source-of-truth coverage
table (hexagon core): it imports no disassembly engine. The architecture identity
it is keyed on is flowref's OWN `Isa` port type, not Capstone's `Arch` — the
`Capstone.Arch → Isa` translation and the "every Capstone architecture is
classified" exhaustiveness check live in the adapter
`FlowrefDecompiler.CapstoneArch` (which is the only place that imports Capstone).
That keeps the hexagonal property intact: core imports nothing from adapters;
the engine stays in the adapter. x86 and PowerPC are not special in this table:
they are simply two contracts whose production implementations happen to be
furthest along today.
-/

namespace FlowrefDecompiler.CanonicalMachine

/-- flowref's own architecture-identity port. Deliberately mirrors the set of
Capstone architectures, but is domain-owned so the canonical-machine core does
not depend on the disassembly engine (see `FlowrefDecompiler.CapstoneArch` for
the engine ↔ port adapter). -/
inductive Isa
  | arm | aarch64 | systemz | mips | x86 | ppc | sparc | xcore | m68k
  | tms320c64x | m680x | evm | mos65xx | wasm | bpf | riscv | sh | tricore
  | alpha | hppa | loongarch | xtensa | arc
  deriving Repr, DecidableEq

/-- All architectures get the same status here: an explicit contract to lower
into the canonical IL. Implementation maturity belongs in changelog/open gaps,
not in the mapping type, so no ISA receives a privileged constructor. -/
inductive AdapterContract
  | explicit
  deriving Repr, DecidableEq

/-- Canonical-machine contract for one architecture, keyed on the domain `Isa`. -/
structure ArchMapping where
  isa : Isa
  names : List String
  wordBits : List Nat
  endian : List String
  pc : Option String
  sp : Option String
  returnRegs : List String
  argRegs : List String
  contract : AdapterContract
  note : String
  deriving Repr

/-- The current proven machine word. Wider/narrower ISAs are projected through
adapter-level truncation/extension until the IL grows a width parameter. -/
def canonicalWordBits : Nat := 32

/-- Exhaustive mapping from every `Isa` constructor to the small canonical
machine/IL contract. Pattern matching makes a missing future `Isa` a Lean
compile error. -/
def mappingOf : Isa → ArchMapping
  | .arm => {
      isa := .arm, names := ["arm", "arm32", "thumb", "thumb2"],
      wordBits := [32], endian := ["little", "big"], pc := some "pc", sp := some "sp",
      returnRegs := ["r0"], argRegs := ["r0", "r1", "r2", "r3"],
      contract := .explicit,
      note := "Lower ARM/Thumb register ALU, load/store, branch-link, and condition flags into the canonical SSA IL." }
  | .aarch64 => {
      isa := .aarch64, names := ["aarch64", "arm64"],
      wordBits := [32, 64], endian := ["little", "big"], pc := none, sp := some "sp",
      returnRegs := ["x0", "w0"], argRegs := ["x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7"],
      contract := .explicit,
      note := "Lower X/W register aliases and condition-code selects into canonical 32-bit SSA projections." }
  | .systemz => {
      isa := .systemz, names := ["systemz", "s390x"],
      wordBits := [32, 64], endian := ["big"], pc := none, sp := some "r15",
      returnRegs := ["r2"], argRegs := ["r2", "r3", "r4", "r5", "r6"],
      contract := .explicit,
      note := "Map general registers, storage operands, and branch-on-condition to canonical ALU/load/store/select." }
  | .mips => {
      isa := .mips, names := ["mips", "mips32", "mips64"],
      wordBits := [32, 64], endian := ["little", "big"], pc := some "pc", sp := some "sp",
      returnRegs := ["v0"], argRegs := ["a0", "a1", "a2", "a3"],
      contract := .explicit,
      note := "Lower delay-slot-normalized MIPS operations to canonical SSA after the adapter linearizes branch delay semantics." }
  | .x86 => {
      isa := .x86, names := ["x16", "x86", "x64"],
      wordBits := [16, 32, 64], endian := ["little"], pc := some "rip", sp := some "rsp",
      returnRegs := ["eax", "rax"], argRegs := ["edi", "esi", "edx", "ecx", "r8d", "r9d"],
      contract := .explicit,
      note := "Canonicalize subregister aliases, ALU, flags, cmov/setcc, compact branch-selects, calls, and memory subsets into the shared IL contract." }
  | .ppc => {
      isa := .ppc, names := ["ppc", "ppc64", "ppc64le"],
      wordBits := [32, 64], endian := ["little", "big"], pc := none, sp := some "r1",
      returnRegs := ["r3"], argRegs := ["r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10"],
      contract := .explicit,
      note := "Map PPC ELF/TOC facts, GPR ops, and CR branches into canonical SSA/select form under the same shared IL contract." }
  | .sparc => {
      isa := .sparc, names := ["sparc", "sparc64", "sparcv9"],
      wordBits := [32, 64], endian := ["big"], pc := some "pc", sp := some "sp",
      returnRegs := ["o0"], argRegs := ["o0", "o1", "o2", "o3", "o4", "o5"],
      contract := .explicit,
      note := "Adapter must flatten register-window naming to canonical logical argument/return registers before IL lowering." }
  | .xcore => {
      isa := .xcore, names := ["xcore"],
      wordBits := [32], endian := ["big"], pc := some "pc", sp := some "sp",
      returnRegs := ["r0"], argRegs := ["r0", "r1", "r2", "r3"],
      contract := .explicit,
      note := "Map scalar register ops and memory references to the canonical 32-bit machine." }
  | .m68k => {
      isa := .m68k, names := ["m68k", "68k"],
      wordBits := [16, 32], endian := ["big"], pc := some "pc", sp := some "sp",
      returnRegs := ["d0"], argRegs := ["d0", "d1", "a0", "a1"],
      contract := .explicit,
      note := "Lower data/address register operands and condition-code branches to canonical SSA/select." }
  | .tms320c64x => {
      isa := .tms320c64x, names := ["tms320c64x", "c64x"],
      wordBits := [32], endian := ["big"], pc := none, sp := some "b15",
      returnRegs := ["a4"], argRegs := ["a4", "b4", "a6", "b6", "a8", "b8"],
      contract := .explicit,
      note := "Map DSP A/B register-file operations to the same canonical ALU/load/store core." }
  | .m680x => {
      isa := .m680x, names := ["m680x"],
      wordBits := [8, 16], endian := ["big"], pc := some "pc", sp := some "sp",
      returnRegs := ["a", "d"], argRegs := [],
      contract := .explicit,
      note := "Zero/sign-extend accumulator/index-register operations into canonical 32-bit words at the adapter boundary." }
  | .evm => {
      isa := .evm, names := ["evm"],
      wordBits := [256], endian := ["big"], pc := some "pc", sp := none,
      returnRegs := ["stack0"], argRegs := [],
      contract := .explicit,
      note := "Stack-machine adapter should name stack slots explicitly, then project supported word operations into canonical IL." }
  | .mos65xx => {
      isa := .mos65xx, names := ["mos65xx", "6502", "65xx"],
      wordBits := [8, 16], endian := ["little"], pc := some "pc", sp := some "sp",
      returnRegs := ["a"], argRegs := [],
      contract := .explicit,
      note := "Lift accumulator/index-register effects by widening byte operations into canonical 32-bit words." }
  | .wasm => {
      isa := .wasm, names := ["wasm"],
      wordBits := [32, 64], endian := ["little"], pc := none, sp := none,
      returnRegs := ["stack0"], argRegs := [],
      contract := .explicit,
      note := "Map Wasm stack values to named SSA stack slots; supported i32 ops lower directly to canonical IL." }
  | .bpf => {
      isa := .bpf, names := ["bpf", "ebpf"],
      wordBits := [32, 64], endian := ["little"], pc := some "pc", sp := some "r10",
      returnRegs := ["r0"], argRegs := ["r1", "r2", "r3", "r4", "r5"],
      contract := .explicit,
      note := "eBPF's small register machine is already close to the canonical ALU/load/store/call IL." }
  | .riscv => {
      isa := .riscv, names := ["riscv", "riscv32", "riscv64"],
      wordBits := [32, 64], endian := ["little"], pc := some "pc", sp := some "sp",
      returnRegs := ["a0"], argRegs := ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"],
      contract := .explicit,
      note := "RISC-V register ALU/load/store/branch forms map directly to canonical SSA plus explicit select/branch nodes." }
  | .sh => {
      isa := .sh, names := ["sh", "superh"],
      wordBits := [32], endian := ["big"], pc := some "pc", sp := some "r15",
      returnRegs := ["r0"], argRegs := ["r4", "r5", "r6", "r7"],
      contract := .explicit,
      note := "Lower T-bit comparisons and delayed branches after adapter normalization." }
  | .tricore => {
      isa := .tricore, names := ["tricore"],
      wordBits := [32], endian := ["little"], pc := some "pc", sp := some "a10",
      returnRegs := ["d2"], argRegs := ["d4", "d5", "d6", "d7", "a4", "a5", "a6", "a7"],
      contract := .explicit,
      note := "Map data/address register classes to canonical registers with explicit load/store boundary nodes." }
  | .alpha => {
      isa := .alpha, names := ["alpha"],
      wordBits := [64], endian := ["little"], pc := some "pc", sp := some "sp",
      returnRegs := ["v0"], argRegs := ["a0", "a1", "a2", "a3", "a4", "a5"],
      contract := .explicit,
      note := "Lower Alpha's regular load/store register machine into canonical SSA projections." }
  | .hppa => {
      isa := .hppa, names := ["hppa", "parisc"],
      wordBits := [32, 64], endian := ["big"], pc := some "iaoq", sp := some "r30",
      returnRegs := ["r28"], argRegs := ["r26", "r25", "r24", "r23"],
      contract := .explicit,
      note := "Map PA-RISC general registers and branch predicates to canonical ALU/select after delay-slot normalization." }
  | .loongarch => {
      isa := .loongarch, names := ["loongarch", "loongarch64", "la64"],
      wordBits := [32, 64], endian := ["little"], pc := some "pc", sp := some "sp",
      returnRegs := ["a0"], argRegs := ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"],
      contract := .explicit,
      note := "LoongArch follows the canonical load/store register-machine path similar to RISC-V." }
  | .xtensa => {
      isa := .xtensa, names := ["xtensa"],
      wordBits := [32], endian := ["little"], pc := some "pc", sp := some "a1",
      returnRegs := ["a2"], argRegs := ["a2", "a3", "a4", "a5", "a6", "a7"],
      contract := .explicit,
      note := "Map windowed-register logical names to stable canonical registers before SSA lowering." }
  | .arc => {
      isa := .arc, names := ["arc"],
      wordBits := [32], endian := ["little"], pc := some "pc", sp := some "sp",
      returnRegs := ["r0"], argRegs := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7"],
      contract := .explicit,
      note := "ARC register ALU/load/store/branch effects lower to the canonical 32-bit machine." }

/-- Every `Isa`, in constructor order. -/
def allIsas : List Isa :=
  [ .arm, .aarch64, .systemz, .mips, .x86, .ppc, .sparc, .xcore, .m68k,
    .tms320c64x, .m680x, .evm, .mos65xx, .wasm, .bpf, .riscv, .sh, .tricore,
    .alpha, .hppa, .loongarch, .xtensa, .arc ]

/-- One row per `Isa`, in constructor order. -/
def allMappings : List ArchMapping := allIsas.map mappingOf

/-- Quick sanity check used by review/tests: flowref's canonical machine
classifies 23 ISAs and every one has a mapping row above. -/
example : allMappings.length = 23 := by native_decide

end FlowrefDecompiler.CanonicalMachine
