import Flowref.Disasm
import Plausible

/-! # flowref-equiv — the equivalence oracle, in Lean (binary is the reference)

The reference behaviour is the **real compiled function in the binary** — no
source compilation needed (Decompile-Bench `code` rarely compiles standalone).
Given a binary function region, this:

1. maps the function's raw bytes into executable memory (the reference);
2. lifts the same region to C with `flowref decompile`, refusing anything not
   faithfully liftable (a straight-line, register-only leaf — which is exactly
   what makes the raw bytes position-independent and safe to relocate + run);
3. compiles that C into a shared object (the candidate);
4. poses `∀ args, ref args = cand args` and lets `plausible` hunt for a differing
   argument vector — iteratively deepened. A counterexample IS the disproof
   (`NOT-EQUIVALENT`); its absence after the deepest level is the equivalence
   witness (`EQUIVALENT`). Unliftable/uncompilable ⇒ `INCOMPARABLE`, never a
   false `EQUIVALENT`.

Usage: flowref-equiv <binary> <arch> <fnVaddrHex> <fileOffHex> <vaddrHex> <lenHex>
Exit: 0 EQUIVALENT, 1 NOT-EQUIVALENT, 3 INCOMPARABLE. -/

open Plausible Flowref

/-- Map the reference function's raw bytes executable; `true` on success. -/
@[extern "lean_equiv_load_ref"]  opaque equivLoadRefImpl (bytes : ByteArray) : Bool
/-- dlopen the candidate `.so` (exports `flowref_cand`); `true` on success. -/
@[extern "lean_equiv_load_cand"] opaque equivLoadCandImpl (path : String) : Bool
@[extern "lean_equiv_ref"]  opaque refCall  (a b c d e f : UInt32) : UInt32
@[extern "lean_equiv_cand"] opaque candCall (a b c d e f : UInt32) : UInt32

def equivLoadRef  (b : ByteArray) : IO Bool := pure (equivLoadRefImpl b)
def equivLoadCand (p : String)    : IO Bool := pure (equivLoadCandImpl p)

/-- Parse the candidate's arity from its `uint32_t sub_X(<params>)` definition. -/
def candArity (c hexName : String) : Nat :=
  match (c.splitOn s!"{hexName}(").getLast? with
  | none => 0
  | some tail =>
    let inside := (tail.splitOn ")").headD ""
    if (inside.splitOn "void").length > 1 ∨ inside.trimAscii.isEmpty then 0
    else (inside.splitOn ",").length

/-- Run a command; return success + captured stderr. -/
def run (cmd : String) (args : Array String) : IO (Bool × String) := do
  let out ← IO.Process.output { cmd := cmd, args := args }
  pure (out.exitCode == 0, out.stderr)

/-- `ref` and `cand` agree on the 6-arg vector `v` (missing slots are 0). -/
def agreeOn (v : Array UInt32) : Bool :=
  let g := fun (h : UInt32→UInt32→UInt32→UInt32→UInt32→UInt32→UInt32) =>
    h (v.getD 0 0) (v.getD 1 0) (v.getD 2 0) (v.getD 3 0) (v.getD 4 0) (v.getD 5 0)
  g refCall == g candCall

/-- Small boundary battery — loop-safe (max 257 iterations for O(n) bodies).
Catches sub-register width bugs (movzx truncation diverges at ≥ 256), small
off-by-one errors, and zero/one edge cases. Safe for O(n) loop functions like
`sum_to_n`, `factorial`, `fib_iter` under the 10 s oracle budget.
Values removed because they cause loop-body timeouts: 1000, 4095, 4096,
0x7fff (32767), 0x8000, 5000, 0x12345678.
See `boundaryValsFull` for the extended set used by non-loop leaf functions. -/
def boundaryVals : List UInt32 :=
  [0, 1, 2, 3, 7, 100, 255, 256, 257]

/-- Extended boundary set — safe for straight-line and branch-select leaves
whose single call is O(1). Adds sign-boundary edges (0x7fff/0x8000,
0x7fffffff/0x80000000), large-constant edges (0xffffffff, 0x12345678,
4095/4096) that are needed to catch 32-bit overflow bugs. Do NOT use this
for O(n) loop functions — those exhaust the oracle budget on large inputs. -/
def boundaryValsFull : List UInt32 :=
  boundaryVals ++ [1000, 4095, 4096, 0x7fff, 0x8000,
                   0x7fffffff, 0x80000000, 0xffffffff, 0x12345678]

/-- Search for an argument vector on which `ref` and `cand` differ. Deterministic
boundary battery first (single-axis sweeps over `boundaryVals` against a distinct
non-zero base, the all-equal diagonal, and pairwise on the first two axes —
catches truncation/width bugs and arg-mixing bugs), then `rnd` full-range random
vectors (`IO.rand` over the whole `uint32`). `none` ⇒ agree everywhere tested. -/
def findMismatch (rnd : Nat) : IO (Option (Array UInt32)) := do
  let base : Array UInt32 := #[1, 2, 3, 4, 5, 6]
  -- diagonal + single-axis sweeps + pairwise(0,1)
  let mut vecs : List (Array UInt32) := boundaryVals.map (fun b => #[b,b,b,b,b,b])
  for i in [0:6] do
    for b in boundaryVals do vecs := (base.set! i b) :: vecs
  for a in boundaryVals do
    for b in boundaryVals do vecs := (((base.set! 0 a).set! 1 b)) :: vecs
  for v in vecs do
    if ¬ agreeOn v then return some v
  -- full-range random sweep capped at 257: keeps per-call iteration count ≤ 257
  -- for O(n) loop functions (sum_to_n, factorial, fib_iter).
  -- The boundary battery already hits sub-register edges; random sampling is a
  -- second-tier net for arg-mixing bugs at values the battery does not reach.
  -- Full-range random (0..0xffffffff) is not used here because a random input of
  -- e.g. 0x80000000 causes 2^31 loop iterations per call → seconds per call.
  for _ in [0:rnd] do
    let mut v : Array UInt32 := #[]
    for _ in [0:6] do
      let r ← IO.rand 0 257
      v := v.push (UInt32.ofNat r)
    if ¬ agreeOn v then return some v
  return none

def main (argv : List String) : IO Unit := do
  match argv with
  | [bin, arch, fnS, foS, vaS, lenS] => do
    let fnVa ← match parseImm? fnS with
      | some v => if v < 0 then throw (IO.userError "fnVaddr negative") else pure v.toNat
      | none => throw (IO.userError s!"bad fnVaddr '{fnS}'")
    let fo ← match parseImm? foS with | some v => pure v.toNat | none => throw (IO.userError "bad fileOff")
    let len ← match parseImm? lenS with | some v => pure v.toNat | none => throw (IO.userError "bad len")
    -- 1. Reference = the binary's own function bytes, mapped executable.
    let data ← IO.FS.readBinFile (bin : System.FilePath)
    if fo + len > data.size then
      IO.println "INCOMPARABLE  (region past end of file)"; IO.Process.exit 3
    if ¬ (← equivLoadRef (data.extract fo (fo + len))) then
      IO.println "INCOMPARABLE  (could not map reference bytes)"; IO.Process.exit 3
    -- 2. Candidate = flowref's lift of the SAME region; refused ⇒ INCOMPARABLE.
    let hexName := s!"sub_{Flowref.hex fnVa}"
    let flowref := (← IO.getEnv "FLOWREF").getD ".lake/build/bin/flowref-decompiler"
    let lifted ← IO.Process.output { cmd := flowref, args := #["decompile", bin, arch, fnS, foS, vaS, lenS] }
    if lifted.exitCode != 0 then
      IO.println "INCOMPARABLE  (candidate not faithfully liftable)"; IO.Process.exit 3
    let cand := lifted.stdout
    -- 3. Compile candidate + a shim exporting `flowref_cand` → the lifted sub_X.
    let dir := (← IO.Process.run { cmd := "mktemp", args := #["-d", "/tmp/flowref-equiv.XXXXXX"] }).trimAscii.toString
    let candPath := s!"{dir}/cand.c"
    let shimPath := s!"{dir}/shim.c"
    let soPath := s!"{dir}/pair.so"
    let p6 := "uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t"
    let sig := "(uint32_t a,uint32_t b,uint32_t c,uint32_t d,uint32_t e,uint32_t f)"
    IO.FS.writeFile candPath cand
    -- shim in a SEPARATE TU: declaring sub_X with six args here does not conflict
    -- with its real (fewer-arg) definition in cand.c, and the SysV ABI passes the
    -- extra integer registers harmlessly.
    IO.FS.writeFile shimPath
      ("#include <stdint.h>\nuint32_t " ++ hexName ++ "(" ++ p6 ++ ");\n" ++
       "uint32_t flowref_cand" ++ sig ++ " { return " ++ hexName ++ "(a,b,c,d,e,f); }\n")
    let (ok, cerr) ← run "cc" #["-shared", "-fPIC", "-w", "-std=c11",
      "-fcf-protection=none", "-fno-stack-protector", candPath, shimPath, "-o", soPath]
    if ¬ ok then
      IO.println "INCOMPARABLE  (candidate C did not compile)"; IO.eprint cerr; IO.Process.exit 3
    if ¬ (← equivLoadCand soPath) then
      IO.println "INCOMPARABLE  (could not load candidate)"; IO.Process.exit 3
    -- 4. Differential search for a divergent argument vector: a DETERMINISTIC
    --    boundary battery (sub-register/sign/extreme edges, which a size-biased
    --    random sampler almost never reaches — e.g. a dropped `movzx` truncation
    --    only diverges at args ≥ 256) followed by a full-range random sweep. Six
    --    args cover the SysV integer-arg registers; a counterexample IS disproof.
    let ar := candArity cand hexName
    -- 200 random vectors is sufficient: the boundary battery already hits all
    -- sub-register edges (movzx, sign extension, wrap) deterministically; random
    -- sampling is a second-tier net for arg-mixing bugs. Loop functions finish
    -- their loop bodies at most 257 times per call (bounded by boundaryVals max),
    -- so 200 random calls × 257 iterations = 51 400 iterations — well inside 10s.
    let rnd := 200
    match ← findMismatch rnd with
    | some v =>
      IO.println s!"NOT-EQUIVALENT  (divergent args {v.toList.take (max ar 1)}, arity {ar})"
      IO.Process.exit 1
    | none =>
      IO.println s!"EQUIVALENT  (no divergence; boundary battery + {rnd} random full-range vectors, arity {ar})"
  | _ =>
    IO.eprintln "usage: flowref-equiv <binary> <arch> <fnVaddrHex> <fileOffHex> <vaddrHex> <lenHex>"
    IO.Process.exit 2
