import Std.Tactic.BVDecide
import LeanSlang

/-! # flowref IL — a BitVec SSA core, proved with `bv_decide` (no oracle)

This is the proof target I proposed: a tiny, total, SSA expression language whose
denotation is a plain Lean function over `BitVec 32`. Because every value is a
fixed-width two's-complement word, equivalence obligations are *decided* by
`bv_decide` (bitblast → SAT) — a real machine-checked theorem, replacing the
`plausible` random-tuple search in `EquivCheck.lean`. -/

namespace FlowrefDecompiler.IL

abbrev Word := BitVec 32

/-- The operations flowref already lifts for leaf functions. -/
inductive Op | add | sub | mul | band | bor | bxor | shl
  deriving DecidableEq, Repr

/-- An operand: a function argument, an earlier SSA slot, or an immediate.
This is exactly the shape of the lifted C (`eax_1 = eax_0 + a1`): `arg` = a
parameter, `slot` = a prior `eax_n`, `imm` = a literal. -/
inductive Atom | arg (i : Nat) | slot (i : Nat) | imm (w : Word)
  deriving Repr

/-- One SSA binding: `slot_next := op a b`. -/
structure Bind where
  op : Op
  a  : Atom
  b  : Atom
  deriving Repr

/-- A leaf function: ordered SSA bindings + the returned atom. -/
structure Prog where
  binds : List Bind
  ret   : Atom
  deriving Repr

@[simp] def Op.apply : Op → Word → Word → Word
  | .add,  x, y => x + y
  | .sub,  x, y => x - y
  | .mul,  x, y => x * y
  | .band, x, y => x &&& y
  | .bor,  x, y => x ||| y
  | .bxor, x, y => x ^^^ y
  | .shl,  x, y => x <<< y

@[simp] def Atom.eval (args slots : List Word) : Atom → Word
  | .arg i  => args.getD i 0
  | .slot i => slots.getD i 0
  | .imm w  => w

/-- Thread the SSA slots left-to-right; when bindings are exhausted, read `ret`. -/
@[simp] def evalGo (args : List Word) (ret : Atom) : List Bind → List Word → Word
  | [],      slots => ret.eval args slots
  | b :: bs, slots =>
      evalGo args ret bs (slots ++ [b.op.apply (b.a.eval args slots) (b.b.eval args slots)])

/-- Evaluate a program against an argument list. -/
@[simp] def Prog.eval (p : Prog) (args : List Word) : Word :=
  evalGo args p.ret p.binds []

/-! ## The demo functions, lifted into the IL.

These mirror `decompile-bench/equiv-demo.sh` exactly. -/

open Op Atom

/-- `uint32_t p_add(a,b){ return a + b; }` → `eax_0 = a0; eax_1 = eax_0 + a1`. -/
def p_add : Prog := { binds := [⟨add, arg 0, arg 1⟩], ret := slot 0 }
/-- `uint32_t p_xor(a,b){ return a ^ b; }` -/
def p_xor : Prog := { binds := [⟨bxor, arg 0, arg 1⟩], ret := slot 0 }
/-- `uint32_t p_mul(a,b){ return a * b; }` -/
def p_mul : Prog := { binds := [⟨mul, arg 0, arg 1⟩], ret := slot 0 }
/-- `uint32_t kxor(){ uint32_t x = 0xff; return x ^ 0x0f; }` -/
def kxor  : Prog := { binds := [⟨bxor, imm 0xff, imm 0x0f⟩], ret := slot 0 }
/-- `uint32_t kchain(){ x=10; x=x+5; x=x-3; return x; }` -/
def kchain : Prog :=
  { binds := [⟨add, imm 10, imm 0⟩, ⟨add, slot 0, imm 5⟩, ⟨sub, slot 1, imm 3⟩], ret := slot 2 }

/-! ## Real proofs — `bv_decide`, not a tuple search.

Each theorem is `∀ args, lift args = spec args`, discharged by bitblasting. For
the parameterised ones this is the universally-quantified statement the oracle
could only *sample*. -/

theorem p_add_correct (a b : Word) : p_add.eval [a, b] = a + b := by
  simp [p_add, Prog.eval, evalGo]

theorem p_xor_correct (a b : Word) : p_xor.eval [a, b] = a ^^^ b := by
  simp [p_xor, Prog.eval, evalGo]

theorem p_mul_correct (a b : Word) : p_mul.eval [a, b] = a * b := by
  simp [p_mul, Prog.eval, evalGo]

theorem kxor_correct : kxor.eval [] = 240 := by
  simp [kxor, Prog.eval, evalGo]

theorem kchain_correct : kchain.eval [] = 12 := by
  simp [kchain, Prog.eval, evalGo]

/-- A property the random oracle would *never* certify but `bv_decide` proves:
`p_add` and the swapped-arg version are equal for **all** 2^64 inputs. -/
theorem p_add_comm (a b : Word) : p_add.eval [a, b] = p_add.eval [b, a] := by
  simp only [p_add, Prog.eval, evalGo, Atom.eval, Op.apply,
             List.getD_cons_zero, List.getD_cons_succ, List.nil_append]
  bv_decide

/-! ## Slang backend: render to the real lean-slang AST, proved meaning-preserving.

`render` lowers an IL program to `LeanSlang.SlangExpr` — the same AST
`LeanSlang.Emit` pretty-prints to `slangc`-accepted source — and we prove the
render preserves meaning against `LeanSlang.evalU32`, the BitVec semantics that
ships with lean-slang. SSA slots are inlined into the expression; `arg i`
becomes the shader parameter named `aᵢ`.

The payoff: instead of `EquivCheck.lean` shelling out to `cc` + `dlopen` to
*run* the emitted code, the **emitted artifact is the proof object** — nothing
compiles, nothing executes. The only trusted edge left is `libslang`'s
Slang→SPIR-V translation, which is Khronos's problem, not ours. -/

open LeanSlang

/-- Map an IL op to the exact operator string `LeanSlang.Emit` prints (and
`LeanSlang.binOpU32` interprets) — so render, printer, and semantics agree. -/
@[simp] def Op.slangOp : Op → String
  | .add => "+" | .sub => "-" | .mul => "*"
  | .band => "&" | .bor => "|" | .bxor => "^" | .shl => "<<"

/-- The Slang parameter name for argument `i`. -/
@[simp] def argName (i : Nat) : String := "a" ++ toString i

/-- Lower an atom: args → shader params, slots → their rendered expr, imm → a
`uint` literal. -/
@[simp] def Atom.toSlang (slots : List SlangExpr) : Atom → SlangExpr
  | .arg i  => .var (argName i)
  | .slot i => slots.getD i (.litUint 0)
  | .imm w  => .litUint w.toNat

/-- Inline the SSA slots left-to-right, then render the returned atom. -/
@[simp] def renderGo (ret : Atom) : List Bind → List SlangExpr → SlangExpr
  | [],      slots => ret.toSlang slots
  | b :: bs, slots =>
      renderGo ret bs (slots ++ [.bin b.op.slangOp (b.a.toSlang slots) (b.b.toSlang slots)])

/-- IL program → one scalar `LeanSlang.SlangExpr`. -/
@[simp] def Prog.render (p : Prog) : SlangExpr := renderGo p.ret p.binds []

/-- Two-argument environment: `a0 ↦ a`, `a1 ↦ b`, everything else `0`. -/
def env2 (a b : Word) : UEnv := fun n => if n = "a0" then a else if n = "a1" then b else 0

/-! ### render-correctness: the emitted Slang means exactly what the IL means.

`evalU32` returns `Option` (it is partial outside the uint fragment); these
theorems land on `some _`, certifying the render stays inside that fragment. -/

theorem p_add_render (a b : Word) :
    (p_add.render).evalU32 (env2 a b) = some (p_add.eval [a, b]) := by
  simp +decide [p_add, env2]

theorem p_xor_render (a b : Word) :
    (p_xor.render).evalU32 (env2 a b) = some (p_xor.eval [a, b]) := by
  simp +decide [p_xor, env2]

theorem kchain_render :
    (kchain.render).evalU32 (env2 0 0) = some (kchain.eval []) := by
  simp +decide

/-- End to end: the rendered Slang for `p_add` computes `a + b` for **all**
inputs — render-correctness composed with the IL spec. -/
theorem p_add_render_spec (a b : Word) :
    (p_add.render).evalU32 (env2 a b) = some (a + b) := by
  simp +decide [p_add, env2]

/-! ## Memory: read-only loads — growing the class past register-only leaves.

The corpus measurement (random 500-function Decompile-Bench sample) found ~0%
of real functions are register-only leaves; the binding constraint is memory.
This adds a `Word`-addressed load: a straight-line function may now dereference
pointers (no stores / calls / branches yet) — the nearest reachable real-corpus
tier. `bv_decide` still discharges equivalence: memory reads appear as
applications of an opaque `Mem`, abstracted uniformly on both sides. -/

/-- A word-addressed memory: address → 32-bit value. -/
abbrev Mem := Word → Word

/-- A binding right-hand side: an ALU op, or a load `*(uint32_t*)addr`. -/
inductive Rhs
  | alu  (op : Op) (a b : Atom)
  | load (addr : Atom)
  deriving Repr

/-- A leaf function with read-only memory. -/
structure MProg where
  binds : List Rhs
  ret   : Atom
  deriving Repr

@[simp] def Rhs.eval (mem : Mem) (args slots : List Word) : Rhs → Word
  | .alu op a b => op.apply (a.eval args slots) (b.eval args slots)
  | .load addr  => mem (addr.eval args slots)

/-- Thread the SSA slots left-to-right under a fixed memory, then read `ret`. -/
@[simp] def mevalGo (mem : Mem) (args : List Word) (ret : Atom) : List Rhs → List Word → Word
  | [],      slots => ret.eval args slots
  | r :: rs, slots => mevalGo mem args ret rs (slots ++ [r.eval mem args slots])

@[simp] def MProg.eval (mem : Mem) (p : MProg) (args : List Word) : Word :=
  mevalGo mem args p.ret p.binds []

open Rhs

/-- `uint32_t load_add(uint32_t* p){ return p[0] + p[1]; }` — reads the words at
`p` and `p+4`. Straight-line, two loads, no store/call/branch. -/
def load_add : MProg :=
  { binds := [ load (arg 0)                 -- slot0 = *p
             , alu add (arg 0) (imm 4)       -- slot1 = p + 4
             , load (slot 1)                 -- slot2 = *(p+4)
             , alu add (slot 0) (slot 2) ]   -- slot3 = slot0 + slot2
  , ret := slot 3 }

/-- The lift means exactly `mem[p] + mem[p+4]`, for **all** memories and `p`. -/
theorem load_add_correct (mem : Mem) (p : Word) :
    load_add.eval mem [p] = mem p + mem (p + 4) := by
  simp [load_add, MProg.eval, mevalGo]

/-- Equivalence under memory: summing the two loads in the other order gives the
same value — `bv_decide`, with the loads abstracted as opaque terms. -/
theorem load_add_comm (mem : Mem) (p : Word) :
    load_add.eval mem [p] = mem (p + 4) + mem p := by
  simp only [load_add, MProg.eval, mevalGo, Rhs.eval, Atom.eval, Op.apply,
             List.getD_cons_zero, List.getD_cons_succ, List.nil_append, List.cons_append]
  bv_decide

end FlowrefDecompiler.IL
