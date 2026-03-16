# ── Feature Interface Tests ──
#
# These test the shared AbstractFeature callable interface defined in
# src/feature/feature.jl and the Features struct in src/feature/features.jl.
# Per-type behaviour is covered in ema_tests.jl and cusum_tests.jl — this
# file covers cross-feature concerns: Features composition, data
# preservation, and pipeline operator integration.

# ── Phase 2: Core Correctness ──

@testitem "Feature Interface: Features Composition" tags = [:feature, :features, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = Features(:ema_10 => EMA(10), :ema_50 => EMA(50), :cusum => CUSUM(1.0))(bars)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_50)
    @test haskey(result.features, :cusum)
    @test length(keys(result.features)) == 3
end

@testitem "Feature Interface: Data Preservation Through Features" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0), :ema_20 => EMA(20))(bars)

    # PriceBars reference identity survives
    @test result.bars === bars

    # Feature values match independent computation
    independent_ema10 = compute(EMA(10), bars.close)
    independent_ema20 = compute(EMA(20), bars.close)
    independent_cusum = compute(CUSUM(1.0), bars.close)
    @test isequal(result.features.ema_10, independent_ema10)
    @test isequal(result.features.ema_20, independent_ema20)
    @test isequal(result.features.cusum, independent_cusum)
end

@testitem "Feature Interface: Pipeline Operator Composition" tags = [:feature, :features, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    composed = Features(:ema_10 => EMA(10), :ema_50 => EMA(50), :cusum => CUSUM(1.0)) >> Crossover(:ema_10, :ema_50)
    result = composed(bars)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result, :side)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_50)
    @test haskey(result.features, :cusum)
end

@testitem "Feature Interface: Job Creation and Execution" tags = [:feature, :features, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> Features(:ema_10 => EMA(10), :ema_50 => EMA(50), :cusum => CUSUM(1.0))
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_50)
    @test haskey(result.features, :cusum)
    @test result.bars === bars
end

# ── Phase 2: Type Stability ──

@testitem "Feature Interface: Type Stability of Features Callable" tags = [
    :feature, :features, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    @test @inferred(Features(:ema_10 => EMA(10))(bars)) isa NamedTuple
    @test @inferred(Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))(bars)) isa NamedTuple
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Feature Interface: Output Types Match Input Precision" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    # Float64 path
    bars64 = TestData.make_pricebars(; n=200)
    result64 = Features(:ema_10 => EMA(10))(bars64)
    @test eltype(result64.features.ema_10) == Float64

    # Float32 path
    n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    p32 = Float32.(100.0 .+ collect(1:n) .* 0.05f0)
    bars32 = PriceBars(p32, p32, p32, p32, p32, ts, TimeBar())
    result32 = Features(:ema_10 => EMA(10))(bars32)
    @test eltype(result32.features.ema_10) == Float32
end

@testitem "Feature Interface: Feature Ordering Independence" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Different ordering — feature values should be identical
    result_ab = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))(bars)
    result_ba = Features(:cusum => CUSUM(1.0), :ema_10 => EMA(10))(bars)

    @test isequal(result_ab.features.ema_10, result_ba.features.ema_10)
    @test isequal(result_ab.features.cusum, result_ba.features.cusum)
end

@testitem "Feature Interface: Many Features in Features" tags = [:feature, :features, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Five features — stress test for NamedTuple merge depth
    result = Features(
        :ema_5 => EMA(5), :ema_10 => EMA(10), :ema_20 => EMA(20),
        :ema_50 => EMA(50), :cusum => CUSUM(1.0),
    )(bars)

    @test haskey(result.features, :ema_5)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :ema_50)
    @test haskey(result.features, :cusum)
    @test result.bars === bars
end

@testitem "Feature Interface: AbstractVector Input" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    prices = collect(1.0:200.0)

    result = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))(prices)

    @test result isa NamedTuple
    @test haskey(result, :ema_10)
    @test haskey(result, :cusum)
    # Vector path returns features directly, no :bars or :features wrapper
    @test !haskey(result, :bars)
    @test !haskey(result, :features)

    # Values match independent computation
    @test isequal(result.ema_10, compute(EMA(10), prices))
    @test isequal(result.cusum, compute(CUSUM(1.0), prices))
end

@testitem "Feature Interface: Single AbstractFeature AbstractVector Input" tags = [
    :feature, :unit
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)

    result = EMA(10)(prices)

    @test result isa NamedTuple
    @test haskey(result, :ema_10)
    @test isequal(result.ema_10, compute(EMA(10), prices))
end

# ── Phase 5: Allocation Budget Tests ──
#
# Features functor allocations: result vectors + 1024 bytes merge overhead.

@testitem "Feature Interface: Allocation — Features functor with PriceBars" tags = [
    :feature, :features, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feats = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    feats(bars)

    # Budget: 2 EMA vectors (Float64 × n × 2) + CUSUM result (Int8 × n) + 1024 bytes merge
    ema_bytes = sizeof(Float64) * 200 * 2
    cusum_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + 1024

    allocs_feats(feats, bars) = @allocated feats(bars)

    actual = minimum([@allocated(allocs_feats(feats, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Feature Interface: Allocation — Features functor chaining" tags = [
    :feature, :features, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feats = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    cross = Crossover(:ema_10, :ema_20)

    pipeline = feats >> cross
    pipeline(bars)

    # Budget: feature result vectors + side vector + 1024 bytes
    ema_bytes = sizeof(Float64) * 200 * 2
    cusum_bytes = sizeof(Int8) * 200
    side_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + side_bytes + 1024

    allocs_pipeline(p, bars) = @allocated p(bars)

    actual = minimum([@allocated(allocs_pipeline(pipeline, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

# ── Duck-Typed Data Support ──

@testitem "Feature Interface: NamedTuple with close field (no PriceBars)" tags = [
    :feature, :unit
] begin
    using Backtest, Test

    # A plain NamedTuple with a :close field should work as input
    close = Float64[10, 11, 12, 13, 14, 15]
    data = (close=close, volume=ones(6))

    result = EMA(3)(data)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_3)
    @test result.bars === data
    @test result.ema_3[3] ≈ 11.0
end

@testitem "Feature Interface: field keyword routes to alternate series" tags = [
    :feature, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # EMA on volume via field keyword
    result = EMA(10; field=:volume)(bars)
    expected = compute(EMA(10), bars.volume)
    @test isequal(result.ema_10, expected)
end
