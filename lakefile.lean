import Lake
open Lake DSL System

package «flowref-decompiler» where
  -- moreLeancArgs / moreLinkArgs left default

/-! ## Disassembler dependency.
    The control-flow-aware disassembler — the `Flowref.*` modules (Disasm,
    Dataflow, Ports, Decoders, Adapters, Elf, Toc, Params) plus the self-contained
    `<elf.h>` ELF shim (`libelfshim` extern_lib) and the multi-arch Capstone
    wrapper — now lives in its own repo and is consumed as a Lake dependency.
    `lean-capstone`, `plausible`, and the `elfshim` glue come transitively
    through it; we do not re-`require` them. This package keeps only the
    decompiler: the C emitter, the calling-convention parameter model, the
    plausible equivalence oracle, and the ETNF corpus normaliser. -/
require «flowref» from git
  "https://github.com/fire/flowref" @ "main"

-- Slang AST + emitter + BitVec semantics (`LeanSlang.evalU32`). The decompiler's
-- IL (`FlowrefDecompiler.IL`) renders to `LeanSlang.SlangExpr` and proves the
-- render preserves meaning against that semantics — no compile/run oracle.
require LeanSlang from git
  "https://github.com/V-Sekai-fire/lean-slang" @ "main"

-- ETNF corpus normalisation writes Decompile-Bench rows to Parquet through
-- DuckDB, statically linked from a self-contained archive that lean_duckdb builds
-- from the DuckDB C amalgamation SOURCE on a plain `lake build` (no prebuilt
-- binary, no libduckdb.so). This dependency is used only by the flowref-etnf /
-- flowref-training-parquet executables below; the production decompiler/oracle
-- targets do not import it (the shim's DuckDB symbols are never pulled into them).
require lean_duckdb from git
  "https://github.com/v-sekai-multiplayer-fabric/lean-duckdb" @ "main"

@[default_target] lean_lib FlowrefDecompiler where
  -- pick up FlowrefDecompiler.lean and every FlowrefDecompiler/*.lean submodule.
  globs := #[.one `FlowrefDecompiler, .submodules `FlowrefDecompiler]

@[default_target] lean_exe «flowref-decompiler» where
  root := `FlowrefDecompiler
  -- Link the multi-arch Capstone static archive built by lean-capstone (a
  -- transitive dependency via fire/flowref). Grouped so the disassembler shim's
  -- cs_* symbols resolve against libcapstone.a. The archive is built FROM SOURCE
  -- one-stop by the Lean/Lake build system (cc + ar, no cmake) on a plain
  -- `lake build` — no manual step; see lean-capstone's `capstoneShimO` target.
  moreLinkArgs := #[
    "-Wl,--start-group",
    ".lake/packages/lean-capstone/thirdparty/capstone/lib/libcapstone.a",
    "-Wl,--end-group"]
    -- The ELF parser is the self-contained `<elf.h>` shim (`libelfshim`), linked
    -- transitively from the fire/flowref dependency — no external library.

/-! ## Equivalence oracle FFI (`flowref-equiv`).
    `ffi/equiv_dl.c` dlopen's a compiled (reference, candidate) pair so the Lean
    `EquivCheck` exe can run a plausible counterexample search over their inputs. -/
target equivDlO pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "equiv_dl.o"
  let srcJob ← inputTextFile <| pkg.dir / "ffi" / "equiv_dl.c"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString]
  buildO oFile srcJob weakArgs #["-fPIC", "-O2"] "cc" getLeanTrace

extern_lib libequivdl pkg := do
  let name := nameToStaticLib "equivdl"
  let oJob ← equivDlO.fetch
  buildStaticLib (pkg.staticLibDir / name) #[oJob]

-- The equivalence oracle, in Lean: runs `flowref-decompiler decompile` for the
-- candidate, compiles the pair, and dlopens it (`-ldl`) for the plausible
-- search. It uses only the pure kernel + plausible, so it needs no Capstone
-- archive.
@[default_target] lean_exe «flowref-equiv» where
  root := `EquivCheck
  moreLinkArgs := #["-ldl"]

-- ETNF normaliser (Etnf.lean): converts flat Decompile-Bench NDJSON rows into
-- lossless ETNF Parquet relations via lean-duckdb. Keep it as a non-default
-- target so `lake build` for the decompiler/oracle remains decoupled from DuckDB.
lean_exe «flowref-etnf» where
  root := `Etnf
  -- Static-link the ENCAPSULATED DuckDB archive (built from the C amalgamation by
  -- lean_duckdb): DuckDB's GNU C++ runtime is whole-archived in and every symbol
  -- but the `duckdb_*` C API is localized, so it does not collide with Lean's
  -- libc++abi. No libduckdb.so, no rpath, no libstdc++/libc++ flags needed.
  moreLinkArgs := #[
    "-Wl,--start-group",
    ".lake/packages/lean_duckdb/vendor/libduckdb.a",
    "-Wl,--end-group",
    "-lm", "-ldl", "-lpthread"
  ]

-- AutoResearch-style training-set snapshots: manifest + oracle results +
-- hypotheses as standalone Parquet files. DuckDB is used only as an in-process
-- Parquet writer/query engine; no persistent database is created.
lean_exe «flowref-training-parquet» where
  root := `TrainingSet
  -- Static-link the ENCAPSULATED DuckDB archive (see flowref-etnf above).
  moreLinkArgs := #[
    "-Wl,--start-group",
    ".lake/packages/lean_duckdb/vendor/libduckdb.a",
    "-Wl,--end-group",
    "-lm", "-ldl", "-lpthread"
  ]
