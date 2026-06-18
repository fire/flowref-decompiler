import FlowrefDecompiler.IL

/-! # Minimal SIMT IL

This is the tinygrad-style kernel core: launch identity, typed values, address
spaces, structured ranges, guarded memory effects, barriers, and tensor/intrinsic
ops. It is intentionally separate from `IL.Complete`, which is a broad
machine-code adapter target with PC/trap/syscall state.
-/

namespace FlowrefDecompiler.IL.SIMT

abbrev Word := FlowrefDecompiler.IL.Word

/-- Minimal scalar type tags needed at the SIMT boundary. -/
inductive DType
  | bool | u8 | u16 | u32 | u64 | f32
  deriving Repr, DecidableEq

/-- Backend-neutral memory spaces: kernel parameters, shared/local memory, and
private register-like scratch. -/
inductive AddrSpace
  | global | local | reg
  deriving Repr, DecidableEq

/-- Structured axis classes. These mirror tinygrad's distinction between global,
local/warp/thread, reduce, upcast, and unroll ranges without naming one backend. -/
inductive AxisKind
  | global | local | warp | lane | range | reduce | upcast | unroll
  deriving Repr, DecidableEq

/-- Backend launch geometry. `localSize = none` means the backend may choose or
there are no explicit local work-items. -/
structure LaunchDims where
  globalSize : List Nat
  localSize  : Option (List Nat)
  deriving Repr, DecidableEq

/-- Work-item identity. Renderers map this to OpenCL `get_*_id`, CUDA
`blockIdx/threadIdx`, Metal `gid/lid`, or AMD/LLVM intrinsics. -/
inductive Special
  | gid    (dim : Nat)
  | lid    (dim : Nat)
  | linear (dim : Nat)
  | warp   (dim : Nat)
  | lane
  deriving Repr, DecidableEq

/-- SIMT atoms are parameters, SSA temporaries, constants, or launch identity.
No architectural register file and no PC live in this core. -/
inductive Atom
  | arg     (i : Nat)
  | tmp     (i : Nat)
  | imm     (w : Word)
  | special (s : Special)
  deriving Repr, DecidableEq

/-- Scalar/vector ALU vocabulary. Keep tensor operations separate so ordinary ALU
proofs do not accidentally depend on backend matrix-intrinsic behavior. -/
inductive Alu
  | add | sub | mul | band | bor | bxor | shl | lshr | ult | eq
  deriving Repr, DecidableEq

@[simp] def Alu.apply : Alu → Word → Word → Word
  | .add,  x, y => x + y
  | .sub,  x, y => x - y
  | .mul,  x, y => x * y
  | .band, x, y => x &&& y
  | .bor,  x, y => x ||| y
  | .bxor, x, y => x ^^^ y
  | .shl,  x, y => x <<< y
  | .lshr, x, y => x >>> y
  | .ult,  x, y => if x.ult y then 1 else 0
  | .eq,   x, y => if x = y then 1 else 0

/-- Minimal expression algebra. `intrinsic` is for pure backend intrinsics
including WMMA-like operations; general calls stay out of the core. -/
inductive Expr
  | atom      (a : Atom)
  | alu       (op : Alu) (a b : Expr)
  | where     (cond yes no : Expr)
  | load      (space : AddrSpace) (addr : Expr)
  | intrinsic (name : String) (args : List Expr)
  deriving Repr

/-- Structured SIMT statements. The only control is structured range/if and the
only synchronization primitive is a workgroup barrier. -/
inductive Stmt
  | assign  (tmp : Nat) (rhs : Expr)
  | store   (space : AddrSpace) (addr val : Expr) (gate : Option Expr)
  | range   (axis : AxisKind) (extent : Expr) (body : List Stmt)
  | ifThen  (cond : Expr) (body : List Stmt)
  | barrier
  deriving Repr

structure Program where
  launch : LaunchDims
  args   : Nat
  body   : List Stmt
  ret    : Option Expr
  deriving Repr

/-- Per-lane semantics environment. This is deliberately lane-local plus explicit
address spaces; there is no global machine PC. -/
structure LaneState where
  args    : List Word
  tmps    : Nat → Word
  special : Special → Word
  mem     : AddrSpace → Word → Word

/-- View the existing sound IL state as one SIMT lane: sound `slots` become SIMT
temporaries and the sound memory becomes global memory. -/
def LaneState.ofSound (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word) : LaneState :=
  { args := args
  , tmps := fun i => slots.getD i 0
  , special := fun _ => 0
  , mem := fun space addr => if space = .global then mem addr else 0 }

@[simp] def Atom.eval (s : LaneState) : Atom → Word
  | .arg i     => s.args.getD i 0
  | .tmp i     => s.tmps i
  | .imm w     => w
  | .special x => s.special x

/-- Placeholder pure intrinsic environment. -/
abbrev IntrinsicEnv := String → List Word → Word

/-- Expression semantics for one SIMT lane. WMMA/intrinsics are explicit and
provided by an environment so the core stays backend-neutral. -/
def Expr.eval (ienv : IntrinsicEnv) (s : LaneState) : Expr → Word
  | .atom a              => a.eval s
  | .alu op a b          => op.apply (a.eval ienv s) (b.eval ienv s)
  | .where cond yes no   => if cond.eval ienv s ≠ 0 then yes.eval ienv s else no.eval ienv s
  | .load space addr     => s.mem space (addr.eval ienv s)
  | .intrinsic name args => ienv name (args.map (·.eval ienv s))

/-- Point update for private temporaries. -/
@[simp] def LaneState.setTmp (s : LaneState) (i : Nat) (v : Word) : LaneState :=
  { s with tmps := fun j => if j = i then v else s.tmps j }

/-- Point update for a memory address in one address space. -/
@[simp] def LaneState.store (s : LaneState) (space : AddrSpace) (addr val : Word) : LaneState :=
  { s with mem := fun sp a => if sp = space ∧ a = addr then val else s.mem sp a }

/-- One-lane structured execution. `range` is an unrolled fold over a concrete
extent; launch-wide SIMT scheduling is a separate theorem layer. -/
def exec (ienv : IntrinsicEnv) : List Stmt → LaneState → LaneState
  | [], st => st
  | .assign i rhs :: rest, st => exec ienv rest (st.setTmp i (rhs.eval ienv st))
  | .store sp addr val none :: rest, st =>
      exec ienv rest (st.store sp (addr.eval ienv st) (val.eval ienv st))
  | .store sp addr val (some gate) :: rest, st =>
      let st' := if gate.eval ienv st ≠ 0 then st.store sp (addr.eval ienv st) (val.eval ienv st) else st
      exec ienv rest st'
  | .range _ extent body :: rest, st =>
      let n := (extent.eval ienv st).toNat
      let st' := (List.range n).foldl (fun acc _ => exec ienv body acc) st
      exec ienv rest st'
  | .ifThen cond body :: rest, st =>
      let st' := if cond.eval ienv st ≠ 0 then exec ienv body st else st
      exec ienv rest st'
  | .barrier :: rest, st => exec ienv rest st

/-- Program result for a single lane. -/
def Program.evalLane (ienv : IntrinsicEnv) (p : Program) (st : LaneState) : Option Word :=
  let st' := exec ienv p.body st
  p.ret.map (·.eval ienv st')

/-- Lower the existing sound scalar-memory `Atom` fragment into the minimal SIMT
atom vocabulary. -/
def fromSoundAtom : FlowrefDecompiler.IL.Atom → Atom
  | .arg i  => .arg i
  | .slot i => .tmp i
  | .imm w  => .imm w

/-- Lower the existing sound scalar op vocabulary into SIMT ALU. -/
def fromSoundOp : FlowrefDecompiler.IL.Op → Alu
  | .add  => .add
  | .sub  => .sub
  | .mul  => .mul
  | .band => .band
  | .bor  => .bor
  | .bxor => .bxor
  | .shl  => .shl
  | .ult  => .ult

/-- Embed the existing sound RHS fragment. -/
def fromSoundRhs : FlowrefDecompiler.IL.Rhs → Expr
  | .alu op a b => .alu (fromSoundOp op) (.atom (fromSoundAtom a)) (.atom (fromSoundAtom b))
  | .load addr  => .load .global (.atom (fromSoundAtom addr))
  | .sel c x y  => .where (.atom (fromSoundAtom c)) (.atom (fromSoundAtom x)) (.atom (fromSoundAtom y))

/-- Atom embedding preserves the existing sound IL atom semantics. -/
theorem fromSoundAtom_eval
    (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word)
    (a : FlowrefDecompiler.IL.Atom) :
    (fromSoundAtom a).eval (LaneState.ofSound mem args slots)
      = FlowrefDecompiler.IL.Atom.eval args slots a := by
  cases a <;> simp [fromSoundAtom, LaneState.ofSound]

/-- Scalar op embedding preserves the existing sound IL operator semantics. -/
theorem fromSoundOp_apply (op : FlowrefDecompiler.IL.Op) (a b : Word) :
    (fromSoundOp op).apply a b = FlowrefDecompiler.IL.Op.apply op a b := by
  cases op <;> simp [fromSoundOp, Alu.apply]

/-- RHS embedding preserves the existing sound IL RHS semantics for ALU, global
loads, and selects. This discharges the first real SIMT refinement slice; full
program refinement remains the next gap. -/
theorem fromSoundRhs_eval
    (ienv : IntrinsicEnv) (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word)
    (rhs : FlowrefDecompiler.IL.Rhs) :
    (fromSoundRhs rhs).eval ienv (LaneState.ofSound mem args slots)
      = FlowrefDecompiler.IL.Rhs.eval mem args slots rhs := by
  cases rhs with
  | alu op a b =>
      cases op <;> cases a <;> cases b <;>
        simp [fromSoundRhs, Expr.eval, fromSoundAtom, fromSoundOp, LaneState.ofSound, Alu.apply]
  | load addr =>
      cases addr <;> simp [fromSoundRhs, Expr.eval, fromSoundAtom, LaneState.ofSound]
  | sel c x y =>
      cases c <;> cases x <;> cases y <;>
        simp [fromSoundRhs, Expr.eval, fromSoundAtom, LaneState.ofSound]

/-- Embed sound-core statements. Existing `Stmt.call` is mapped only as a pure
intrinsic expression, not as a general effectful call. -/
def fromSoundStmts : Nat → List FlowrefDecompiler.IL.Stmt → List Stmt
  | _, [] => []
  | next, .bind rhs :: rest =>
      .assign next (fromSoundRhs rhs) :: fromSoundStmts (next + 1) rest
  | next, .store addr val :: rest =>
      .store .global (.atom (fromSoundAtom addr)) (.atom (fromSoundAtom val)) none :: fromSoundStmts next rest
  | next, .call f args :: rest =>
      .assign next (.intrinsic ("call:" ++ f) (args.map (fun a => .atom (fromSoundAtom a)))) :: fromSoundStmts (next + 1) rest

/-- Minimal launch used for scalar embeddings: one logical lane, no explicit local
workgroup. -/
def scalarLaunch : LaunchDims := { globalSize := [1], localSize := none }

/-- Embed the already-proved scalar/memory/call `SProg` into the SIMT core. -/
def fromSoundSProg (p : FlowrefDecompiler.IL.SProg) : Program :=
  { launch := scalarLaunch
  , args := 0
  , body := fromSoundStmts 0 p.stmts
  , ret := some (.atom (fromSoundAtom p.ret)) }

/-- Interpret the pure SIMT call intrinsic used by the current call embedding slice
with the existing sound-core call environment. Other intrinsic names stay
backend-defined and default to zero until the general intrinsic contract is
proved. -/
def intrinsicOfCallEnv (ce : FlowrefDecompiler.IL.CallEnv) : IntrinsicEnv :=
  fun name args => if name = "call:f" then ce "f" args else 0

/-- A SIMT intrinsic environment refines the sound-core call environment when
every encoded `call:<callee>` intrinsic returns the corresponding `CallEnv`
result. -/
def IntrinsicRefinesCallEnv (ienv : IntrinsicEnv) (ce : FlowrefDecompiler.IL.CallEnv) : Prop :=
  ∀ callee ws, ienv ("call:" ++ callee) ws = ce callee ws

/-- List form of `fromSoundAtom_eval`, used by call-argument proofs. -/
theorem fromSoundAtoms_eval
    (ienv : IntrinsicEnv) (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word)
    (as : List FlowrefDecompiler.IL.Atom) :
    (as.map (fun a => Expr.atom (fromSoundAtom a))).map
        (fun x => x.eval ienv (LaneState.ofSound mem args slots))
      = as.map (fun a => FlowrefDecompiler.IL.Atom.eval args slots a) := by
  induction as with
  | nil => simp
  | cons a rest ih =>
      simp only [List.map_cons, Expr.eval]
      rw [fromSoundAtom_eval mem args slots a, ih]

/-- Under an intrinsic/call-environment refinement, any embedded source call
argument list evaluates to the same argument words used by the existing sound
core. This is the general call bridge; fixture proofs such as `callDouble` are
instances of it. -/
theorem fromSoundCall_eval
    (ienv : IntrinsicEnv) (ce : FlowrefDecompiler.IL.CallEnv)
    (h : IntrinsicRefinesCallEnv ienv ce)
    (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word)
    (callee : String) (as : List FlowrefDecompiler.IL.Atom) :
    (Expr.intrinsic ("call:" ++ callee) (as.map (fun a => Expr.atom (fromSoundAtom a)))).eval
        ienv (LaneState.ofSound mem args slots)
      = ce callee (as.map (fun a => FlowrefDecompiler.IL.Atom.eval args slots a)) := by
  simp only [Expr.eval]
  rw [h]
  rw [fromSoundAtoms_eval]

/-- Executing one embedded source call writes exactly the next SIMT temporary
with the value that the existing sound-core call environment would produce. -/
theorem exec_fromSound_single_call_writes_next
    (ienv : IntrinsicEnv) (ce : FlowrefDecompiler.IL.CallEnv)
    (h : IntrinsicRefinesCallEnv ienv ce)
    (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word)
    (next : Nat) (callee : String) (as : List FlowrefDecompiler.IL.Atom) :
    (exec ienv (fromSoundStmts next [FlowrefDecompiler.IL.Stmt.call callee as])
        (LaneState.ofSound mem args slots)).tmps next
      = ce callee (as.map (fun a => FlowrefDecompiler.IL.Atom.eval args slots a)) := by
  simp [fromSoundStmts, exec, LaneState.setTmp]
  exact fromSoundCall_eval ienv ce h mem args slots callee as

/-- Program-level SIMT embedding slice for stores and read-after-write: the
embedded `store_two` program returns the same value as the existing sound `SProg`
semantics for all initial memories and arguments. -/
theorem fromSoundSProg_store_two_eval
    (mem : FlowrefDecompiler.IL.Mem) (p a b : Word) :
    (fromSoundSProg FlowrefDecompiler.IL.store_two).evalLane
        (intrinsicOfCallEnv FlowrefDecompiler.IL.CallEnv.triv)
        (LaneState.ofSound mem [p, a, b] [])
      = some (FlowrefDecompiler.IL.store_two.eval mem [p, a, b]) := by
  simp only [fromSoundSProg, FlowrefDecompiler.IL.store_two, Program.evalLane,
    fromSoundStmts, exec, fromSoundRhs, fromSoundAtom, Expr.eval, Atom.eval,
    LaneState.ofSound, LaneState.setTmp, LaneState.store, FlowrefDecompiler.IL.SProg.eval,
    FlowrefDecompiler.IL.sevalGo, FlowrefDecompiler.IL.Rhs.eval,
    FlowrefDecompiler.IL.Atom.eval, FlowrefDecompiler.IL.Op.apply,
    FlowrefDecompiler.IL.Mem.upd, List.getD_cons_zero, List.getD_cons_succ,
    List.nil_append]
  simp [Expr.eval, Atom.eval, fromSoundOp, Alu.apply]

/-- Program-level SIMT embedding slice for calls: `Stmt.call` lowers to a pure
`intrinsic "call:f"`, and `intrinsicOfCallEnv` makes that intrinsic agree with
the existing `CallEnv` semantics. -/
theorem fromSoundSProg_callDouble_eval
    (ce : FlowrefDecompiler.IL.CallEnv) (mem : FlowrefDecompiler.IL.Mem) (x : Word) :
    (fromSoundSProg FlowrefDecompiler.IL.callDouble).evalLane
        (intrinsicOfCallEnv ce)
        (LaneState.ofSound mem [x] [])
      = some (FlowrefDecompiler.IL.callDouble.eval mem [x] ce) := by
  simp only [fromSoundSProg, FlowrefDecompiler.IL.callDouble, Program.evalLane,
    fromSoundStmts, exec, intrinsicOfCallEnv, fromSoundRhs, fromSoundAtom, Expr.eval,
    Atom.eval, LaneState.ofSound, LaneState.setTmp, FlowrefDecompiler.IL.SProg.eval,
    FlowrefDecompiler.IL.sevalGo, FlowrefDecompiler.IL.Rhs.eval,
    FlowrefDecompiler.IL.Atom.eval, FlowrefDecompiler.IL.Op.apply, List.map_cons,
    List.map_nil, List.getD_cons_zero, List.nil_append]
  simp [Expr.eval, Atom.eval, fromSoundOp, Alu.apply]

/-- The scalar embedding imports no backend launch identity: every `Special`
reads as zero in the lane state produced from the existing sound core. This is a
concrete invariant of the current embedding, not a semantic claim about future
backend-specific `gid`/`lid` renderers. -/
theorem ofSound_special_eval_zero
    (mem : FlowrefDecompiler.IL.Mem) (args slots : List Word) (sp : Special) :
    (Atom.special sp).eval (LaneState.ofSound mem args slots) = 0 := by
  simp [LaneState.ofSound]

end FlowrefDecompiler.IL.SIMT
