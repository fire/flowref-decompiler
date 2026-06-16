/-!
# `Capstone` — Lean bindings to the Capstone disassembler

A small, generic binding to the Capstone disassembly engine (BSD-3),
vendored under `thirdparty/capstone` and linked into executables;
`ffi/capstone_shim.c` exposes a single primitive. This module wraps it in
a typed API: disassemble a `ByteArray` for a chosen architecture into
`Insn` records `(address, mnemonic, ops)`. Any structuring or analysis on
top is left to the caller.
-/

namespace Capstone

/-- Every architecture the engine supports (values match the underlying
`cs_arch`; the vendored build enables all of them). Exhaustive. -/
inductive Arch
  | arm           -- ARM (incl. Thumb / Thumb-2)
  | aarch64       -- ARM64 / AArch64
  | systemz       -- SystemZ
  | mips
  | x86           -- x86 & x86-64 (select width via `Mode`)
  | ppc           -- PowerPC (select width/endian via `Mode`)
  | sparc
  | xcore
  | m68k          -- Motorola 680x0
  | tms320c64x
  | m680x         -- Motorola 680x
  | evm           -- Ethereum VM
  | mos65xx       -- MOS 65xx (incl. 6502)
  | wasm          -- WebAssembly
  | bpf           -- (e)BPF
  | riscv
  | sh            -- SuperH
  | tricore
  | alpha
  | hppa          -- PA-RISC
  | loongarch
  | xtensa
  | arc
  deriving Repr, DecidableEq, Inhabited

/-- `cs_arch` numeric code. -/
def Arch.code : Arch → UInt32
  | .arm => 0  | .aarch64 => 1 | .systemz => 2  | .mips => 3 | .x86 => 4
  | .ppc => 5  | .sparc => 6   | .xcore => 7    | .m68k => 8 | .tms320c64x => 9
  | .m680x => 10 | .evm => 11  | .mos65xx => 12 | .wasm => 13 | .bpf => 14
  | .riscv => 15 | .sh => 16   | .tricore => 17 | .alpha => 18 | .hppa => 19
  | .loongarch => 20 | .xtensa => 21 | .arc => 22

/-- Disassembly mode as a raw `cs_mode` bitmask. Common bits are named below;
combine with `|||`, and use `Mode.raw` for any arch-specific mode bit. Note
some bits alias across architectures (inherent to `cs_mode`). -/
structure Mode where
  bits : UInt32 := 0
  deriving Repr, DecidableEq, Inhabited

namespace Mode
instance : OrOp Mode := ⟨fun a b => ⟨a.bits ||| b.bits⟩⟩
/-- Any raw `cs_mode` value (for arch-specific bits not named here). -/
def raw (n : UInt32) : Mode := ⟨n⟩
def littleEndian : Mode := ⟨0⟩
def bigEndian    : Mode := ⟨(1 : UInt32) <<< 31⟩
def b16   : Mode := ⟨(1 : UInt32) <<< 1⟩   -- 16-bit (x86); MIPS16
def b32   : Mode := ⟨(1 : UInt32) <<< 2⟩   -- 32-bit (x86); MIPS32
def b64   : Mode := ⟨(1 : UInt32) <<< 3⟩   -- 64-bit (x86, PPC); MIPS64
def thumb : Mode := ⟨(1 : UInt32) <<< 4⟩   -- ARM Thumb
def mclass : Mode := ⟨(1 : UInt32) <<< 5⟩  -- ARM Cortex-M
def v8    : Mode := ⟨(1 : UInt32) <<< 6⟩   -- ARMv8 A32
def micro : Mode := ⟨(1 : UInt32) <<< 4⟩   -- microMIPS
def v9    : Mode := ⟨(1 : UInt32) <<< 4⟩   -- SPARC V9
def riscv32 : Mode := ⟨(1 : UInt32) <<< 0⟩
def riscv64 : Mode := ⟨(1 : UInt32) <<< 1⟩
end Mode

/-- One disassembled instruction. -/
structure Insn where
  addr     : Nat
  mnemonic : String
  ops      : String
  deriving Repr, Inhabited

/-- FFI: disassemble `code` at base `addr` for `(archCode, modeBits)`,
returning a TSV listing ("addrHex\tmnemonic\tops\n" per instruction). Empty on
a Capstone error. -/
@[extern "lean_capstone_disasm"]
opaque disasmRaw (archCode modeBits : UInt32) (code : ByteArray) (addr : UInt64) : String

/-- Disassemble `code` (base address `addr`) for `arch`/`mode` into `Insn`s. -/
def disasm (arch : Arch) (mode : Mode := {}) (code : ByteArray) (addr : Nat := 0) :
    Array Insn := Id.run do
  let tsv := disasmRaw arch.code mode.bits code addr.toUInt64
  let mut out : Array Insn := #[]
  for line in tsv.splitOn "\n" do
    if line.isEmpty then continue
    match line.splitOn "\t" with
    | [a, m, o] =>
      let addr := (a.foldl (fun n c =>
        let d := if '0' ≤ c ∧ c ≤ '9' then c.toNat - '0'.toNat
                 else if 'a' ≤ c ∧ c ≤ 'f' then c.toNat - 'a'.toNat + 10 else 0
        n * 16 + d) 0)
      out := out.push { addr, mnemonic := m, ops := o }
    | _ => pure ()
  pure out

end Capstone
