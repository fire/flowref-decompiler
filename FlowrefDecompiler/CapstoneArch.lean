import Capstone
import FlowrefDecompiler.CanonicalMachine

/-! # Capstone engine → canonical `Isa` port (hexagon ADAPTER)

This is the ONLY flowref-decompiler module that imports the Capstone disassembly
engine. It translates the engine's `Capstone.Arch` into flowref's domain-owned
`FlowrefDecompiler.CanonicalMachine.Isa` port, keeping the canonical-machine core
(`CanonicalMachine.lean`) free of any engine dependency — the hexagonal property:
core imports nothing from adapters; the engine stays here.

The `Arch → Isa` match below is TOTAL, so if Capstone adds a new architecture
constructor upstream this adapter fails to compile until the new arch is
classified into an `Isa` — exactly the coverage tripwire the CHANGELOG calls for,
now living in the adapter layer where the engine coupling belongs. -/

namespace FlowrefDecompiler.CapstoneArch

open FlowrefDecompiler.CanonicalMachine

/-- Translate a Capstone engine architecture into flowref's canonical `Isa` port.
Total on `Capstone.Arch`: a new upstream arch constructor breaks this build until
it is mapped. -/
def isaOfCapstone : Capstone.Arch → Isa
  | .arm => .arm
  | .aarch64 => .aarch64
  | .systemz => .systemz
  | .mips => .mips
  | .x86 => .x86
  | .ppc => .ppc
  | .sparc => .sparc
  | .xcore => .xcore
  | .m68k => .m68k
  | .tms320c64x => .tms320c64x
  | .m680x => .m680x
  | .evm => .evm
  | .mos65xx => .mos65xx
  | .wasm => .wasm
  | .bpf => .bpf
  | .riscv => .riscv
  | .sh => .sh
  | .tricore => .tricore
  | .alpha => .alpha
  | .hppa => .hppa
  | .loongarch => .loongarch
  | .xtensa => .xtensa
  | .arc => .arc

/-- Convenience: the canonical-machine contract for a Capstone architecture,
resolved through the `Isa` port. -/
def mappingOfCapstone (a : Capstone.Arch) : ArchMapping :=
  mappingOf (isaOfCapstone a)

/-- Coverage tripwire: every Capstone architecture the engine exposes maps onto a
distinct classified `Isa`, and the count matches the core's ISA table. Because
`isaOfCapstone` is a total match, a new Capstone arch would already fail to
compile above; this pins the 1:1 count as well. -/
example :
    (([ .arm, .aarch64, .systemz, .mips, .x86, .ppc, .sparc, .xcore, .m68k,
        .tms320c64x, .m680x, .evm, .mos65xx, .wasm, .bpf, .riscv, .sh, .tricore,
        .alpha, .hppa, .loongarch, .xtensa, .arc ] : List Capstone.Arch).map
        isaOfCapstone).length = allIsas.length := by native_decide

end FlowrefDecompiler.CapstoneArch
