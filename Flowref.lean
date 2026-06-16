import Capstone
import Plausible

/-! # flowref — control-flow-aware cross-reference search over disassembly

A linear disassembler tells you the instructions; it does *not* tell you where
a particular constant or address is **used**, because the value is often built
in one basic block and consumed in another. `flowref` recovers that link.

**The idea (a "witness DAG", not a linear scan).** A *def* materialises a
constant base `B` into a register `R` at some instruction `i`. A *use* at `j`
combines `R + disp` and equals the target. The two are connected by a
control-flow path `i → … → j` along which `R` is never clobbered — that path is
the *witness*. We pose the search as a property and let `plausible` find a
counterexample: state `∀ def-witness, ¬(it reaches a target-hitting use)`; a
counterexample is exactly a witness DAG that locates the cross-block reference.

This catches the case a linear constant-propagation pass misses: a base set in
block A and used in block B reachable from A. The disassembly comes from
Capstone, so the same engine works on every architecture Capstone supports
(x86 and PowerPC are wired up below; others are a few lines each).

Run:
```
flowref <binary> <arch> <targetHex> <fileOffHex> <vaddrHex> <lenHex>
```
- `arch` ∈ {`x86`, `ppc`} (default `x86`)
- `targetHex` the address/constant to find references to
- the region `[fileOff, fileOff+len)` of `<binary>` is disassembled starting at
  virtual address `vaddr` (so file offset and load address can differ).
-/

open Capstone Plausible

/-- Parse a hex (`0x…`) or decimal integer, optionally signed. -/
def parseImm (s0 : String) : Int :=
  let s := s0.trimAscii.toString
  let (neg, t) := if s.startsWith "-" then (true, (s.drop 1).toString) else (false, s)
  let t := if t.startsWith "0x" then (t.drop 2).toString else t
  let v : Int := t.toList.foldl (fun n c =>
    if '0' ≤ c ∧ c ≤ '9' then n*16 + (c.toNat - '0'.toNat)
    else if 'a' ≤ c ∧ c ≤ 'f' then n*16 + (c.toNat - 'a'.toNat + 10)
    else if 'A' ≤ c ∧ c ≤ 'F' then n*16 + (c.toNat - 'A'.toNat + 10) else n) 0
  if neg then -v else v

/-- A decoded instruction, reduced to what the data-flow walk needs. -/
structure Ins where
  addr : Nat
  mn   : String
  ops  : String
  deriving Inhabited

/-- Supported architectures. Each adds a handful of per-arch patterns below. -/
inductive A | x86 | ppc deriving DecidableEq

/-- A *def*: an instruction that materialises a constant into a register.
x86 `mov REG,imm`; PowerPC `lis REG,imm` (`=imm<<16`) or `li REG,imm`. -/
def defOf (a : A) (i : Ins) : Option (String × Int) :=
  let toks := (i.ops.splitOn ",").map (·.trimAscii.toString)
  match a with
  | .x86 => if i.mn == "mov" then match toks with
      | [d, s] => if (s.startsWith "0x" ∨ s.startsWith "-") ∧ ¬ d.any (· == '[') then some (d, parseImm s) else none
      | _ => none else none
  | .ppc => match i.mn, toks with
      | "lis", [d, im] => some (d, parseImm im * 0x10000)
      | "li",  [d, im] => some (d, parseImm im)
      | _, _ => none

/-- Does this instruction overwrite register `r`? Conservative: a write whose
first operand is `r` (excluding compares / branches / stores). -/
def clobbers (a : A) (i : Ins) (r : String) : Bool :=
  let d := ((i.ops.splitOn ",").headD "").trimAscii.toString
  match a with
  | .x86 => d == r ∧ i.mn != "cmp" ∧ i.mn != "test"
  | .ppc => d == r ∧ ¬ i.mn.startsWith "cmp" ∧ ¬ i.mn.startsWith "st" ∧ ¬ i.mn.startsWith "b"

/-- A *use* of base `r` with a displacement. x86 `[r+disp]` (any memory
operand); PowerPC `disp(r)` loads/stores and `addi rD,r,disp`. -/
def useDisp (a : A) (i : Ins) (r : String) : Option Int :=
  match a with
  | .x86 =>
    (i.ops.splitOn "[").drop 1 |>.foldl (fun acc piece =>
      match acc with
      | some _ => acc
      | none =>
        let inner := (piece.splitOn "]").headD ""
        match (inner.splitOn "+").map (·.trimAscii.toString) with
        | [a] => if a == r then some 0 else none
        | [a, b] => if a == r then some (parseImm b) else none
        | _ => none) none
  | .ppc =>
    if i.mn == "addi" ∨ i.mn == "addic" then
      match (i.ops.splitOn ",").map (·.trimAscii.toString) with
      | [_, rb, im] => if rb == r then some (parseImm im) else none
      | _ => none
    else
      match i.ops.splitOn "(" with
      | _ :: rest :: _ =>
        let rb := (rest.splitOn ")").headD "" |>.trimAscii.toString
        if rb == r then
          let ds := ((i.ops.splitOn "(").headD "").splitOn "," |>.getLastD "" |>.trimAscii.toString
          some (if ds.isEmpty then 0 else parseImm ds)
        else none
      | _ => none

/-- Branch / call target (hex) of an instruction, if it has one. -/
def branchTarget (a : A) (i : Ins) : Option Nat :=
  let last := (i.ops.splitOn ",").getLastD "" |>.trimAscii.toString
  match a with
  | .x86 => if i.mn.startsWith "j" ∨ i.mn == "call" ∨ i.mn == "loop" then
      (if (i.ops.trimAscii.toString).startsWith "0x" then some (parseImm i.ops).toNat else none) else none
  | .ppc => if i.mn.startsWith "b" then (if last.startsWith "0x" then some (parseImm last).toNat else none) else none

/-- Does control fall through past this instruction, or does it terminate /
unconditionally transfer? -/
def isUncondJmp (a : A) (i : Ins) : Bool :=
  match a with
  | .x86 => i.mn == "jmp" ∨ i.mn.startsWith "ret"
  | .ppc => i.mn == "b" ∨ i.mn == "blr" ∨ i.mn == "bctr" ∨ i.mn == "blrl"

def main (args : List String) : IO Unit := do
  match args with
  | bin :: archS :: tgtS :: foS :: vaS :: lenS :: _ =>
    let a : A := if archS == "ppc" then .ppc else .x86
    let (carch, cmode) := if a == .ppc then (Capstone.Arch.ppc, Mode.b64 ||| Mode.bigEndian) else (Capstone.Arch.x86, Mode.b32)
    let target : Int := parseImm tgtS
    let fo := (parseImm foS).toNat; let va := (parseImm vaS).toNat; let len := (parseImm lenS).toNat
    let d ← IO.FS.readBinFile (bin : System.FilePath)
    let insns := (disasm carch cmode (d.extract fo (fo+len)) va).map
      (fun x => ({ addr := x.addr, mn := x.mnemonic, ops := x.ops } : Ins))
    let nI := insns.size
    -- address → index
    let mut addr2idx : Std.HashMap Nat Nat := {}
    for i in [0:nI] do addr2idx := addr2idx.insert insns[i]!.addr i
    -- successors per index (fall-through + branch target)
    let succ := fun (i : Nat) =>
      let ins := insns[i]!
      let ft := if isUncondJmp a ins ∨ i+1 ≥ nI then [] else [i+1]
      let bt := match branchTarget a ins with
        | some t => (match addr2idx[t]? with | some j => [j] | none => ([] : List Nat))
        | none => ([] : List Nat)
      ft ++ bt
    -- forward CFG walk from a def: BFS preserving the base reg, find a use
    -- whose (value + disp) == target. Returns the use addr if found.
    let walk := fun (start : Nat) (reg : String) (val : Int) =>
      Id.run do
        let mut seen : Std.HashSet Nat := {}
        let mut stack := succ start
        let mut steps := 0
        while ¬stack.isEmpty ∧ steps < 4000 do
          steps := steps + 1
          match stack with
          | [] => pure ()
          | k :: rest =>
            stack := rest
            if ¬ seen.contains k ∧ k < nI then
              seen := seen.insert k
              let ins := insns[k]!
              match useDisp a ins reg with
              | some disp => if val + disp == target then return some ins.addr
              | none => pure ()
              if ¬ clobbers a ins reg then stack := succ k ++ stack
        pure none
    -- collect def witnesses whose materialised value shares the target's high
    -- half (a cheap evidence filter so the search space stays small/relevant).
    let defs := (Array.range nI).filterMap (fun i =>
      match defOf a insns[i]! with
      | some (r, v) => if (target - v).toNat < 0x10000 ∨ v == target then some (i, r, v) else none
      | none => none)
    IO.println s!"insns={nI}, def-witness candidates={defs.size}, target=0x{String.ofList (Nat.toDigits 16 target.toNat)}"
    -- plausible: ∀ def-witness index, ¬(it reaches a target-hitting use).
    -- A counterexample = the witness DAG locating the cross-block reference.
    let cfg : Plausible.Configuration := { numInst := 4000, quiet := true }
    let r ← Testable.checkIO
      (NamedBinder "w" (∀ w : Fin 4096,
        (match defs[w.val]? with
         | some (i, rr, v) => (walk i rr v).isNone
         | none => true) = true)) cfg
    if r.isFailure then
      IO.println "FOUND a witness DAG to target (plausible counterexample):"
      IO.println (toString r)
      -- also print every located reference deterministically
      for (i, rg, v) in defs do
        match walk i rg v with
        | some ua => IO.println s!"  ~ def @0x{String.ofList (Nat.toDigits 16 insns[i]!.addr)} ({rg}={v}) → use @0x{String.ofList (Nat.toDigits 16 ua)}"
        | none => pure ()
    else
      IO.println "no witness DAG reaches the target in this region"
  | _ => IO.eprintln "usage: flowref <binary> <arch:x86|ppc> <targetHex> <fileOffHex> <vaddrHex> <lenHex>"
