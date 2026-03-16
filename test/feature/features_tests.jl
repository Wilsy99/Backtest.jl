# ── Features Tests ──
#
# Tests for the Features struct that computes multiple named features
# in a single pipeline step with results merged flat into the pipeline
# NamedTuple. Follows the TESTING.md phase structure.

# ── Phase 1: Construction ──

@testitem "Features: Construction" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    @test f isa Features
    @test length(f.operations) == 2

    f3 = Features(:ema_5 => EMA(5), :ema_10 => EMA(10), :cusum => CUSUM(0.5))
    @test length(f3.operations) == 3
end

@testitem "Features: Single Feature Allowed" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    f = Features(:ema_10 => EMA(10))
    @test f isa Features
    @test length(f.operations) == 1
end

# ── Phase 2: Core Correctness — Reference Values ──

@testitem "Features: Results Match Independent Computation" tags = [
    :feature, :features, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    result = f(bars)

    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)

    @test isequal(result.ema_10, compute(EMA(10), bars.close))
    @test isequal(result.ema_20, compute(EMA(20), bars.close))
    @test isequal(result.cusum, compute(CUSUM(1.0), bars.close))
    @test result.bars === bars
end

@testitem "Features: Custom Names" tags = [:feature, :features, :reference] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:fast => EMA(10), :slow => EMA(50))
    result = f(bars)

    @test haskey(result, :fast)
    @test haskey(result, :slow)
    @test isequal(result.fast, compute(EMA(10), bars.close))
    @test isequal(result.slow, compute(EMA(50), bars.close))
end

# ── Phase 2: Core Correctness — Properties ──

@testitem "Features: Data Preservation Through Pipeline" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    result = f(bars)

    @test result.bars === bars
    @test haskey(result, :ema_10)
    @test haskey(result, :cusum)
    @test length(keys(result)) == 3  # :bars, :ema_10, :cusum
end

@testitem "Features: Feature Ordering Independence" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f_ab = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    f_ba = Features(:cusum => CUSUM(1.0), :ema_10 => EMA(10))

    result_ab = f_ab(bars)
    result_ba = f_ba(bars)

    @test isequal(result_ab.ema_10, result_ba.ema_10)
    @test isequal(result_ab.cusum, result_ba.cusum)
end

# ── Phase 2: Type Stability ──

@testitem "Features: Type Stability" tags = [:feature, :features, :stability] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    @test @inferred(f(bars)) isa NamedTuple
end

@testitem "Features: _compute_features Type Stability" tags = [
    :feature, :features, :stability
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    @test @inferred(Backtest._compute_features(f, prices)) isa NamedTuple
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Features: Float32 Precision" tags = [:feature, :features, :edge] begin
    using Backtest, Test, Dates

    n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    p32 = Float32.(100.0 .+ collect(1:n) .* 0.05f0)
    bars32 = PriceBars(p32, p32, p32, p32, p32, ts, TimeBar())

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0f0))
    result = f(bars32)

    @test eltype(result.ema_10) == Float32
    @test eltype(result.cusum) == Int8
end

@testitem "Features: Multiple EMAs + CUSUM" tags = [
    :feature, :features, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(
        :ema_5 => EMA(5), :ema_10 => EMA(10), :ema_20 => EMA(20),
        :ema_50 => EMA(50), :cusum => CUSUM(1.0),
    )
    result = f(bars)

    @test haskey(result, :ema_5)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :ema_50)
    @test haskey(result, :cusum)
end

@testitem "Features: AbstractVector Input" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    prices = Float64[10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]

    f = Features(:ema_3 => EMA(3))
    result = f(prices)

    @test result isa NamedTuple
    @test haskey(result, :ema_3)
    @test !haskey(result, :bars)
    @test isequal(result.ema_3, compute(EMA(3), prices))
end

@testitem "Features: AbstractVector Input Multiple Features" tags = [
    :feature, :features, :unit
] begin
    using Backtest, Test

    prices = collect(100.0:299.0)

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    result = f(prices)

    @test haskey(result, :ema_10)
    @test haskey(result, :cusum)
    @test isequal(result.ema_10, compute(EMA(10), prices))
    @test isequal(result.cusum, compute(CUSUM(1.0), prices))
end

# ── Phase 3: Robustness — Pipeline Operator Integration ──

@testitem "Features: Pipeline Operator >>" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
    @test result.bars === bars
end

@testitem "Features: Pipe Operator |>" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
end

@testitem "Features: NamedTuple Input (pipeline continuation)" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Simulate a pipeline NamedTuple with bars
    d = (bars=bars, some_key=42)

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    result = f(d)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :some_key)
    @test haskey(result, :ema_10)
    @test haskey(result, :cusum)
    @test result.some_key == 42
    @test result.bars === bars
end

# ── Phase 4: Static Analysis ──

@testitem "Features: Static Analysis" tags = [
    :feature, :features, :stability
] begin
    using Backtest, Test, JET

    prices = collect(1.0:200.0)
    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))

    @test_opt target_modules = (Backtest,) Backtest._compute_features(f, prices)
    @test_call target_modules = (Backtest,) Backtest._compute_features(f, prices)
end

# ── Phase 5: Allocation Budget Tests ──

@testitem "Features: Allocation — Budget" tags = [
    :feature, :features, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    f(bars)

    # Budget: 2 EMA vectors (Float64 × n × 2) + CUSUM result (Int8 × n)
    # + 1024 bytes merge overhead
    ema_bytes = sizeof(Float64) * 200 * 2
    cusum_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + 1024

    allocs_f(f, bars) = @allocated f(bars)

    actual = minimum([@allocated(allocs_f(f, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Features: Allocation — AbstractVector Path" tags = [
    :feature, :features, :allocation
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))

    f(prices)

    ema_bytes = sizeof(Float64) * 200
    cusum_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + 1024

    allocs_f(f, prices) = @allocated f(prices)

    actual = minimum([@allocated(allocs_f(f, prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end
