# ─────────────────────────────────────────────────────────────────────────────
# CUSUM Test Plan
# ─────────────────────────────────────────────────────────────────────────────
#
# This file contains the test plan for the CUSUM indicator (src/indicator/cusum.jl).
# Tests are organized by phase following TESTING.md's phased approach.
# Each @testitem follows the same conventions as ema_tests.jl.
#
# ── Source Code Summary ──
#
# CUSUM{T<:AbstractFloat}: multiplier::T, span::Int, expected_value::T
# Constructor: CUSUM(multiplier; span=100, expected_value=0.0)
#   - multiplier must be > 0 (_positive_float)
#   - span must be > 0 (_natural)
#
# _calculate_cusum algorithm:
#   - Returns Vector{Int8} of length n, values ∈ {-1, 0, 1}
#   - Warmup: indices 1–101 always zero; if n ≤ 101, warns and returns all zeros
#   - Warmup (2:101): accumulates squared log-returns → initial ema_sq_mean
#   - Post-warmup (102:n): tracks s_pos/s_neg CUSUM accumulators against
#     adaptive threshold (sqrt(ema_sq_mean) * multiplier); emits ±1 on breach
#   - Uses log(prices[i]) → DomainError on negative prices
#
# _indicator_result: returns (cusum=vals,) NamedTuple
# Callable interface: inherited from AbstractIndicator (PriceBars / NamedTuple)
#
# ── Tag Registration ──
# Component tag :cusum added to TESTING.md tag taxonomy table.
#
# ── Test Count: 20 @testitems ──
#
#   Phase 2 (Core Correctness):     4 items
#   Phase 3 (Edge Cases):           9 items
#   Phase 3 (Interface):            3 items
#   Phase 4 (Deep Analysis):        1 item
#   Phase 5 (Allocation Budgets):   3 items
#
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Core Correctness
# ─────────────────────────────────────────────────────────────────────────────

# 1. Hand-Calculated Reference
# Build 110+ points: flat prices during warmup, then a sharp spike.
# Hand-calculate: log-returns during warmup are zero (flat prices),
# so ema_sq_mean ≈ 0 after warmup. Any non-zero log-return post-warmup
# will exceed threshold ≈ sqrt(1e-16) * multiplier ≈ 0.
# Use a controlled scenario: flat 100.0 for 101 bars, then a jump to
# a higher price at index 102+. Verify:
#   - Indices 1:101 are all zero
#   - Signal fires at the expected index with expected sign (+1 for up)
#   - Signal value is Int8(1)
#
# tags = [:indicator, :cusum, :reference]

# 2. Output Domain Property
# For various inputs (make_pricebars close, trending, sine-wave), verify:
#   - length(output) == length(input)
#   - eltype(output) == Int8
#   - all values ∈ {Int8(-1), Int8(0), Int8(1)}
#
# tags = [:indicator, :cusum, :property], setup = [TestData]

# 3. Type Stability
# @inferred tests:
#   - calculate_indicator(CUSUM(1.0), prices64) isa Vector{Int8}
#   - calculate_indicator(CUSUM(1.0f0), prices32) — check if Float32 prices
#     work or if MethodError occurs (document actual behavior)
#   - Backtest._indicator_result(CUSUM(1.0), prices64) isa NamedTuple
#
# tags = [:indicator, :cusum, :stability]

# 4. Mathematical Properties
# Invariants for any valid input with n > 101:
#   - Warmup invariant: output[1:101] always all zeros
#   - Flat prices → all zeros (log-returns are zero, accumulators never grow)
#   - Higher multiplier → fewer or equal signals (compare CUSUM(1.0) vs CUSUM(5.0))
#   - Signal sparsity: accumulators reset after signal, so consecutive signals
#     require re-accumulation (verify no two signals at adjacent indices unless
#     both accumulators fire independently)
#   - Directional consistency: strong uptrend spike → +1, strong downtrend → -1
#
# tags = [:indicator, :cusum, :property], setup = [TestData]

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Edge Cases
# ─────────────────────────────────────────────────────────────────────────────

# 5. Constructor Validation
# Invalid:
#   - CUSUM(0.0)       → ArgumentError (multiplier must be > 0)
#   - CUSUM(-1.0)      → ArgumentError
#   - CUSUM(1.0; span=0)  → ArgumentError (span must be positive integer)
#   - CUSUM(1.0; span=-1) → ArgumentError
# Valid:
#   - CUSUM(1.0) isa CUSUM
#   - CUSUM(0.5; span=50) isa CUSUM
#   - CUSUM(1.0; expected_value=0.01) isa CUSUM
#   - CUSUM(3.0; span=200, expected_value=0.005) isa CUSUM
#
# tags = [:indicator, :cusum, :edge]

# 6. Data Shorter Than Warmup
# n = 50:  @test_logs (:warn,), returns all zeros, length == 50
# n = 101: exactly at boundary → warns and returns all zeros (n <= warmup_idx=101)
# n = 102: minimum post-warmup → no warning, one post-warmup index (102)
#
# tags = [:indicator, :cusum, :edge]

# 7. Negative Prices
# Negative price in warmup range → DomainError from log()
# Negative price after warmup → DomainError from log()
# Zero price: log(0.0) = -Inf → doesn't throw, but downstream squared
#   returns become Inf, verify behavior (output may contain signals or zeros
#   but should not throw)
#
# tags = [:indicator, :cusum, :edge]

# 8. Very Large Prices
# fill(50_000.0, 200) → all output values ∈ {-1, 0, 1}, no overflow
# Flat large prices → all zeros (log-returns are zero)
# Large prices with spikes → signals still valid
#
# tags = [:indicator, :cusum, :edge]

# 9. Very Small Prices
# fill(0.001, 200) → all output values valid, no underflow
# log(0.001) is finite (-6.9), squared returns are small but valid
# Flat small prices → all zeros
#
# tags = [:indicator, :cusum, :edge]

# 10. Flat Prices
# fill(100.0, 200) → all zeros
# Rationale: log-returns are exactly 0.0, s_pos and s_neg never accumulate,
# threshold is sqrt(1e-16) * mult ≈ 0, but accumulators are also 0
#
# tags = [:indicator, :cusum, :edge], setup = [TestData]

# 11. Step Function
# Flat 100.0 for 101 bars, then jump to 200.0:
#   - Should trigger positive signal near the step (index 102)
# Flat 100.0 for 101 bars, then drop to 50.0:
#   - Should trigger negative signal near the drop
# Verify boundedness: all outputs ∈ {-1, 0, 1}
#
# tags = [:indicator, :cusum, :edge], setup = [TestData]

# 12. Float32 Construction
# CUSUM(1.0f0) → CUSUM{Float32}
# CUSUM(1.0f0).multiplier isa Float32
# calculate_indicator with Float64 prices: the method signature requires
#   prices::AbstractVector{T} where T matches the CUSUM{T} type.
#   Test whether Float32 CUSUM with Float64 prices throws MethodError
#   (document actual behavior for users).
# If prices must match, test with Float32 prices to confirm it works.
#
# tags = [:indicator, :cusum, :edge]

# 13. Monotone Trending Prices
# Strong uptrend (large step): should eventually trigger positive signals
# Strong downtrend (large step): should eventually trigger negative signals
# Gentle trend (tiny step) with high multiplier: may not trigger any signals
# Verify signal direction matches trend direction
#
# tags = [:indicator, :cusum, :edge]

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Interface
# ─────────────────────────────────────────────────────────────────────────────

# 14. Named Result Builder (_indicator_result)
# Returns NamedTuple with exactly one key: :cusum
# Value isequal to calculate_indicator output
# length(keys(nt)) == 1
#
# tags = [:indicator, :cusum, :unit]

# 15. Callable Interface with PriceBars
# CUSUM(1.0)(bars) returns NamedTuple
# Has keys :bars and :cusum
# result.bars === bars (identity, not copy)
# length(result.cusum) == n
# eltype(result.cusum) == Int8
#
# tags = [:indicator, :cusum, :unit], setup = [TestData]

# 16. Callable Interface with NamedTuple (chaining)
# Chain: step1 = EMA(10)(bars); step2 = CUSUM(1.0)(step1)
# Result has :bars, :ema_10, and :cusum
# Original bars preserved: step2.bars === bars
# EMA values preserved: step2.ema_10 matches step1.ema_10
#
# tags = [:indicator, :cusum, :unit], setup = [TestData]

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — Deep Analysis
# ─────────────────────────────────────────────────────────────────────────────

# 17. Static Analysis (JET.jl)
# @test_opt target_modules=(Backtest,) calculate_indicator(CUSUM(1.0), prices)
# @test_call target_modules=(Backtest,) calculate_indicator(CUSUM(1.0), prices)
# Uses prices = collect(1.0:200.0) — must be longer than warmup
#
# tags = [:indicator, :cusum, :stability]

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5 — Allocation Budget Tests
# ─────────────────────────────────────────────────────────────────────────────
#
# CUSUM allocates a Vector{Int8} result — much smaller than EMA's Float64
# vectors. Budget = sizeof(Int8) * n + overhead.
#
# Pattern (same as EMA):
#   1. Warmup target function
#   2. Define wrapper function (avoid Core.Box)
#   3. Warmup wrapper
#   4. Measure on second call
# ─────────────────────────────────────────────────────────────────────────────

# 18. Allocation — _calculate_cusum
# Budget: sizeof(Int8) * n + 512 bytes overhead
# For n=200: budget = 200 + 512 = 712; double-allocation = 400 → caught
# Sanity: actual > 0 (must allocate result vector)
#
# tags = [:indicator, :cusum, :allocation]

# 19. Allocation — calculate_indicator
# Same budget as _calculate_cusum (thin wrapper)
#
# tags = [:indicator, :cusum, :allocation]

# 20. Allocation — CUSUM functor with PriceBars
# Budget: sizeof(Int8) * n + 1024 bytes (NamedTuple merge overhead)
# Sanity: actual > 0
#
# tags = [:indicator, :cusum, :allocation], setup = [TestData]
