# ── Phase 2: Core Correctness ──

@testitem "EMA: Hand-Calculated Reference (period=3)" tags = [:feature, :ema, :reference] begin
    using Backtest, Test

    # α = 2/(3+1) = 0.5, SMA seed = (10+11+12)/3 = 11.0
    prices = Float64[10, 11, 12, 13, 14, 15]
    ema = calculate_feature(EMA(3), prices)

    @test length(ema) == 6
    @test all(isnan, ema[1:2])
    @test ema[3] ≈ 11.0                # SMA seed
    @test ema[4] ≈ 12.0                # 0.5×13 + 0.5×11.0
    @test ema[5] ≈ 13.0                # 0.5×14 + 0.5×12.0
    @test ema[6] ≈ 14.0                # 0.5×15 + 0.5×13.0
end

@testitem "EMA: Hand-Calculated Reference (period=5)" tags = [:feature, :ema, :reference] begin
    using Backtest, Test

    # α = 2/(5+1) = 1/3, β = 2/3, SMA seed = (2+4+6+8+10)/5 = 6.0
    prices = Float64[2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    ema = calculate_feature(EMA(5), prices)

    @test length(ema) == 10
    @test all(isnan, ema[1:4])
    @test ema[5] ≈ 6.0                 # SMA seed
    @test ema[6] ≈ 8.0                 # 1/3×12 + 2/3×6
    @test ema[7] ≈ 10.0                # 1/3×14 + 2/3×8
    @test ema[8] ≈ 12.0                # 1/3×16 + 2/3×10
    @test ema[9] ≈ 14.0                # 1/3×18 + 2/3×12
    @test ema[10] ≈ 16.0               # 1/3×20 + 2/3×14
end

@testitem "EMA: SMA Seed Correctness" tags = [:feature, :ema, :unit] begin
    using Backtest, Test

    prices = Float64[10, 20, 30, 40, 50]

    @test Backtest._sma_seed(prices, 3) ≈ 20.0
    @test Backtest._sma_seed(prices, 5) ≈ 30.0
    @test Backtest._sma_seed(prices, 1) ≈ 10.0

    prices32 = Float32[1, 2, 3]
    result = Backtest._sma_seed(prices32, 3)
    @test result isa Float32
    @test result ≈ 2.0f0
end

@testitem "EMA: Mathematical Properties" tags = [:feature, :ema, :property] setup = [
    TestData
] begin
    using Backtest, Test, Statistics

    prices = TestData.make_trending_prices(:up; n=200, start=50.0, step=0.5)

    ema = calculate_feature(EMA(10), prices)
    @test length(ema) == length(prices)

    valid = filter(!isnan, ema)
    @test minimum(valid) >= minimum(prices) - eps()
    @test maximum(valid) <= maximum(prices) + eps()

    flat = TestData.make_flat_prices(; price=42.0, n=200)
    ema_flat = calculate_feature(EMA(10), flat)
    @test all(ema_flat[10:end] .≈ 42.0)

    sine_prices = [100.0 + 10.0 * sin(2π * i / 20) for i in 1:200]
    ema_short = calculate_feature(EMA(5), sine_prices)
    ema_long = calculate_feature(EMA(20), sine_prices)
    @test var(diff(ema_long[21:end])) < var(diff(ema_short[21:end]))

    ema_up = calculate_feature(EMA(5), prices)
    @test all(diff(ema_up[6:end]) .> 0)

    prices_down = TestData.make_trending_prices(:down; n=200, start=200.0, step=0.5)
    ema_down = calculate_feature(EMA(5), prices_down)
    @test all(diff(ema_down[6:end]) .< 0)

    @test all(ema_up[11:end] .< prices[11:end])
    @test all(ema_down[11:end] .> prices_down[11:end])
end

@testitem "EMA: Type Stability" tags = [:feature, :ema, :stability] begin
    using Backtest, Test

    prices64 = Float64.(1:50)
    prices32 = Float32.(1:50)

    @test @inferred(calculate_feature(EMA(5), prices64)) isa Vector{Float64}
    @test @inferred(calculate_feature(EMA(5), prices32)) isa Vector{Float32}

    @test @inferred(calculate_feature(EMA(5, 10), prices64)) isa Matrix{Float64}
    @test @inferred(calculate_feature(EMA(5, 10), prices32)) isa Matrix{Float32}

    @test @inferred(Backtest._feature_result(EMA(5), prices64)) isa NamedTuple
    @test @inferred(Backtest._feature_result(EMA(5, 10), prices64)) isa NamedTuple
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "EMA: Edge Case — Period of 1" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    # α = 1.0, β = 0.0 → EMA equals input exactly
    prices = Float64[5, 10, 15, 20, 25]
    ema = calculate_feature(EMA(1), prices)

    @test length(ema) == 5
    @test ema ≈ prices
    @test !any(isnan, ema)
end

@testitem "EMA: Edge Case — Input Length < Period" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices = Float64[1, 2, 3]
    ema = calculate_feature(EMA(5), prices)

    @test length(ema) == 3
    @test all(isnan, ema)
end

@testitem "EMA: Edge Case — Input Length == Period" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices = Float64[10, 20, 30]
    ema = calculate_feature(EMA(3), prices)

    @test length(ema) == 3
    @test all(isnan, ema[1:2])
    @test ema[3] ≈ 20.0
end

@testitem "EMA: Edge Case — Single Element" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices = Float64[42.0]
    ema = calculate_feature(EMA(1), prices)
    @test length(ema) == 1
    @test ema[1] ≈ 42.0

    ema2 = calculate_feature(EMA(2), Float64[42.0])
    @test length(ema2) == 1
    @test isnan(ema2[1])
end

@testitem "EMA: Edge Case — Flat Prices" tags = [:feature, :ema, :edge] setup = [TestData] begin
    using Backtest, Test

    flat = TestData.make_flat_prices(; price=100.0, n=200)
    ema = calculate_feature(EMA(10), flat)

    @test all(isnan, ema[1:9])
    @test all(ema[10:end] .≈ 100.0)
end

@testitem "EMA: Edge Case — Step Function" tags = [:feature, :ema, :edge] setup = [TestData] begin
    using Backtest, Test

    prices = TestData.make_step_prices(; n=200, low=100.0, high=200.0, step_at=101)
    ema = calculate_feature(EMA(10), prices)

    valid = filter(!isnan, ema)

    @test minimum(valid) >= 100.0 - eps()
    @test maximum(valid) <= 200.0 + eps()
    @test all(ema[50:100] .≈ 100.0)
    @test all(diff(ema[101:120]) .> 0)
    @test ema[end] > 199.0
end

@testitem "EMA: Edge Case — Very Large Prices" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices = fill(50_000.0, 200)
    ema = calculate_feature(EMA(10), prices)

    @test all(ema[10:end] .≈ 50_000.0)
    @test all(isfinite, filter(!isnan, ema))
end

@testitem "EMA: Edge Case — Very Small Prices" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices = fill(0.001, 200)
    ema = calculate_feature(EMA(10), prices)

    @test all(ema[10:end] .≈ 0.001)
    @test all(isfinite, filter(!isnan, ema))
end

@testitem "EMA: Float32 Type Preservation" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    prices32 = Float32.(1:100)

    ema = calculate_feature(EMA(5), prices32)
    @test eltype(ema) == Float32
    @test length(ema) == 100

    result = calculate_feature(EMA(5, 10), prices32)
    @test eltype(result) == Float32
    @test size(result) == (100, 2)
end

# ── Phase 3: Robustness — Multi-Period & Interface ──

@testitem "EMA: Multi-Period Matches Individual Calculations" tags = [:feature, :ema, :unit] begin
    using Backtest, Test

    prices = Float64.(1:100)
    multi = calculate_feature(EMA(5, 10, 20), prices)

    ema5 = calculate_feature(EMA(5), prices)
    ema10 = calculate_feature(EMA(10), prices)
    ema20 = calculate_feature(EMA(20), prices)

    @test size(multi) == (100, 3)
    @test isequal(multi[:, 1], ema5)
    @test isequal(multi[:, 2], ema10)
    @test isequal(multi[:, 3], ema20)
end

@testitem "EMA: Named Result Builder (_feature_result)" tags = [:feature, :ema, :unit] begin
    using Backtest, Test

    prices = Float64.(1:50)

    nt = Backtest._feature_result(EMA(10), prices)
    @test nt isa NamedTuple
    @test haskey(nt, :ema_10)
    @test isequal(nt.ema_10, calculate_feature(EMA(10), prices))

    nt2 = Backtest._feature_result(EMA(5, 20), prices)
    @test haskey(nt2, :ema_5)
    @test haskey(nt2, :ema_20)
    @test length(keys(nt2)) == 2
end

@testitem "EMA: Callable Interface with PriceBars" tags = [:feature, :ema, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    result = EMA(10)(bars)
    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test result.bars === bars
    @test length(result.ema_10) == 100

    result2 = EMA(10, 20)(bars)
    @test haskey(result2, :bars)
    @test haskey(result2, :ema_10)
    @test haskey(result2, :ema_20)
end

@testitem "EMA: Callable Interface with NamedTuple (chaining)" tags = [
    :feature, :ema, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    step1 = EMA(10)(bars)
    step2 = EMA(20)(step1)

    @test haskey(step2, :bars)
    @test haskey(step2, :ema_10)
    @test haskey(step2, :ema_20)
    @test step2.bars === bars
end

# ── Phase 3: Robustness — Constructor & Error Paths ──

@testitem "EMA: Constructor Validation" tags = [:feature, :ema, :edge] begin
    using Backtest, Test

    @test_throws ArgumentError EMA(0)
    @test_throws ArgumentError EMA(-1)
    @test_throws ArgumentError EMA(-10)

    @test_throws ArgumentError EMA(3, 3)
    @test_throws ArgumentError EMA(5, 10, 5)

    @test EMA(1) isa EMA
    @test EMA(100) isa EMA
    @test EMA(1, 2, 3) isa EMA
end

# ── Phase 3: Robustness — Performance ──

@testitem "EMA: Zero Allocations in Kernel" tags = [:feature, :ema, :stability] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    dest = similar(prices)
    p = 10
    n = length(prices)
    α = 2.0 / (p + 1)
    β = 1.0 - α
    dest[p] = Backtest._sma_seed(prices, p)

    Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)

    # Wrapper avoids Core.Box allocation from captured variables
    allocs(dest, prices, p, n, α, β) =
        @allocated Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)

    actual_kernel = minimum([@allocated(allocs(dest, prices, p, n, α, β)) for _ in 1:3])
    @test actual_kernel == 0

    Backtest._sma_seed(prices, 10)
    allocs_seed(prices) = @allocated Backtest._sma_seed(prices, 10)

    actual_seed = minimum([@allocated(allocs_seed(prices)) for _ in 1:3])
    @test actual_seed == 0
end

@testitem "EMA: Allocation — _calculate_emas (multi-period)" tags = [
    :feature, :ema, :allocation
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    periods = [5, 10, 20]

    Backtest._calculate_emas(prices, periods)

    expected_data = sizeof(Float64) * length(prices) * length(periods)
    budget = expected_data + 512

    allocs_emas(prices, periods) = @allocated Backtest._calculate_emas(prices, periods)

    actual = minimum([@allocated(allocs_emas(prices, periods)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "EMA: Kernel Unrolled Covers All Remainders" tags = [:feature, :ema, :unit] begin
    using Backtest, Test

    # Vary n so that (n - period) mod 4 covers all remainders 0..3
    period = 2
    α = 2.0 / (period + 1)

    for n in 6:9
        prices = Float64.(1:n)
        ema = calculate_feature(EMA(period), prices)

        @test length(ema) == n
        @test isnan(ema[1])
        @test !isnan(ema[2])

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

# ── Phase 4: Deep Analysis ──

@testitem "EMA: Static Analysis (JET.jl)" tags = [:feature, :ema, :stability] begin
    using Backtest, Test, JET

    prices = collect(1.0:100.0)

    @test_opt target_modules = (Backtest,) calculate_feature(EMA(10), prices)
    @test_call target_modules = (Backtest,) calculate_feature(EMA(10), prices)
end

# ── Phase 5: Allocation Budget Tests ──
#
# Budget methodology: data bytes + fixed overhead constant.
# See TESTING.md §6b for rationale on overhead constants and the
# Min-of-N measurement pattern.

@testitem "EMA: Allocation — _calculate_ema (single period)" tags = [
    :feature, :ema, :allocation
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)

    Backtest._calculate_ema(prices, 10)

    expected_data = sizeof(Float64) * length(prices)
    budget = expected_data + 512

    allocs_ema(prices) = @allocated Backtest._calculate_ema(prices, 10)

    actual = minimum([@allocated(allocs_ema(prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "EMA: Allocation — _calculate_ema Float32" tags = [:feature, :ema, :allocation] begin
    using Backtest, Test

    prices = collect(Float32.(1:200))

    Backtest._calculate_ema(prices, 10)

    expected_data = sizeof(Float32) * length(prices)
    budget = expected_data + 512

    allocs_ema(prices) = @allocated Backtest._calculate_ema(prices, 10)

    actual = minimum([@allocated(allocs_ema(prices)) for _ in 1:3])

    @test actual <= budget
end

@testitem "EMA: Allocation — calculate_feature single period" tags = [
    :feature, :ema, :allocation
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    feat = EMA(10)

    calculate_feature(feat, prices)

    expected_data = sizeof(Float64) * length(prices)
    budget = expected_data + 512

    allocs_calc(feat, prices) = @allocated calculate_feature(feat, prices)

    actual = minimum([@allocated(allocs_calc(feat, prices)) for _ in 1:3])

    @test actual <= budget
end

@testitem "EMA: Allocation — calculate_feature multi-period" tags = [
    :feature, :ema, :allocation
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    feat = EMA(5, 10, 20)
    n_periods = 3

    calculate_feature(feat, prices)

    expected_data = sizeof(Float64) * length(prices) * n_periods
    budget = expected_data + 1536

    allocs_calc(feat, prices) = @allocated calculate_feature(feat, prices)

    actual = minimum([@allocated(allocs_calc(feat, prices)) for _ in 1:3])

    @test actual <= budget
end

@testitem "EMA: Allocation — EMA functor with PriceBars" tags = [
    :feature, :ema, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feat = EMA(10)

    feat(bars)

    expected_data = sizeof(Float64) * 200
    budget = expected_data + 1024

    allocs_functor(feat, bars) = @allocated feat(bars)

    actual = minimum([@allocated(allocs_functor(feat, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "EMA: Allocation — EMA functor with NamedTuple (chaining)" tags = [
    :feature, :ema, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feat1 = EMA(10)
    feat2 = EMA(20)

    step1 = feat1(bars)

    feat2(step1)

    expected_data = sizeof(Float64) * 200
    budget = expected_data + 1024

    allocs_chain(feat2, step1) = @allocated feat2(step1)

    actual = minimum([@allocated(allocs_chain(feat2, step1)) for _ in 1:3])

    @test actual <= budget
end

@testitem "EMA: Allocation — EMA functor multi-period with PriceBars" tags = [
    :feature, :ema, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feat = EMA(5, 10, 20)

    feat(bars)

    expected_data = sizeof(Float64) * 200 * 3
    budget = expected_data + 1024

    allocs_functor(feat, bars) = @allocated feat(bars)

    actual = minimum([@allocated(allocs_functor(feat, bars)) for _ in 1:3])

    @test actual <= budget
end