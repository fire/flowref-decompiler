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

-- DuckDB binding: Parquet (+ zstd) read/write and SQL, used to normalise the
-- Decompile-Bench corpus into ETNF relations (see `Etnf.lean`). `lake update`
-- runs the dep's post_update hook, which vendors `libduckdb.so` into
-- `.lake/packages/lean_duckdb/vendor/` (linked by `flowref-etnf` below).
require lean_duckdb from git
  "https://github.com/v-sekai-multiplayer-fabric/lean-duckdb" @ "main"

@[default_target] lean_lib FlowrefDecompiler where
  -- pick up FlowrefDecompiler.lean and every FlowrefDecompiler/*.lean submodule.
  globs := #[.one `FlowrefDecompiler, .submodules `FlowrefDecompiler]

@[default_target] lean_exe «flowref-decompiler» where
  root := `FlowrefDecompiler
  -- Link the multi-arch Capstone static archive vendored by lean-capstone (a
  -- transitive dependency via fire/flowref). Grouped so the disassembler shim's
  -- cs_* symbols resolve against libcapstone.a. After `lake update`, run the
  -- dep's build.sh once to produce the archive:
  --   .lake/packages/lean-capstone/thirdparty/capstone/build.sh
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

-- ETNF normaliser: reads Decompile-Bench rows (ndjson) and writes redundancy-free
-- Parquet relations (zstd) via DuckDB. Links the vendored libduckdb.so (Lake does
-- not propagate a dependency's moreLinkArgs, so we repeat them here per the
-- lean-duckdb README).
lean_exe «flowref-etnf» where
  root := `Etnf
  moreLinkArgs := #[
    "-L.lake/packages/lean_duckdb/vendor", "-lduckdb",
    "-Wl,-rpath,$ORIGIN/../../packages/lean_duckdb/vendor"]
