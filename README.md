# flowref

**Control-flow-aware cross-reference search over machine-code disassembly, in Lean 4.**

A linear disassembler lists instructions but won't tell you *where a constant or
address is actually used* — the value is frequently built in one basic block and
consumed in another, so a straight-line scan loses the connection. `flowref`
recovers it by walking the control-flow graph and tracking constant values
through it.

## The idea — a "witness DAG", found by property-based search

- A **def** materialises a constant base `B` into a register `R` at instruction `i`.
- A **use** at instruction `j` forms `R + disp` and equals the target address.
- They're linked by a control-flow path `i → … → j` along which `R` is never
  clobbered — that path is the **witness**.

Instead of writing a bespoke fixpoint analysis, the search is posed as a
property and discharged with [`plausible`](https://github.com/leanprover-community/plausible):

> `∀ candidate def-witness, ¬(it reaches a target-hitting use)`

A **counterexample to that property is exactly a witness** that locates the
cross-block reference. This finds the case a linear constant-propagation pass
misses: a base set in block A and used in block B reachable from A.

Disassembly comes from [Capstone](https://github.com/capstone-engine/capstone),
so the same engine works on every architecture Capstone supports. **x86** (32-bit)
and **PowerPC** (64-bit, big-endian) are wired up here; adding another is a few
lines (`defOf` / `useDisp` / `branchTarget` / `clobbers` / `isUncondJmp`).

## Build

```bash
thirdparty/capstone/build.sh   # clone + build libcapstone.a once (needs git, cmake, a C compiler)
lake build                     # builds the `flowref` executable
```

## Usage

```
flowref <binary> <arch> <targetHex> <fileOffHex> <vaddrHex> <lenHex>
```

| arg          | meaning                                                        |
|--------------|----------------------------------------------------------------|
| `binary`     | path to the file to analyse                                    |
| `arch`       | `x86` or `ppc` (default `x86`)                                 |
| `targetHex`  | the address/constant to find references to (e.g. `0x4e54a3`)   |
| `fileOffHex` | start offset of the region to disassemble                      |
| `vaddrHex`   | virtual/load address that `fileOff` maps to                    |
| `lenHex`     | length of the region to disassemble                            |

The file offset and load address are separate arguments because they differ in
most executable formats (sections are mapped to addresses unrelated to their
on-disk position). Read the mapping from the file's section table first.

### Example

```bash
# Find where the address 0x550e70 is referenced within a .text window.
flowref ./program x86 0x550e70 0x1000 0x401000 0x111220
# → FOUND a witness DAG to target … ~ def @0x… (reg=…) → use @0x…
```

It prints the candidate def-witnesses, and for each one that reaches the target
the located `def → use` pair (with addresses), so you can jump straight to the
referencing code.

## How it works (internals)

1. Disassemble the region with Capstone into `(addr, mnemonic, operands)`.
2. Build a successor map (fall-through + branch/call edge) — the CFG.
3. Collect **def** instructions that materialise a constant near the target.
4. For each def, BFS forward over the CFG, preserving the base register until it
   is clobbered, and report a **use** whose `value + displacement == target`.
5. Drive the per-def search with `plausible`'s counterexample mechanism.

## Status & limitations

- Pattern coverage is intentionally small and conservative (clear, auditable
  rules over Capstone's textual operands rather than a full IR). It is meant as
  a lead-finder for reverse engineering, not a sound decompiler.
- It tracks **register-materialised** constants (`mov`/`lis`+`addi`/…). Values
  loaded *whole* from a table (e.g. a PowerPC TOC pointer) are not yet modelled;
  adding a table-load `defOf` is a natural extension.
- The CFG walk is bounded (depth cap) and ignores indirect branches.

## License

`flowref` is MIT-licensed (see `LICENSE`). The vendored Capstone headers under
`thirdparty/capstone/include` are BSD-3-Clause (© the Capstone authors); the
build script fetches the matching Capstone sources at build time.
