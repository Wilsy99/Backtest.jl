# ── FeatureUnion Tests ──
#
# Tests for the fused feature combinator that computes multiple features
# in a single pipeline step.  Follows the TESTING.md phase structure.

# ── Phase 1: Construction ──

@testitem "FeatureUnion: Construction" tags = [:feature, :feature_union, :unit] begin
    using Backtest, Test

    fu = FeatureUnion(EMA(10, 20), CUSUM(1.0))
    @test fu isa AbstractFeature
    @test fu isa FeatureUnion
    @test length(fu.features) == 2

    fu3 = FeatureUnion(EMA(5), EMA(10), CUSUM(0.5))
    @test length(fu3.features) == 3
end

@testitem "FeatureUnion: Rejects Fewer Than Two Features" tags = [
    :feature, :feature_union, :edge
] begin
    using Backtest, Test

    @test_throws ArgumentError FeatureUnion(EMA(10))
    @test_throws MethodError FeatureUnion()
end

# ── Phase 2: Core Correctness — Reference Values ──

@testitem "FeatureUnion: Results Match Sequential — EMA+CUSUM" tags = [
    :feature, :feature_union, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    fu = FeatureUnion(EMA(10, 20), CUSUM(1.0))
    fused = fu(bars)

    sequential = CUSUM(1.0)(EMA(10, 20)(bars))

    @test haskey(fused, :bars)
    @test haskey(fused, :ema_10)
    @test haskey(fused, :ema_20)
    @test haskey(fused, :cusum)

    @test isequal(fused.ema_10, sequential.ema_10)
    @test isequal(fused.ema_20, sequential.ema_20)
    @test isequal(fused.cusum, sequential.cusum)
    @test fused.bars === bars
end

@testitem "FeatureUnion: Results Match Sequential — Three Features" tags = [
    :feature, :feature_union, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    fu = FeatureUnion(EMA(5), EMA(20), CUSUM(1.0))
    fused = fu(bars)

    step1 = EMA(5)(bars)
    step2 = EMA(20)(step1)
    step3 = CUSUM(1.0)(step2)

    @test haskey(fused, :ema_5)
    @test haskey(fused, :ema_20)
    @test haskey(fused, :cusum)

    @test isequal(fused.ema_5, step3.ema_5)
    @test isequal(fused.ema_20, step3.ema_20)
    @test isequal(fused.cusum, step3.cusum)
end

# ── Phase 2: Core Correctness — Properties ──

@testitem "FeatureUnion: Data Preservation Through Chain" tags = [
    :feature, :feature_union, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # First step: single EMA
    step1 = EMA(5)(bars)

    # Second step: FeatureUnion adds more features
    fu = FeatureUnion(EMA(20), CUSUM(1.0))
    result = fu(step1)

    # Upstream keys preserved
    @test haskey(result, :bars)
    @test haskey(result, :ema_5)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
    @test result.bars === bars

    # Values match independent computation
    independent_ema20 = calculate_feature(EMA(20), bars.close)
    independent_cusum = calculate_feature(CUSUM(1.0), bars.close)
    @test isequal(result.ema_20, independent_ema20)
    @test isequal(result.cusum, independent_cusum)
end

@testitem "FeatureUnion: Feature Ordering Independence" tags = [
    :feature, :feature_union, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    fu_ab = FeatureUnion(EMA(10), CUSUM(1.0))
    fu_ba = FeatureUnion(CUSUM(1.0), EMA(10))

    result_ab = fu_ab(bars)
    result_ba = fu_ba(bars)

    @test isequal(result_ab.ema_10, result_ba.ema_10)
    @test isequal(result_ab.cusum, result_ba.cusum)
end

# ── Phase 2: Type Stability ──

@testitem "FeatureUnion: Type Stability" tags = [:feature, :feature_union, :stability] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    fu = FeatureUnion(EMA(10, 20), CUSUM(1.0))

    @test @inferred(fu(bars)) isa NamedTuple

    step1 = EMA(5)(bars)
    fu2 = FeatureUnion(EMA(20), CUSUM(1.0))
    @test @inferred(fu2(step1)) isa NamedTuple
end

@testitem "FeatureUnion: _feature_result Type Stability" tags = [
    :feature, :feature_union, :stability
] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    fu = FeatureUnion(EMA(10), CUSUM(1.0))
    @test @inferred(Backtest._feature_result(fu, prices)) isa NamedTuple
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "FeatureUnion: Float32 Precision" tags = [
    :feature, :feature_union, :edge
] begin
    using Backtest, Test, Dates

    n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    p32 = Float32.(100.0 .+ collect(1:n) .* 0.05f0)
    bars32 = PriceBars(p32, p32, p32, p32, p32, ts, TimeBar())

    fu = FeatureUnion(EMA(10), CUSUM(1.0f0))
    result = fu(bars32)

    @test eltype(result.ema_10) == Float32
    @test eltype(result.cusum) == Int8
end

@testitem "FeatureUnion: Multi-Period EMA + CUSUM" tags = [
    :feature, :feature_union, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    fu = FeatureUnion(EMA(5, 10, 20, 50), CUSUM(1.0))
    result = fu(bars)

    @test haskey(result, :ema_5)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :ema_50)
    @test haskey(result, :cusum)
    @test length(keys(result)) == 6  # bars + 4 EMAs + cusum
end

# ── Phase 3: Robustness — Pipeline Operator Integration ──

@testitem "FeatureUnion: Pipeline Operator >>" tags = [
    :feature, :feature_union, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> FeatureUnion(EMA(10, 20), CUSUM(1.0))
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
    @test result.bars === bars
end

@testitem "FeatureUnion: Pipe Operator |>" tags = [
    :feature, :feature_union, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = bars |> FeatureUnion(EMA(10, 20), CUSUM(1.0))

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
end

@testitem "FeatureUnion: Composable in Longer Pipeline" tags = [
    :feature, :feature_union, :integration
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # FeatureUnion followed by another standalone feature
    composed = FeatureUnion(EMA(10, 20), CUSUM(1.0)) >> EMA(50)
    result = composed(bars)

    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :cusum)
    @test haskey(result, :ema_50)
end

# ── Phase 4: Static Analysis ──

@testitem "FeatureUnion: Static Analysis" tags = [
    :feature, :feature_union, :stability
] begin
    using Backtest, Test, JET

    prices = collect(1.0:200.0)
    fu = FeatureUnion(EMA(10), CUSUM(1.0))

    @test_opt target_modules = (Backtest,) Backtest._feature_result(fu, prices)
    @test_call target_modules = (Backtest,) Backtest._feature_result(fu, prices)
end

# ── Phase 5: Allocation Budget Tests ──
#
# FeatureUnion should allocate no more than the sum of its contained
# features' result data plus a single merge overhead, since it produces
# one pipeline merge instead of N sequential merges.

@testitem "FeatureUnion: Allocation — Fused vs Sequential" tags = [
    :feature, :feature_union, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    fu = FeatureUnion(EMA(10, 20), CUSUM(1.0))
    sequential = EMA(10, 20) >> CUSUM(1.0)

    fu(bars)
    sequential(bars)

    fused_alloc = minimum([@allocated(fu(bars)) for _ in 1:5])
    seq_alloc = minimum([@allocated(sequential(bars)) for _ in 1:5])

    # Fused path should allocate no more than sequential
    @test fused_alloc <= seq_alloc
end

@testitem "FeatureUnion: Allocation — Budget" tags = [
    :feature, :feature_union, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    fu = FeatureUnion(EMA(10, 20), CUSUM(1.0))

    fu(bars)

    # Budget: EMA matrix (Float64 × n × 2) + CUSUM result (Int8 × n) + 1024 bytes merge
    ema_bytes = sizeof(Float64) * 200 * 2
    cusum_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + 1024

    allocs_fu(fu, bars) = @allocated fu(bars)

    actual = minimum([@allocated(allocs_fu(fu, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end
