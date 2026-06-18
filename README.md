# FlowrefDecompiler

Point it at a binary, get back compilable C you can actually read. A
control-flow-aware xref finder and a small decompiler, written in Lean 4. For
simple functions it goes further and machine-checks that the C returns the
same value as the source.
