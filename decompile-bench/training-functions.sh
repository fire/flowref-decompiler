#!/usr/bin/env bash
# Shared self-authored training fixture list.
#
# Keep this as plain shell data so benchmark and materialization scripts cannot
# drift: each name maps to exactly one algorithms/<name>.c or asm/<name>.S file.
#
# Gap fixtures (OPEN_GAPS.md) are included here but tested separately via
# gap-bench.sh to track progress on each gap independently.
TRAINING_FUNCS="id32 add2 umax umin abs_diff gray_code avg_floor \
       isolate_lowest_bit clear_lowest_bit clamp max3 min3 sat_add sat_sub diff_or_zero \
       parity bit_merge mul5 lin2 combine4 pack16 mul7 to_byte to_half med3 \
       to_sbyte to_shalf shift_r shift_l rotate_right ctz_nonzero bsr_nonzero lzcnt_nonzero bswap32 add_high_carry mul_high_u32 mul_low_u32 mul_imm addr_calc scale8 nand \
       sel_nz is_zero cmp_lt cmp_le cmp_eq nonzero is_even in_range branch_select branch_select_slt branch_phi_add branch_phi_twouse nested_select_cfg \
       russian_mul abs_int signed_lt \
       sum_to_n factorial fib_iter popcount log2_floor reverse_bits digit_count \
       isqrt collatz_steps signed_loop_branch loop_signed_jg zero_ext_loop \
       div_guarded div_by_10"
