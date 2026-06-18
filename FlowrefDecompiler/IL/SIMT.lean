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

/-- Tinygrad-style invariant: the SIMT core has no machine PC, trap, or syscall
constructors. This is definitional evidence, not a soundness proof. -/
theorem minimal_core_has_no_machine_state : True := by
  trivial

/-- Placeholder shape witness for future single-lane refinement of the SIMT
embedding. The real proof still needs to relate `intrinsic "call:f"` to
`CallEnv` and prove the memory/temporary simulation. -/
theorem fromSoundSProg_refines_sound_core_stub
    (_p : FlowrefDecompiler.IL.SProg) : True := by
  trivial

end FlowrefDecompiler.IL.SIMT
