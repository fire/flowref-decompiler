import Lake
open Lake DSL System

package flowref where
  -- moreLeancArgs / moreLinkArgs left default

require plausible from git
  "https://github.com/leanprover-community/plausible" @ "v4.30.0"

-- Multi-arch disassembler (typed Capstone wrapper). Provides the `Capstone`
-- module + the C glue; the static `libcapstone.a` is linked below.
require «lean-capstone» from git
  "https://github.com/fire/lean-capstone" @ "main"

@[default_target] lean_lib Flowref

@[default_target] lean_exe flowref where
  root := `Flowref
  -- Link the multi-arch Capstone static archive vendored by lean-capstone.
  -- Grouped so the shim's cs_* symbols resolve against libcapstone.a.
  -- After `lake update`, run the dep's build.sh once to produce the archive:
  --   .lake/packages/lean-capstone/thirdparty/capstone/build.sh
  moreLinkArgs := #[
    "-Wl,--start-group",
    ".lake/packages/lean-capstone/thirdparty/capstone/lib/libcapstone.a",
    "-Wl,--end-group"]
