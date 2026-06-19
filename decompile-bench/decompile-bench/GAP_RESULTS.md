# Gap Benchmark Results

**Date**: 2026-06-19  
**Run**: 20260619T150512Z  
**Training set**: 71 fixtures (69 original + 2 gap fixtures)

## Summary

| Gap | Status | Fixture | Result | Notes |
|-----|--------|---------|--------|-------|
| 1. div/idiv guard | OPEN | div_guarded | INCOMPARABLE | unsafe compiles, strict refuses - can't prove divisor != 0 |
| 2. 64-bit magic div | OPEN | div_by_10 | NOT-EQUIVALENT | imul r64; shr $35 pattern not recognized |
| 3. chained branch-phi | CLOSED | nested_select_cfg | EQUIVALENT | Already in training set |
| 4. loop oracle | CLOSED | sum_to_n | EQUIVALENT | Already in training set |
| 5. type propagation | PENDING | - | N/A | Readability-only, no functional fixture |
| 6. variable coalescing | PENDING | - | N/A | Readability-only, no functional fixture |

## Detailed Results

### Gap 1: Scalar div/idiv with zero-divisor preconditions

**Fixture**: `div_guarded.c`
```c
uint32_t div_guarded(uint32_t a, uint32_t b) {
  if (b == 0) {
    return 0;
  }
  return a / b;  // b is provably nonzero here
}
```

**Assembly**: Uses `testl %esi, %esi` / `je` guard + `divl %esi`

**Result**: INCOMPARABLE (strict refuses, unsafe compiles)

**Root cause**: The decompiler cannot prove that the reaching definition of the divisor at the `divl` instruction is nonzero. The path-fact lattice (Gap 1 design) is not yet implemented.

### Gap 2: 64-bit magic-constant division

**Fixture**: `div_by_10.c`
```c
uint32_t div_by_10(uint32_t x) {
  return x / 10;
}
```

**Assembly**: 
```asm
movl    %edi, %eax
movl    $3435973837, %edx  # magic constant
imulq   %rdx, %rax         # 64-bit multiply
shrq    $35, %rax          # shift right
```

**Result**: NOT-EQUIVALENT (oracle finds divergence)

**Root cause**: The 32-bit `Word` IL cannot faithfully model the 64-bit multiply pattern. The compound-pattern theorem (Gap 2 design) is not yet implemented.

## Recommendations

1. **Gap 1 (div guard)**: Implement path-fact lattice as described in OPEN_GAPS.md. Start with the simple guarded division fixture, then expand to `gcd`.

2. **Gap 2 (64-bit magic div)**: Implement the compound-pattern recognizer for `imul r64; shr $k` sequences. The theorem should record the magic constant, shift amount, and input range.

3. **Gaps 3-4**: Already closed - no action needed.

4. **Gaps 5-6**: Readability improvements - can be addressed after functional gaps are closed.

## Next Steps

- Implement path-fact lattice for Gap 1
- Implement 64-bit magic-constant division recognizer for Gap 2
- Re-run gap-bench.sh after each implementation
- Add fixtures to training set once they achieve EQUIVALENT status
