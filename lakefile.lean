import Lake
open Lake DSL System

package flowref where
  -- moreLeancArgs / moreLinkArgs left default

require plausible from git
  "https://github.com/leanprover-community/plausible" @ "v4.30.0"

/-! ## Capstone disassembler FFI (multi-arch).
    Headers live in `thirdparty/capstone/include` (BSD-3-Clause); the static
    `libcapstone.a` is produced by `thirdparty/capstone/build.sh` (gitignored).
    `ffi/capstone_shim.c` is the Lean ↔ Capstone glue; `Capstone.lean` is the
    typed wrapper. The archive is linked into the exe via `moreLinkArgs`. -/

@[default_target] lean_lib Capstone
@[default_target] lean_lib Flowref

target capstoneShimO pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "capstone_shim.o"
  let srcJob ← inputTextFile <| pkg.dir / "ffi" / "capstone_shim.c"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString,
                    "-I", (pkg.dir / "thirdparty" / "capstone" / "include").toString]
  buildO oFile srcJob weakArgs #["-fPIC", "-O2"] "cc" getLeanTrace

extern_lib libcapstoneshim pkg := do
  let name := nameToStaticLib "capstoneshim"
  let oJob ← capstoneShimO.fetch
  buildStaticLib (pkg.staticLibDir / name) #[oJob]

@[default_target] lean_exe flowref where
  root := `Flowref
  -- Link the vendored multi-arch Capstone static archive. Grouped so the
  -- shim's cs_* symbols resolve against libcapstone.a regardless of order.
  moreLinkArgs := #[
    "-Wl,--start-group", "thirdparty/capstone/lib/libcapstone.a", "-Wl,--end-group"]
