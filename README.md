# flowref

**Point it at a binary, get back compilable C — and a proof the C returns what
the original did.** A control-flow-aware xref finder and a small decompiler,
written in Lean 4.

```bash
flowref list   a.out                 # what functions are in here?
flowref decompile a.out main         # lift one to C (region read from the ELF)
flowref decompile a.out main | gcc -xc -std=c11 -w -fsyntax-only -   # it compiles
```

```c
uint32_t sub_1000(void) {
  uint32_t eax_0 = 0;
  eax_0 = 0;
  uint32_t ebx_0 = 0xa;
  while (!((int32_t)eax_0 >= (int32_t)ebx_0)) {
    uint32_t eax_1 = eax_0 + 1;
  }
  if (!((int32_t)ebx_0 != (int32_t)0xa)) {
    uint32_t ecx_0 = 1;
  }
  return eax_0;
}
```

The output is meant to be **read and trusted**: values declared where they're
computed, real `if`/`while` instead of `goto`, no machine noise. The style
follows NASA/JPL's *Power of Ten* (simple control flow, smallest scope) so it's
easy to teach from and to review.

## Commands

| Command | What it does |
|---|---|
| `flowref list <bin>` | List functions (name, address, size) and the auto-detected arch. |
| `flowref decompile <bin> <name\|0xaddr>` | Lift a function to C. |
| `flowref xref <bin> <name\|0xaddr> <target>` | Find where `target` is used in that function. |
| `flowref demo` | Built-in self-tests (no files needed). |

Add `--json` for machine-readable output, `--search-trace` to watch the search.
For ELF binaries the arch, file offset, address and length are read from the
headers — give a symbol or `0x` address, not six hex numbers. For raw blobs,
pass them explicitly: `flowref decompile <bin> <arch> <fnVaddr> <fileOff> <vaddr> <len>`
(run `flowref --help` for the full list, including `.asm`-listing input).

## How it works

- **Equivalence is the point.** The emitted C must be both type-correct *and*
  return the same value as the source. An oracle (`decompile-bench/equiv.sh`)
  compiles, links and *runs* the lifted C against the reference to check it,
  reporting `INCOMPARABLE` rather than ever claiming a false equivalence.
- **Plausible-driven, no hand-rolled analysis.** Every data-flow fact (reaching
  defs, back-edges, reachability) is recovered as a *counterexample* from
  [`plausible`](https://github.com/leanprover-community/plausible), deepened
  on demand into a witness DAG. The `if`/`while` structure is rendered from
  those same witnesses.
- **Hexagonal.** A pure kernel (`Disasm`/`Dataflow`/`Emit`) speaks only an
  instruction model; adapters feed it from ELF, raw bytes, or an asm listing.
  Decoding covers every Capstone target; data-flow patterns are x86 + PowerPC.

## Build & test

```bash
lake update
.lake/packages/lean-capstone/thirdparty/capstone/build.sh   # build libcapstone.a once (slow)
lake build
./run-tests.sh                                              # builds, runs demos, gcc-checks the C
```

ELF parsing is a self-contained `<elf.h>` shim (`ffi/elf_shim.c`) — no external
library to install.

## Limitations

A **lead-finder and MVP decompiler, not Ghidra.** Equivalence is proven today for
register-only leaf functions; larger functions lift to compilable C but are not
yet guaranteed faithful (no float/struct/varargs ABI, register-level model,
irreducible control flow falls back to `goto`). Very large functions can hit the
search budget. See `decompile-bench/README.md` for the evaluation and open gaps.

## License

MIT (see `LICENSE`). Disassembly via
[`lean-capstone`](https://github.com/fire/lean-capstone) (Capstone, BSD-3).
Evaluated against Decompile-Bench (Tan, Tian, Qi et al., 2025; see `CITATIONS.bib`).
