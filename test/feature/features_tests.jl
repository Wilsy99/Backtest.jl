# ── Features Tests ──
#
# Tests for the Features struct that computes named features in a single
# pipeline step with results nested under a :features key.
# Follows the TESTING.md phase structure.

# ── Phase 1: Construction ──

@testitem "Features: Construction" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    @test f isa Features
    @test length(f.operations) == 2

    f3 = Features(:ema_5 => EMA(5), :ema_10 => EMA(10), :cusum => CUSUM(0.5))
    @test length(f3.operations) == 3
end

@testitem "Features: Single Feature" tags = [:feature, :features, :edge] begin
    using Backtest, Test

    f = Features(:ema_10 => EMA(10))
    @test f isa Features
    @test length(f.operations) == 1
end

# ── Phase 2: Core Correctness — Reference Values ──

@testitem "Features: Results Match Independent Computation — EMA+CUSUM" tags = [
    :feature, :features, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    result = f(bars)

    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :cusum)

    # Values match independent computation
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
    @test isequal(result.features.ema_20, compute(EMA(20), bars.close))
    @test isequal(result.features.cusum, compute(CUSUM(1.0), bars.close))
    @test result.bars === bars
end

@testitem "Features: Results Match Independent Computation — Three Features" tags = [
    :feature, :features, :reference
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:ema_5 => EMA(5), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    result = f(bars)

    @test haskey(result.features, :ema_5)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :cusum)

    @test isequal(result.features.ema_5, compute(EMA(5), bars.close))
    @test isequal(result.features.ema_20, compute(EMA(20), bars.close))
    @test isequal(result.features.cusum, compute(CUSUM(1.0), bars.close))
end

# ── Phase 2: Core Correctness — Properties ──

@testitem "Features: Feature Names Match User-Supplied Symbols" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(:my_ema => EMA(10), :my_cusum => CUSUM(1.0))
    result = f(bars)

    @test haskey(result.features, :my_ema)
    @test haskey(result.features, :my_cusum)
    @test isequal(result.features.my_ema, compute(EMA(10), bars.close))
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

    @test isequal(result_ab.features.ema_10, result_ba.features.ema_10)
    @test isequal(result_ab.features.cusum, result_ba.features.cusum)
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

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Features: Float32 Precision" tags = [:feature, :features, :edge] begin
    using Backtest, Test, Dates

    n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    p32 = Float32.(100.0 .+ collect(1:n) .* 0.05f0)
    bars32 = PriceBars(p32, p32, p32, p32, p32, ts, TimeBar())

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0f0))
    result = f(bars32)

    @test eltype(result.features.ema_10) == Float32
    @test eltype(result.features.cusum) == Int8
end

@testitem "Features: Multiple EMAs + CUSUM" tags = [:feature, :features, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = Features(
        :ema_5 => EMA(5), :ema_10 => EMA(10), :ema_20 => EMA(20),
        :ema_50 => EMA(50), :cusum => CUSUM(1.0),
    )
    result = f(bars)

    @test haskey(result.features, :ema_5)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :ema_50)
    @test haskey(result.features, :cusum)
    @test length(keys(result.features)) == 5
end

@testitem "Features: AbstractVector Input" tags = [:feature, :features, :edge] begin
    using Backtest, Test

    prices = collect(1.0:200.0)

    f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))
    result = f(prices)

    @test result isa NamedTuple
    @test haskey(result, :ema_10)
    @test haskey(result, :cusum)
    # Vector path returns features directly
    @test !haskey(result, :bars)
    @test !haskey(result, :features)
    @test isequal(result.ema_10, compute(EMA(10), prices))
end

# ── Phase 3: Robustness — Pipeline Operator Integration ──

@testitem "Features: Pipeline Operator >>" tags = [:feature, :features, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :cusum)
    @test result.bars === bars
end

@testitem "Features: Merges Existing Features Instead of Overwriting" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # First Features call adds :ema_10
    step1 = Features(:ema_10 => EMA(10))(bars)
    @test haskey(step1.features, :ema_10)

    # Second Features call adds :ema_20 — should merge, not overwrite
    step2 = Features(:ema_20 => EMA(20))(step1)
    @test haskey(step2.features, :ema_10)
    @test haskey(step2.features, :ema_20)

    # Values are correct
    @test isequal(step2.features.ema_10, compute(EMA(10), bars.close))
    @test isequal(step2.features.ema_20, compute(EMA(20), bars.close))
end

@testitem "Features: Pipe Operator |>" tags = [:feature, :features, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test haskey(result.features, :cusum)
end

@testitem "Features: Full Pipeline Integration" tags = [
    :feature, :features, :integration
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)

    result = (
        Features(:ema_10 => EMA(10), :ema_50 => EMA(50), :cusum => CUSUM(1.0)) >>
        Crossover(:ema_10, :ema_50) >>
        Event(d -> d.features.cusum .!= 0 .&& d.side .!= 0) >>
        Label!(
            UpperBarrier(d -> d.entry_price * 1.10),
            LowerBarrier(d -> d.entry_price * 0.90),
            TimeBarrier(d -> d.entry_ts + Day(20)),
        )
    )(bars)

    @test result isa Backtest.LabelResults
end

# ── Phase 3: Macro Rewriting Tests ──

@testitem "Features: @Event rewrites to d.features.symbol" tags = [
    :feature, :features, :macro
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    nt = Features(:ema_10 => EMA(10), :ema_50 => EMA(50))(bars)

    evt_manual = Event(d -> d.features.ema_10 .> d.features.ema_50)
    evt_macro = @Event :ema_10 .> :ema_50

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

@testitem "Features: @ConditionBarrier rewrites to d.features.symbol[d.idx]" tags = [
    :feature, :features, :macro
] begin
    using Backtest, Test, Dates

    cb = @ConditionBarrier :ema_10 < :ema_20

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        fill(100.0, 10), fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )
    ema_10 = collect(1.0:10.0)
    ema_20 = collect(11.0:20.0)

    d = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        idx=5, bars=bars, features=(ema_10=ema_10, ema_20=ema_20),
    )

    # ema_10[5] = 5.0, ema_20[5] = 15.0 → 5.0 < 15.0 → true
    @test Backtest.barrier_level(cb, d) == true
end

# ── Phase 5: Allocation Budget Tests ──

@testitem "Features: Allocation — Budget" tags = [:feature, :features, :allocation] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1.0))

    f(bars)

    # Budget: 2 EMA vectors (Float64 × n × 2) + CUSUM result (Int8 × n) + 1024 bytes merge
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

    # Budget: EMA vector (Float64 × n) + CUSUM result (Int8 × n) + 1024 bytes
    ema_bytes = sizeof(Float64) * 200
    cusum_bytes = sizeof(Int8) * 200
    budget = ema_bytes + cusum_bytes + 1024

    allocs_f(f, prices) = @allocated f(prices)

    actual = minimum([@allocated(allocs_f(f, prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

# ── FeatureResults Container Tests ──

@testitem "FeatureResults: Pipeline Returns FeatureResults" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    result = Features(:ema_10 => EMA(10))(bars)

    @test result.features isa FeatureResults
end

@testitem "FeatureResults: getproperty Forwards to Inner NamedTuple" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    result = Features(:ema_10 => EMA(10), :ema_20 => EMA(20))(bars)

    @test result.features.ema_10 isa Vector{Float64}
    @test result.features.ema_20 isa Vector{Float64}
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
end

@testitem "FeatureResults: haskey and keys" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    result = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0))(bars)

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :cusum)
    @test !haskey(result.features, :nonexistent)
    @test Set(keys(result.features)) == Set([:ema_10, :cusum])
    @test length(keys(result.features)) == 2
end

@testitem "FeatureResults: getindex with Symbol" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    result = Features(:ema_10 => EMA(10))(bars)

    @test result.features[:ema_10] === result.features.ema_10
end

@testitem "FeatureResults: merge Preserves FeatureResults Type" tags = [
    :feature, :features, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    step1 = Features(:ema_10 => EMA(10))(bars)
    step2 = Features(:ema_20 => EMA(20))(step1)

    @test step2.features isa FeatureResults
    @test haskey(step2.features, :ema_10)
    @test haskey(step2.features, :ema_20)
end
