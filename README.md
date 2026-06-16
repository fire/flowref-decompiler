# flowref

**Point it at a binary, get back compilable C you can actually read.** A
control-flow-aware xref finder and a small decompiler, written in Lean 4. For
*simple* functions it goes further and **machine-checks** that the C returns the
same value as the source — see *Equivalence* for exactly which.

```bash
flowref list   a.out                 # what functions are in here?
flowref decompile a.out main         # lift one to C (region read from the ELF)
flowref decompile a.out main | gcc -xc -std=c11 -w -fsyntax-only -   # it compiles
```

Real output, for a function taking two args and returning their sum:

```c
uint32_t sub_401000(uint32_t a0, uint32_t a1) {
  uint32_t eax_0 = a0;
  uint32_t eax_1 = eax_0 + a1;
  return eax_1;
}
```

The output is meant to be **read**: values declared where they're computed, real
`if`/`while` instead of `goto`, parameters recovered from the calling
convention, no machine noise. The style follows NASA/JPL's *Power of Ten* (simple
control flow, smallest scope) so it's easy to teach from and to review.

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

## Equivalence

The goal is C that is both type-correct *and* returns the same value as the
original. This is **checked, not asserted**: the oracle `decompile-bench/equiv.sh`
compiles, links and *runs* the lifted C against the reference source and compares
return values.

What is proven **today**: parameterless, register-only **leaf** functions. The
bundled demo proves 4/4 —

```text
$ decompile-bench/equiv-demo.sh
  k7     … EQUIVALENT  (both return 7)
  kshift … EQUIVALENT  (both return 16)
  kxor   … EQUIVALENT  (both return 240)
  kchain … EQUIVALENT  (both return 12)
  RESULT: 4/4 proven functionally equivalent to their source.
```

Faithful C is the **bar, not a bonus.** `flowref decompile` emits C **only** for
the class it can lift exactly — a straight-line, register-only leaf. For anything
else (control flow, memory, calls) it is a **hard error**: a non-zero exit and
**nothing on stdout** — flowref never prints C it cannot stand behind. Closing
those gaps (parameters, memory, full control flow) is the job, not an excuse; the
current edge is in *Limitations*.

```text
$ flowref decompile a.out has_a_loop ; echo "exit=$?"
error: function is not faithfully liftable (control flow / memory / calls); flowref refuses to emit unverified C
exit=5
```

## How it works

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

Faithful output is the standard; today flowref *meets* it only for straight-line,
register-only leaf functions (equivalence proven 4/4). Everything else — control
flow, memory, calls, parameters beyond simple register args, float/struct/varargs
ABI — is an **open gap, not a finished feature**, and `decompile` refuses it with
a hard error rather than emit something unverified. `xref` and `list` still work
on any binary. Closing these gaps (so more functions lift *faithfully*, not just
*compilably*) is the roadmap; see `decompile-bench/README.md`.

## License

MIT (see `LICENSE`). Disassembly via
[`lean-capstone`](https://github.com/fire/lean-capstone) (Capstone, BSD-3).
Evaluated against Decompile-Bench (Tan, Tian, Qi et al., 2025; see `CITATIONS.bib`).
