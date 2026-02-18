# ── Phase 2: Core Correctness ──

@testitem "Event: Hand-Calculated Reference — AND logic" tags = [:event, :reference] begin
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

    evt = Event(d -> d.close .> 100.0, d -> d.close .< 102.0; match=:all)
    result = evt(bars)

    @test result.event_indices == [3]
    @test result.bars === bars
end

@testitem "Event: Hand-Calculated Reference — OR logic" tags = [:event, :reference] begin
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

    evt = Event(d -> d.close .> 101.0, d -> d.close .< 99.0; match=:any)
    result = evt(bars)

    @test result.event_indices == [1, 4]
end

@testitem "Event: Single Condition — All Bars Match" tags = [:event, :reference] begin
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

    evt = Event(d -> d.close .> 100.0)
    result = evt(bars)

    @test result.event_indices == [1, 2, 3, 4]
end

@testitem "Event: Single Condition — No Bars Match" tags = [:event, :reference] begin
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

    evt = Event(d -> d.close .> 100.0)
    result = evt(bars)

    @test isempty(result.event_indices)
end

@testitem "Event: Type Stability" tags = [:event, :stability] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=50)
    nt = EMA(10)(bars)

    evt = Event(d -> d.ema_10 .> 100.0)

    # Callable with PriceBars
    @test @inferred(Event(d -> d.close .> 100.0)(bars)) isa NamedTuple

    # Callable with NamedTuple
    @test @inferred(evt(nt)) isa NamedTuple
end

# ── Phase 2: Core Correctness — Properties ──

@testitem "Event: Property — Indices Are Sorted and In-Bounds" tags = [
    :event, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    n = length(bars)

    evt = Event(d -> d.close .> 100.0)
    result = evt(bars)

    @test issorted(result.event_indices)
    @test all(i -> 1 <= i <= n, result.event_indices)
end

@testitem "Event: Property — AND Is a Subset of OR" tags = [:event, :property] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    nt = EMA(10, 50)(bars)

    cond1 = d -> d.ema_10 .> d.ema_50
    cond2 = d -> d.close .> 100.0

    evt_and = Event(cond1, cond2; match=:all)
    evt_or = Event(cond1, cond2; match=:any)

    r_and = evt_and(nt)
    r_or = evt_or(nt)

    # Every AND index must also be in the OR result
    @test all(i -> i in r_or.event_indices, r_and.event_indices)
end

@testitem "Event: Property — Single Condition AND == OR" tags = [:event, :property] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    cond = d -> d.close .> 100.0
    r_and = Event(cond; match=:all)(bars)
    r_or = Event(cond; match=:any)(bars)

    @test r_and.event_indices == r_or.event_indices
end

@testitem "Event: Property — Input Data Passes Through Unchanged" tags = [
    :event, :property
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10)(bars)

    evt = Event(d -> d.ema_10 .> 100.0)
    result = evt(nt)

    # Original keys survive the merge
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :event_indices)
    @test result.bars === bars
    @test isequal(result.ema_10, nt.ema_10)
end

@testitem "Event: Property — Match Logic Symmetry" tags = [:event, :property] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # With a single always-true condition:
    # AND and OR both return all indices
    r = Event(d -> trues(length(d.close)); match=:all)(bars)
    @test length(r.event_indices) == length(bars)

    # With a single always-false condition:
    # AND and OR both return empty
    r2 = Event(d -> falses(length(d.close)); match=:any)(bars)
    @test isempty(r2.event_indices)
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Event: Edge Case — Single Bar" tags = [:event, :edge] begin
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

    r_match = Event(d -> d.close .> 100.0)(bars)
    @test r_match.event_indices == [1]

    r_no_match = Event(d -> d.close .> 200.0)(bars)
    @test isempty(r_no_match.event_indices)
end

@testitem "Event: Edge Case — All Conditions Contradictory (AND returns empty)" tags = [
    :event, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    # close > X AND close < X is always empty
    x = 105.0
    evt = Event(d -> d.close .> x, d -> d.close .< x; match=:all)
    result = evt(bars)

    @test isempty(result.event_indices)
end

@testitem "Event: Edge Case — All Conditions Tautological (OR returns all)" tags = [
    :event, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    # close > X OR close <= X covers everything
    x = 105.0
    evt = Event(d -> d.close .> x, d -> d.close .<= x; match=:any)
    result = evt(bars)

    @test length(result.event_indices) == length(bars)
end

@testitem "Event: Edge Case — Flat Prices" tags = [:event, :edge] begin
    using Backtest, Test, Dates

    n = 50
    close = fill(100.0, n)
    bars = PriceBars(
        fill(99.0, n),
        fill(101.0, n),
        fill(98.0, n),
        close,
        fill(1000.0, n),
        [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n],
        TimeBar(),
    )

    # Strict threshold: none match
    r_none = Event(d -> d.close .> 100.0)(bars)
    @test isempty(r_none.event_indices)

    # At-or-below threshold: all match
    r_all = Event(d -> d.close .>= 100.0)(bars)
    @test length(r_all.event_indices) == n
end

@testitem "Event: Edge Case — Callable with NamedTuple (post-feature)" tags = [
    :event, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    evt = Event(d -> d.ema_10 .> d.ema_50)
    result = evt(nt)

    @test result isa NamedTuple
    @test haskey(result, :event_indices)
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test issorted(result.event_indices)
    @test all(i -> 1 <= i <= 100, result.event_indices)
end

# ── Phase 3: Robustness — Warning Paths ──

@testitem "Event: Warning — Non-Broadcasting Condition Returns Scalar Bool" tags = [
    :event, :edge
] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [99.0, 100.0],
        [101.0, 102.0],
        [98.0, 99.0],
        [100.0, 101.0],
        [1000.0, 1000.0],
        [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
        TimeBar(),
    )

    # Non-broadcasting operator returns a single Bool — should warn
    bad_evt = Event(d -> all(d.close .> 50.0))
    @test_logs (:warn,) bad_evt(bars)
end

# ── Phase 3: Robustness — Constructor ──

@testitem "Event: Constructor — match kwarg controls logic operator" tags = [:event, :unit] begin
    using Backtest, Test

    evt_all = Event(d -> d.close .> 100.0; match=:all)
    evt_any = Event(d -> d.close .> 100.0; match=:any)
    evt_default = Event(d -> d.close .> 100.0)

    @test evt_all.logic === (&)
    @test evt_any.logic === (|)
    @test evt_default.logic === (&)   # :all is the default
end

@testitem "Event: Constructor — stores conditions as a Tuple" tags = [:event, :unit] begin
    using Backtest, Test

    f1 = d -> d.close .> 100.0
    f2 = d -> d.close .< 110.0
    evt = Event(f1, f2)

    @test evt.conditions isa Tuple
    @test length(evt.conditions) == 2
    @test evt.conditions[1] === f1
    @test evt.conditions[2] === f2
end

@testitem "Event: Constructor — single condition" tags = [:event, :unit] begin
    using Backtest, Test

    f = d -> d.close .> 0.0
    evt = Event(f)

    @test evt isa AbstractEvent
    @test length(evt.conditions) == 1
end

# ── Phase 3: Robustness — DSL Macro Tests ──

@testitem "Macro: @Event — simple symbol rewriting" tags = [:macro, :event] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    # @Event should produce the same indices as the manual form
    evt_manual = Event(d -> d.ema_10 .> d.ema_50; match=:all)
    evt_macro = @Event :ema_10 .> :ema_50 match = :all

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

@testitem "Macro: @Event — match=:any forwarded correctly" tags = [:macro, :event] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    evt_manual = Event(d -> d.ema_10 .> d.ema_50; match=:any)
    evt_macro = @Event :ema_10 .> :ema_50 match = :any

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
    @test evt_macro.logic === (|)
end

@testitem "Macro: @Event — multiple conditions" tags = [:macro, :event] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    evt_manual = Event(d -> d.ema_10 .> d.ema_50, d -> d.ema_10 .> 100.0; match=:all)
    evt_macro = @Event :ema_10 .> :ema_50 :ema_10 .> 100.0 match = :all

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

@testitem "Macro: @Event — complex nested expression" tags = [:macro, :event, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    # Weighted average of two EMAs compared to a literal
    evt_manual = Event(d -> (d.ema_10 .* 0.5 .+ d.ema_50 .* 0.5) .> 100.0)
    evt_macro = @Event (:ema_10 .* 0.5 .+ :ema_50 .* 0.5) .> 100.0

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

@testitem "Macro: @Event — literals pass through untouched" tags = [:macro, :event, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10)(bars)

    # Numeric literal 100.0 must not be rewritten as d.100.0
    evt_manual = Event(d -> d.ema_10 .> 100.0)
    evt_macro = @Event :ema_10 .> 100.0

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

@testitem "Macro: @Event — default match is :all" tags = [:macro, :event] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    evt_implicit = @Event :ema_10 .> :ema_50
    evt_explicit = @Event :ema_10 .> :ema_50 match = :all

    @test evt_implicit(nt).event_indices == evt_explicit(nt).event_indices
    @test evt_implicit.logic === (&)
end

@testitem "Macro: @Event — parenthesised sub-expression" tags = [:macro, :event, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10, 50)(bars)

    # Parenthesised sub-expression — Expr(:call,...) inside Expr(:comparison,...)
    evt_manual = Event(d -> (d.ema_10 .- d.ema_50) .> 0.0)
    evt_macro = @Event (:ema_10 .- :ema_50) .> 0.0

    @test evt_manual(nt).event_indices == evt_macro(nt).event_indices
end

# ── Phase 3: Robustness — Pipeline Integration (basic) ──

@testitem "Event: Callable on PriceBars returns correct keys" tags = [:event, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    evt = Event(d -> d.close .> 100.0)
    result = evt(bars)

    @test haskey(result, :bars)
    @test haskey(result, :event_indices)
    @test result.bars === bars
    @test result.event_indices isa Vector{Int}
end

@testitem "Event: Callable on NamedTuple merges event_indices" tags = [:event, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10)(bars)

    evt = Event(d -> d.ema_10 .> 100.0)
    result = evt(nt)

    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :event_indices)
    @test result.bars === bars
    @test result.event_indices isa Vector{Int}
end

# ── Phase 4: Deep Analysis ──

@testitem "Event: Static Analysis (JET.jl)" tags = [:event, :stability] setup = [TestData] begin
    using Backtest, Test, JET

    bars = TestData.make_pricebars(; n=100)
    evt = Event(d -> d.close .> 100.0)
    nt = EMA(10)(bars)

    @test_opt target_modules = (Backtest,) evt(bars)
    @test_call target_modules = (Backtest,) evt(bars)
    @test_opt target_modules = (Backtest,) evt(nt)
    @test_call target_modules = (Backtest,) evt(nt)
end

# ── Phase 5: Allocation Budget Tests ──

@testitem "Event: Allocation — callable with PriceBars" tags = [:event, :allocation] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> d.close .> 100.0)

    # Warmup
    evt(bars)

    # Budget: result Vector{Int} + BitVector mask + NamedTuple overhead
    n = length(bars)
    budget = sizeof(Int) * n + 512 + 1024

    allocs_evt(evt, bars) = @allocated evt(bars)

    actual = minimum([@allocated(allocs_evt(evt, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Event: Allocation — callable with NamedTuple" tags = [:event, :allocation] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    nt = EMA(10)(bars)
    evt = Event(d -> d.ema_10 .> 100.0)

    # Warmup
    evt(nt)

    n = length(bars)
    budget = sizeof(Int) * n + 512 + 1024

    allocs_evt(evt, nt) = @allocated evt(nt)

    actual = minimum([@allocated(allocs_evt(evt, nt)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Event: Zero Allocations — _resolve_indices kernel" tags = [
    :event, :stability
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> d.close .> 100.0)
    n = length(bars)

    # Pre-allocate mask to isolate the inner loop
    mask = trues(n)
    cond = evt.conditions[1]
    res = cond(bars)

    # Warmup
    mask .= (&).(mask, res)

    allocs_inner(mask, res) = @allocated (mask .= (&).(mask, res))

    actual = minimum([@allocated(allocs_inner(mask, res)) for _ in 1:3])
    @test actual == 0
end

# ── @Event bars-field symbol scoping ──
#
# EventContext maps every :symbol → d.symbol (flat lookup).
# This works when d is a PriceBars (which has .close, .high, etc. directly),
# but fails on a pipeline NamedTuple where price data lives under d.bars.
# BarrierContext handles this distinction via its two-path _replace_symbols;
# EventContext does not. These tests document that behaviour.

@testitem "Macro: @Event — :close symbol resolves on PriceBars directly" tags = [
    :macro, :event
] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [99.0, 100.0, 101.0],
        [100.0, 101.0, 102.0],
        [98.0, 99.0, 100.0],
        [99.5, 100.5, 101.5],
        fill(1000.0, 3),
        [DateTime(2024, 1, i) for i in 1:3],
        TimeBar(),
    )

    # EventContext: :close → d.close. Works when d is PriceBars.
    evt = @Event :close .> 100.0
    result = evt(bars)
    @test result.event_indices == [2, 3]
end

@testitem "Macro: @Event — :close symbol fails on pipeline NamedTuple" tags = [
    :macro, :event, :edge
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    nt = EMA(10)(bars)  # NamedTuple: (bars=PriceBars(...), ema_10=Vector{Float64}(...))

    # EventContext maps :close → d.close, but a pipeline NamedTuple exposes
    # price data under d.bars.close, not at the top level.
    # Use Event(d -> d.bars.close .> 100.0) for pipeline use.
    evt = @Event :close .> 100.0
    @test_throws Exception evt(nt)
end
