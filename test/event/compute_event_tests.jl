# ── compute_event: Standalone Function Tests ──

@testitem "compute_event: Hand-Calculated Reference — PriceBars overload" tags = [
    :event, :reference
] begin
    using Backtest, Test, Dates

    # close = [98, 99, 101, 102, 100]
    # Condition: close .> 100  → [false, false, true, true, false]
    # Expected indices: [3, 4]
    bars = PriceBars(
        [97.0, 98.0, 100.0, 101.0, 99.0],
        [99.0, 100.0, 102.0, 103.0, 101.0],
        [96.0, 97.0, 99.0, 100.0, 98.0],
        [98.0, 99.0, 101.0, 102.0, 100.0],
        fill(1000.0, 5),
        [DateTime(2024, 1, i) for i in 1:5],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 100.0)
    indices = compute_event(evt, bars)

    @test indices == [3, 4]
    @test indices isa Vector{Int}
end

@testitem "compute_event: Hand-Calculated Reference — NamedTuple overload (AND)" tags = [
    :event, :reference
] begin
    using Backtest, Test, Dates

    # close = [98, 99, 101, 102, 100]
    # Condition 1: close .> 100  → [false, false, true, true, false]
    # Condition 2: close .< 102  → [true,  true,  true, false, true]
    # AND mask                   → [false, false, true, false, false]
    # Expected indices: [3]
    bars = PriceBars(
        [97.0, 98.0, 100.0, 101.0, 99.0],
        [99.0, 100.0, 102.0, 103.0, 101.0],
        [96.0, 97.0, 99.0, 100.0, 98.0],
        [98.0, 99.0, 101.0, 102.0, 100.0],
        fill(1000.0, 5),
        [DateTime(2024, 1, i) for i in 1:5],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 100.0, d -> d.bars.close .< 102.0; match=:all)
    indices = compute_event(evt, (bars=bars,))

    @test indices == [3]
end

@testitem "compute_event: Hand-Calculated Reference — NamedTuple overload (OR)" tags = [
    :event, :reference
] begin
    using Backtest, Test, Dates

    # close = [98, 99, 101, 102, 100]
    # Condition 1: close .> 101  → [false, false, false, true,  false]
    # Condition 2: close .< 99   → [true,  false, false, false, false]
    # OR mask                    → [true,  false, false, true,  false]
    # Expected indices: [1, 4]
    bars = PriceBars(
        [97.0, 98.0, 100.0, 101.0, 99.0],
        [99.0, 100.0, 102.0, 103.0, 101.0],
        [96.0, 97.0, 99.0, 100.0, 98.0],
        [98.0, 99.0, 101.0, 102.0, 100.0],
        fill(1000.0, 5),
        [DateTime(2024, 1, i) for i in 1:5],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 101.0, d -> d.bars.close .< 99.0; match=:any)
    indices = compute_event(evt, (bars=bars,))

    @test indices == [1, 4]
end

@testitem "compute_event: With upstream feature data" tags = [:event, :reference] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = Features(:ema_10 => EMA(10), :ema_50 => EMA(50))(bars)

    evt = Event(d -> d.features.ema_10 .> d.features.ema_50)
    indices = compute_event(evt, nt)

    @test indices isa Vector{Int}
    @test issorted(indices)
    @test all(i -> 1 <= i <= 100, indices)

    # Must match functor output
    functor_result = evt(nt)
    @test indices == functor_result.event_indices
end

# ── Properties ──

@testitem "compute_event: Property — PriceBars and NamedTuple overloads agree" tags = [
    :event, :property
] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [97.0, 98.0, 100.0, 101.0, 99.0],
        [99.0, 100.0, 102.0, 103.0, 101.0],
        [96.0, 97.0, 99.0, 100.0, 98.0],
        [98.0, 99.0, 101.0, 102.0, 100.0],
        fill(1000.0, 5),
        [DateTime(2024, 1, i) for i in 1:5],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 100.0)

    @test compute_event(evt, bars) == compute_event(evt, (bars=bars,))
end

@testitem "compute_event: Property — matches functor output" tags = [
    :event, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    evt = Event(d -> d.bars.close .> 100.0)

    # PriceBars path
    @test compute_event(evt, bars) == evt(bars).event_indices

    # NamedTuple path
    nt = Features(:ema_10 => EMA(10))(bars)
    evt2 = Event(d -> d.features.ema_10 .> 100.0)
    @test compute_event(evt2, nt) == evt2(nt).event_indices
end

@testitem "compute_event: Property — indices are sorted and in-bounds" tags = [
    :event, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    n = length(bars)

    evt = Event(d -> d.bars.close .> 100.0)
    indices = compute_event(evt, bars)

    @test issorted(indices)
    @test all(i -> 1 <= i <= n, indices)
end

# ── Edge Cases ──

@testitem "compute_event: Edge Case — no bars match" tags = [:event, :edge] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        fill(99.0, 4),
        fill(100.0, 4),
        fill(98.0, 4),
        [98.0, 99.0, 99.5, 99.9],
        fill(1000.0, 4),
        [DateTime(2024, 1, i) for i in 1:4],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 100.0)
    @test isempty(compute_event(evt, bars))
end

@testitem "compute_event: Edge Case — all bars match" tags = [:event, :edge] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        fill(99.0, 4),
        fill(101.0, 4),
        fill(98.0, 4),
        [101.0, 102.0, 103.0, 104.0],
        fill(1000.0, 4),
        [DateTime(2024, 1, i) for i in 1:4],
        TimeBar(),
    )

    evt = Event(d -> d.bars.close .> 100.0)
    @test compute_event(evt, bars) == [1, 2, 3, 4]
end

@testitem "compute_event: Edge Case — single bar" tags = [:event, :edge] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [100.0],
        [101.0],
        [99.0],
        [100.5],
        [1000.0],
        [DateTime(2024, 1, 1)],
        TimeBar(),
    )

    @test compute_event(Event(d -> d.bars.close .> 100.0), bars) == [1]
    @test isempty(compute_event(Event(d -> d.bars.close .> 200.0), bars))
end

# ── Type Stability ──

@testitem "compute_event: Type Stability" tags = [:event, :stability] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=50)
    nt = Features(:ema_10 => EMA(10))(bars)

    evt_bars = Event(d -> d.bars.close .> 100.0)
    evt_nt = Event(d -> d.features.ema_10 .> 100.0)

    @test @inferred(compute_event(evt_bars, bars)) isa Vector{Int}
    @test @inferred(compute_event(evt_nt, nt)) isa Vector{Int}
end

# ── Allocation Budget ──

@testitem "compute_event: Allocation — PriceBars" tags = [:event, :allocation] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> d.bars.close .> 100.0)

    # Warmup
    compute_event(evt, bars)

    # Budget: result Vector{Int} + BitVector mask + minor overhead
    n = length(bars)
    budget = sizeof(Int) * n + 512 + 1024

    allocs_fn(evt, bars) = @allocated compute_event(evt, bars)

    actual = minimum([@allocated(allocs_fn(evt, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end
