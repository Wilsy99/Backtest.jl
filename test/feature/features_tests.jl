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

# ── Phase 2: FunctionFeature and StaticFeature ──

@testitem "Features: FunctionFeature — Custom Function" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # User-supplied function that computes a simple rolling mean
    my_indicator = bars -> cumsum(bars.close) ./ (1:length(bars.close))

    f = Features(:custom => my_indicator, :ema_10 => EMA(10))
    result = f(bars)

    @test haskey(result, :bars)
    @test haskey(result, :features)
    @test haskey(result.features, :custom)
    @test haskey(result.features, :ema_10)
    @test result.features.custom ≈ cumsum(bars.close) ./ (1:length(bars.close))
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
end

@testitem "Features: StaticFeature — Pre-computed Vector" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    precomputed = collect(1.0:200.0)

    f = Features(:static_val => precomputed, :ema_10 => EMA(10))
    result = f(bars)

    @test haskey(result.features, :static_val)
    @test haskey(result.features, :ema_10)
    @test result.features.static_val === precomputed
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
end

@testitem "Features: Mixed Types — AbstractFeature + Function + Vector" tags = [
    :feature, :features, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    precomputed = fill(42.0, 200)
    my_func = bars -> bars.high .- bars.low

    f = Features(:ema_10 => EMA(10), :range => my_func, :constant => precomputed)
    result = f(bars)

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :range)
    @test haskey(result.features, :constant)
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
    @test result.features.range ≈ bars.high .- bars.low
    @test result.features.constant === precomputed
end

@testitem "Features: FunctionFeature Type Stability" tags = [
    :feature, :features, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    f = Features(:custom => bars -> bars.close .* 2.0)

    @test @inferred(f(bars)) isa NamedTuple
end

@testitem "Features: StaticFeature Type Stability" tags = [
    :feature, :features, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    f = Features(:static_val => collect(1.0:200.0))

    @test @inferred(f(bars)) isa NamedTuple
end

@testitem "Features: wrap_feature Dispatch" tags = [:feature, :features, :unit] begin
    using Backtest, Test

    ema = EMA(10)
    @test wrap_feature(ema) === ema

    f = x -> x
    wrapped_f = wrap_feature(f)
    @test wrapped_f isa FunctionFeature
    @test wrapped_f.f === f

    v = [1.0, 2.0, 3.0]
    wrapped_v = wrap_feature(v)
    @test wrapped_v isa StaticFeature
    @test wrapped_v.values === v
end

@testitem "Features: @Features Macro with Function" tags = [
    :feature, :features, :macro
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = @Features range = (bars -> bars.high .- bars.low) ema_10 = EMA(10)
    result = f(bars)

    @test haskey(result.features, :range)
    @test haskey(result.features, :ema_10)
    @test result.features.range ≈ bars.high .- bars.low
end

@testitem "Features: @Features Macro Paren Form" tags = [
    :feature, :features, :macro
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    f = @Features(ema_10 = EMA(10), ema_20 = EMA(20))
    result = f(bars)

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :ema_20)
    @test isequal(result.features.ema_10, compute(EMA(10), bars.close))
    @test isequal(result.features.ema_20, compute(EMA(20), bars.close))
end

@testitem "Features: Pipeline with FunctionFeature" tags = [
    :feature, :features, :integration
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> Features(:ema_10 => EMA(10), :spread => bars -> bars.high .- bars.low)
    result = job()

    @test haskey(result.features, :ema_10)
    @test haskey(result.features, :spread)
    @test result.bars === bars
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
