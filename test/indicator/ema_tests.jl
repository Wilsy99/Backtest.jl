# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Core Correctness
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Hand-Calculated Reference (period=3)" tags = [:indicator, :ema, :reference] begin
    using Backtest, Test

    # α = 2/(3+1) = 0.5, SMA seed = (10+11+12)/3 = 11.0
    prices = Float64[10, 11, 12, 13, 14, 15]
    ema = calculate_indicator(EMA(3), prices)

    @test length(ema) == 6
    @test all(isnan, ema[1:2])
    @test ema[3] ≈ 11.0                # SMA seed
    @test ema[4] ≈ 12.0                # 0.5×13 + 0.5×11.0
    @test ema[5] ≈ 13.0                # 0.5×14 + 0.5×12.0
    @test ema[6] ≈ 14.0                # 0.5×15 + 0.5×13.0
end

@testitem "EMA: Hand-Calculated Reference (period=5)" tags = [:indicator, :ema, :reference] begin
    using Backtest, Test

    # α = 2/(5+1) = 1/3, β = 2/3, SMA seed = (2+4+6+8+10)/5 = 6.0
    prices = Float64[2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    ema = calculate_indicator(EMA(5), prices)

    @test length(ema) == 10
    @test all(isnan, ema[1:4])
    @test ema[5] ≈ 6.0                # SMA seed
    @test ema[6] ≈ 8.0                # 1/3×12 + 2/3×6
    @test ema[7] ≈ 10.0               # 1/3×14 + 2/3×8
    @test ema[8] ≈ 12.0               # 1/3×16 + 2/3×10
    @test ema[9] ≈ 14.0               # 1/3×18 + 2/3×12
    @test ema[10] ≈ 16.0               # 1/3×20 + 2/3×14
end

@testitem "EMA: SMA Seed Correctness" tags = [:indicator, :ema, :unit] begin
    using Backtest, Test

    prices = Float64[10, 20, 30, 40, 50]

    @test Backtest._sma_seed(prices, 3) ≈ 20.0      # (10+20+30)/3
    @test Backtest._sma_seed(prices, 5) ≈ 30.0      # (10+20+30+40+50)/5
    @test Backtest._sma_seed(prices, 1) ≈ 10.0      # just prices[1]

    # Float32 type preservation
    prices32 = Float32[1, 2, 3]
    result = Backtest._sma_seed(prices32, 3)
    @test result isa Float32
    @test result ≈ 2.0f0
end

@testitem "EMA: Mathematical Properties" tags = [:indicator, :ema, :property] setup = [
    TestData
] begin
    using Backtest, Test, Statistics

    prices = TestData.make_trending_prices(:up; n=200, start=50.0, step=0.5)

    # ── Output length ──
    ema = calculate_indicator(EMA(10), prices)
    @test length(ema) == length(prices)

    # ── Boundedness: EMA cannot exceed input range ──
    valid = filter(!isnan, ema)
    @test minimum(valid) >= minimum(prices) - eps()
    @test maximum(valid) <= maximum(prices) + eps()

    # ── Convergence: constant input → EMA equals that constant ──
    flat = TestData.make_flat_prices(; price=42.0, n=200)
    ema_flat = calculate_indicator(EMA(10), flat)
    @test all(ema_flat[10:end] .≈ 42.0)

    # ── Smoothness: longer period → lower variance of differences ──
    sine_prices = [100.0 + 10.0 * sin(2π * i / 20) for i in 1:200]
    ema_short = calculate_indicator(EMA(5), sine_prices)
    ema_long = calculate_indicator(EMA(20), sine_prices)
    @test var(diff(ema_long[21:end])) < var(diff(ema_short[21:end]))

    # ── Directionality: monotone increasing input → monotone increasing EMA ──
    ema_up = calculate_indicator(EMA(5), prices)
    @test all(diff(ema_up[6:end]) .> 0)

    # Also for decreasing
    prices_down = TestData.make_trending_prices(:down; n=200, start=200.0, step=0.5)
    ema_down = calculate_indicator(EMA(5), prices_down)
    @test all(diff(ema_down[6:end]) .< 0)

    # ── Lag: on a rising linear trend, EMA lags below price ──
    @test all(ema_up[11:end] .< prices[11:end])

    # On a falling trend, EMA lags above price
    @test all(ema_down[11:end] .> prices_down[11:end])
end

@testitem "EMA: Type Stability" tags = [:indicator, :ema, :stability] begin
    using Backtest, Test

    prices64 = Float64.(1:50)
    prices32 = Float32.(1:50)

    # Public API — single period
    @test @inferred(calculate_indicator(EMA(5), prices64)) isa Vector{Float64}
    @test @inferred(calculate_indicator(EMA(5), prices32)) isa Vector{Float32}

    # Public API — multi-period
    @test @inferred(calculate_indicator(EMA(5, 10), prices64)) isa Matrix{Float64}
    @test @inferred(calculate_indicator(EMA(5, 10), prices32)) isa Matrix{Float32}

    # Internal: named result builder
    @test @inferred(Backtest._indicator_result(EMA(5), prices64)) isa NamedTuple
    @test @inferred(Backtest._indicator_result(EMA(5, 10), prices64)) isa NamedTuple
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Edge Cases
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Edge Case — Period of 1" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    # α = 2/(1+1) = 1.0, β = 0.0  →  EMA should equal input exactly
    prices = Float64[5, 10, 15, 20, 25]
    ema = calculate_indicator(EMA(1), prices)

    @test length(ema) == 5
    @test ema ≈ prices
    @test !any(isnan, ema)              # no NaN warmup for period=1
end

@testitem "EMA: Edge Case — Input Length < Period" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    prices = Float64[1, 2, 3]
    ema = calculate_indicator(EMA(5), prices)

    @test length(ema) == 3
    @test all(isnan, ema)
end

@testitem "EMA: Edge Case — Input Length == Period" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    # Exactly one valid value (the SMA seed), rest are NaN warmup
    prices = Float64[10, 20, 30]
    ema = calculate_indicator(EMA(3), prices)

    @test length(ema) == 3
    @test all(isnan, ema[1:2])
    @test ema[3] ≈ 20.0                # SMA of [10, 20, 30]
end

@testitem "EMA: Edge Case — Single Element" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    # period=1 with single element → valid
    prices = Float64[42.0]
    ema = calculate_indicator(EMA(1), prices)
    @test length(ema) == 1
    @test ema[1] ≈ 42.0

    # period > 1 with single element → all NaN
    ema2 = calculate_indicator(EMA(2), Float64[42.0])
    @test length(ema2) == 1
    @test isnan(ema2[1])
end

@testitem "EMA: Edge Case — Flat Prices" tags = [:indicator, :ema, :edge] setup = [TestData] begin
    using Backtest, Test

    flat = TestData.make_flat_prices(; price=100.0, n=200)
    ema = calculate_indicator(EMA(10), flat)

    @test all(isnan, ema[1:9])
    @test all(ema[10:end] .≈ 100.0)
end

@testitem "EMA: Edge Case — Step Function" tags = [:indicator, :ema, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    prices = TestData.make_step_prices(; n=200, low=100.0, high=200.0, step_at=101)
    ema = calculate_indicator(EMA(10), prices)

    valid = filter(!isnan, ema)

    # Boundedness
    @test minimum(valid) >= 100.0 - eps()
    @test maximum(valid) <= 200.0 + eps()

    # Before step (after warmup), EMA converges to the low level
    @test all(ema[50:100] .≈ 100.0)

    # After step, EMA must be rising toward 200
    @test all(diff(ema[101:120]) .> 0)

    # Eventually converges near 200 (check last values)
    @test ema[end] > 199.0
end

@testitem "EMA: Edge Case — Very Large Prices" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    prices = fill(50_000.0, 200)
    ema = calculate_indicator(EMA(10), prices)

    @test all(ema[10:end] .≈ 50_000.0)
    @test all(isfinite, filter(!isnan, ema))
end

@testitem "EMA: Edge Case — Very Small Prices" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    prices = fill(0.001, 200)
    ema = calculate_indicator(EMA(10), prices)

    @test all(ema[10:end] .≈ 0.001)
    @test all(isfinite, filter(!isnan, ema))
end

@testitem "EMA: Float32 Type Preservation" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    prices32 = Float32.(1:100)

    # Single period
    ema = calculate_indicator(EMA(5), prices32)
    @test eltype(ema) == Float32
    @test length(ema) == 100

    # Multi-period
    result = calculate_indicator(EMA(5, 10), prices32)
    @test eltype(result) == Float32
    @test size(result) == (100, 2)
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Multi-Period & Interface
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Multi-Period Matches Individual Calculations" tags = [
    :indicator, :ema, :unit
] begin
    using Backtest, Test

    prices = Float64.(1:100)
    multi = calculate_indicator(EMA(5, 10, 20), prices)

    ema5 = calculate_indicator(EMA(5), prices)
    ema10 = calculate_indicator(EMA(10), prices)
    ema20 = calculate_indicator(EMA(20), prices)

    @test size(multi) == (100, 3)
    @test multi[:, 1] ≈ ema5
    @test multi[:, 2] ≈ ema10
    @test multi[:, 3] ≈ ema20
end

@testitem "EMA: Named Result Builder (_indicator_result)" tags = [:indicator, :ema, :unit] begin
    using Backtest, Test

    prices = Float64.(1:50)

    # Single period → NamedTuple with :ema_10
    nt = Backtest._indicator_result(EMA(10), prices)
    @test nt isa NamedTuple
    @test haskey(nt, :ema_10)
    @test nt.ema_10 == calculate_indicator(EMA(10), prices)

    # Multi-period → NamedTuple with :ema_5 and :ema_20
    nt2 = Backtest._indicator_result(EMA(5, 20), prices)
    @test haskey(nt2, :ema_5)
    @test haskey(nt2, :ema_20)
    @test length(keys(nt2)) == 2
end

@testitem "EMA: Callable Interface with PriceBars" tags = [:indicator, :ema, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    # Single period
    result = EMA(10)(bars)
    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test result.bars === bars
    @test length(result.ema_10) == 100

    # Multi-period
    result2 = EMA(10, 20)(bars)
    @test haskey(result2, :bars)
    @test haskey(result2, :ema_10)
    @test haskey(result2, :ema_20)
end

@testitem "EMA: Callable Interface with NamedTuple (chaining)" tags = [
    :indicator, :ema, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    # Chain: EMA(10) then EMA(20) — simulates pipeline composition
    step1 = EMA(10)(bars)
    step2 = EMA(20)(step1)

    @test haskey(step2, :bars)
    @test haskey(step2, :ema_10)         # preserved from step1
    @test haskey(step2, :ema_20)         # added by step2
    @test step2.bars === bars            # original data preserved
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Constructor & Error Paths
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Constructor Validation" tags = [:indicator, :ema, :edge] begin
    using Backtest, Test

    # Invalid: period must be a positive integer
    @test_throws ArgumentError EMA(0)
    @test_throws ArgumentError EMA(-1)
    @test_throws ArgumentError EMA(-10)

    # Invalid: duplicate periods
    @test_throws ArgumentError EMA(3, 3)
    @test_throws ArgumentError EMA(5, 10, 5)

    # Valid constructions
    @test EMA(1) isa EMA
    @test EMA(100) isa EMA
    @test EMA(1, 2, 3) isa EMA
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Performance
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Zero Allocations in Kernel" tags = [:indicator, :ema, :stability] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    dest = similar(prices)
    p = 10
    n = length(prices)
    α = 2.0 / (p + 1)
    β = 1.0 - α
    dest[p] = Backtest._sma_seed(prices, p)

    # Warmup call (JIT compilation)
    Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)

    # Measurement — must be zero allocations
    allocs = @allocated Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)
    @test allocs == 0

    # Also test _sma_seed
    Backtest._sma_seed(prices, 10)   # warmup
    allocs_seed = @allocated Backtest._sma_seed(prices, 10)
    @test allocs_seed == 0
end

@testitem "EMA: Kernel Unrolled Covers All Remainders" tags = [:indicator, :ema, :unit] begin
    using Backtest, Test

    # The kernel processes 4 elements at a time starting from index p+1.
    # For period=2 and varying lengths, the number of elements after the seed is:
    #   n - p = n - 2, and the remainder after unrolling is (n-2) mod 4.
    # Test lengths that produce remainders of 0, 1, 2, 3.

    period = 2
    α = 2.0 / (period + 1)

    for n in 6:9   # (n-2) mod 4 = 0,1,2,3
        prices = Float64.(1:n)
        ema = calculate_indicator(EMA(period), prices)

        @test length(ema) == n
        @test isnan(ema[1])
        @test !isnan(ema[2])

        # Verify against manual scalar recurrence
        expected = Vector{Float64}(undef, n)
        expected[1] = NaN
        expected[2] = Backtest._sma_seed(prices, period)
        for i in 3:n
            expected[i] = α * prices[i] + (1 - α) * expected[i - 1]
        end

        for i in 2:n
            @test ema[i] ≈ expected[i] atol = 1e-10
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — Deep Analysis
# ─────────────────────────────────────────────────────────────────────────────

@testitem "EMA: Static Analysis (JET.jl)" tags = [:indicator, :ema, :stability] begin
    using Backtest, Test, JET

    prices = collect(1.0:100.0)

    # Optimisation issues (type instability inside the body)
    @test_opt target_modules = (Backtest,) calculate_indicator(EMA(10), prices)

    # Method errors (calling a function that doesn't exist for those types)
    @test_call target_modules = (Backtest,) calculate_indicator(EMA(10), prices)
end
