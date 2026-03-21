# ── PrecomputedFeature Tests ──
#
# Tests for custom/external feature support via PrecomputedFeature.
# Covers pre-computed vectors, external indicator results, and mixing
# with built-in AbstractFeature instances.

# ── Phase 1: Construction ──

@testitem "PrecomputedFeature: Direct Construction" tags = [:feature, :precomputed, :unit] begin
    using Backtest, Test

    data = collect(1.0:10.0)
    pf = PrecomputedFeature(data)

    @test pf isa AbstractFeature
    @test pf isa PrecomputedFeature
    @test pf.data === data
end

@testitem "PrecomputedFeature: Features with Vector via Pair" tags = [
    :feature, :precomputed, :unit
] begin
    using Backtest, Test

    vec = collect(1.0:200.0)
    f = Features(:custom => vec)

    @test f isa Features
    @test length(f.operations) == 1
end

@testitem "PrecomputedFeature: Features with Mixed Types via Pair" tags = [
    :feature, :precomputed, :unit
] begin
    using Backtest, Test

    vec = collect(1.0:200.0)
    f = Features(:ema_10 => EMA(10), :custom => vec)

    @test f isa Features
    @test length(f.operations) == 2
end

@testitem "PrecomputedFeature: @Features Macro with Vector" tags = [
    :feature, :precomputed, :unit
] begin
    using Backtest, Test

    vec = collect(1.0:200.0)
    f = @Features custom = vec

    @test f isa Features
    @test length(f.operations) == 1
end

@testitem "PrecomputedFeature: @Features Macro Mixed" tags = [
    :feature, :precomputed, :unit
] begin
    using Backtest, Test

    vec = collect(1.0:200.0)
    f = @Features ema_10 = EMA(10) custom = vec

    @test f isa Features
    @test length(f.operations) == 2
end

# ── Phase 2: Core Correctness ──

@testitem "PrecomputedFeature: Returns Stored Data on PriceBars Call" tags = [
    :feature, :precomputed, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    vec = collect(1.0:200.0)

    f = Features(:custom => vec)
    result = f(bars)

    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :custom)
    @test result.features.custom === vec
    @test result.bars === bars
end

@testitem "PrecomputedFeature: Mixed with Built-in Features" tags = [
    :feature, :precomputed, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    custom_vec = randn(200)

    f = Features(:ema_10 => EMA(10), :custom => custom_vec, :cusum => CUSUM(1.0))
    result = f(bars)

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :custom)
    @test haskey(result.features, :cusum)

    # Built-in features computed correctly
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
    @test isequal(result.features.cusum, compute(CUSUM(1.0), bars.close))

    # Custom feature returns exact reference
    @test result.features.custom === custom_vec
end

@testitem "PrecomputedFeature: @Features Macro Mixed Correctness" tags = [
    :feature, :precomputed, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    rsi = randn(200)

    f = @Features ema_10 = EMA(10) rsi_14 = rsi
    result = f(bars)

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :rsi_14)
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
    @test result.features.rsi_14 === rsi
end

@testitem "PrecomputedFeature: External Function Result" tags = [
    :feature, :precomputed, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Simulate external library: function that computes on raw data
    my_sma(x, period) = [i < period ? NaN : sum(x[i-period+1:i]) / period for i in eachindex(x)]

    sma_result = my_sma(bars.close, 10)
    f = @Features sma_10 = sma_result ema_20 = EMA(20)
    result = f(bars)

    @test result.features.sma_10 === sma_result
    @test isequal(result.features.ema_20, compute(EMA(20), bars.close))
end

# ── Phase 2: Type Stability ──

@testitem "PrecomputedFeature: Type Stability" tags = [
    :feature, :precomputed, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    vec = collect(1.0:200.0)

    f = Features(:custom => vec)
    @test @inferred(f(bars)) isa NamedTuple
end

@testitem "PrecomputedFeature: Type Stability Mixed" tags = [
    :feature, :precomputed, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    vec = collect(1.0:200.0)

    f = Features(:ema_10 => EMA(10), :custom => vec)
    @test @inferred(f(bars)) isa NamedTuple
end

# ── Phase 3: Pipeline Integration ──

@testitem "PrecomputedFeature: Pipeline Operator >>" tags = [
    :feature, :precomputed, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    fast = randn(200)
    slow = randn(200)

    f = Features(:fast => fast, :slow => slow)
    job = bars >> f
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test result.features.fast === fast
    @test result.features.slow === slow
end

@testitem "PrecomputedFeature: Pipe Operator |>" tags = [
    :feature, :precomputed, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    signal = Int8.(rand([-1, 0, 1], 200))

    result = bars |> Features(:ema_10 => EMA(10), :signal => signal)

    @test result isa NamedTuple
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :signal)
    @test result.features.signal === signal
end

@testitem "PrecomputedFeature: NamedTuple Input Merges Features" tags = [
    :feature, :precomputed, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # First step: built-in feature
    step1 = Features(:ema_10 => EMA(10))(bars)

    # Second step: add pre-computed feature — should merge
    custom = randn(200)
    step2 = Features(:custom => custom)(step1)

    @test haskey(step2.features, :ema_10)
    @test haskey(step2.features, :custom)
    @test step2.features.custom === custom
    @test isequal(step2.features.ema_10, compute(EMA(10), bars.close))
end

# ── Phase 3: Edge Cases ──

@testitem "PrecomputedFeature: Multiple PrecomputedFeatures" tags = [
    :feature, :precomputed, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    v1 = randn(200)
    v2 = rand(Int8, 200)
    v3 = randn(Float32, 200)

    f = Features(:f1 => v1, :f2 => v2, :f3 => v3)
    result = f(bars)

    @test result.features.f1 === v1
    @test result.features.f2 === v2
    @test result.features.f3 === v3
end

@testitem "PrecomputedFeature: Float32 Vector" tags = [
    :feature, :precomputed, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    vec32 = randn(Float32, 200)

    f = Features(:custom => vec32)
    result = f(bars)

    @test eltype(result.features.custom) == Float32
    @test result.features.custom === vec32
end

@testitem "PrecomputedFeature: Int8 Signal Vector" tags = [
    :feature, :precomputed, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    signal = Int8.(rand([-1, 0, 1], 200))

    f = Features(:signal => signal)
    result = f(bars)

    @test eltype(result.features.signal) == Int8
    @test result.features.signal === signal
end

@testitem "PrecomputedFeature: @Event Macro Rewrites Custom Feature Name" tags = [
    :feature, :precomputed, :macro
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    custom_signal = Float64.(rand([-1, 0, 1], 200))

    nt = Features(:ema_10 => EMA(10), :my_signal => custom_signal)(bars)

    evt_manual = Event(d -> d.features.my_signal .!= 0)
    evt_macro = @Event :my_signal .!= 0

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end
