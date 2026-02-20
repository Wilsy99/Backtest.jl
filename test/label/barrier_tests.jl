# ── Phase 2: Core Correctness — Constructors ──

@testitem "Barrier: Default constructor labels" tags = [:label, :barrier, :unit] begin
    using Backtest, Test

    lb = LowerBarrier(d -> d.entry_price * 0.95)
    @test lb.label == Int8(-1)
    @test lb.exit_basis isa Immediate

    ub = UpperBarrier(d -> d.entry_price * 1.05)
    @test ub.label == Int8(1)
    @test ub.exit_basis isa Immediate

    tb = TimeBarrier(d -> d.entry_ts)
    @test tb.label == Int8(0)
    @test tb.exit_basis isa Immediate

    cb = ConditionBarrier(d -> true)
    @test cb.label == Int8(0)
    @test cb.exit_basis isa NextOpen  # ConditionBarrier defaults to NextOpen
end

@testitem "Barrier: Custom label and exit_basis" tags = [:label, :barrier, :unit] begin
    using Backtest, Test

    lb = LowerBarrier(d -> 0.0; label=-1, exit_basis=NextOpen())
    @test lb.label == Int8(-1)
    @test lb.exit_basis isa NextOpen

    ub = UpperBarrier(d -> 0.0; label=1, exit_basis=CurrentClose())
    @test ub.label == Int8(1)
    @test ub.exit_basis isa CurrentClose

    tb = TimeBarrier(d -> 0; label=0, exit_basis=NextClose())
    @test tb.label == Int8(0)
    @test tb.exit_basis isa NextClose

    cb = ConditionBarrier(d -> false; label=-1, exit_basis=Immediate())
    @test cb.label == Int8(-1)
    @test cb.exit_basis isa Immediate
end

@testitem "Barrier: Invalid label throws ArgumentError" tags = [:label, :barrier, :unit] begin
    using Backtest, Test

    @test_throws ArgumentError LowerBarrier(d -> 0.0; label=-2)
    @test_throws ArgumentError UpperBarrier(d -> 0.0; label=2)
    @test_throws ArgumentError TimeBarrier(d -> 0; label=5)
    @test_throws ArgumentError ConditionBarrier(d -> false; label=-3)
end

@testitem "Barrier: Subtypes of AbstractBarrier" tags = [:label, :barrier, :unit] begin
    using Backtest, Test

    @test LowerBarrier(d -> 0.0) isa AbstractBarrier
    @test UpperBarrier(d -> 0.0) isa AbstractBarrier
    @test TimeBarrier(d -> 0) isa AbstractBarrier
    @test ConditionBarrier(d -> false) isa AbstractBarrier
end

# ── Phase 2: Core Correctness — barrier_level / gap_hit / barrier_hit ──

@testitem "Barrier: barrier_level evaluates level function" tags = [
    :label, :barrier, :unit
] begin
    using Backtest, Test

    ub = UpperBarrier(d -> d.entry_price * 1.05)
    args = (; entry_price=100.0)
    @test Backtest.barrier_level(ub, args) ≈ 105.0

    lb = LowerBarrier(d -> d.entry_price * 0.95)
    @test Backtest.barrier_level(lb, args) ≈ 95.0

    cb = ConditionBarrier(d -> d.entry_price > 50.0)
    @test Backtest.barrier_level(cb, args) == true
end

@testitem "Barrier: gap_hit dispatch" tags = [:label, :barrier, :unit] begin
    using Backtest, Test, Dates

    lb = LowerBarrier(d -> 0.0)
    ub = UpperBarrier(d -> 0.0)
    tb = TimeBarrier(d -> DateTime(2024, 1, 1))
    cb = ConditionBarrier(d -> false)

    # LowerBarrier: gap-down when open <= level
    @test Backtest.gap_hit(lb, 100.0, 99.0) == true    # open below
    @test Backtest.gap_hit(lb, 100.0, 100.0) == true   # open exactly at
    @test Backtest.gap_hit(lb, 100.0, 101.0) == false   # open above

    # UpperBarrier: gap-up when open >= level
    @test Backtest.gap_hit(ub, 100.0, 101.0) == true   # open above
    @test Backtest.gap_hit(ub, 100.0, 100.0) == true   # open exactly at
    @test Backtest.gap_hit(ub, 100.0, 99.0) == false    # open below

    # Time and Condition barriers never gap
    @test Backtest.gap_hit(tb, DateTime(2024, 1, 1), 100.0) == false
    @test Backtest.gap_hit(cb, true, 100.0) == false
end

@testitem "Barrier: barrier_hit dispatch" tags = [:label, :barrier, :unit] begin
    using Backtest, Test, Dates

    lb = LowerBarrier(d -> 0.0)
    ub = UpperBarrier(d -> 0.0)
    tb = TimeBarrier(d -> DateTime(2024, 1, 1))
    cb = ConditionBarrier(d -> false)

    # LowerBarrier: hit when low <= level
    @test Backtest.barrier_hit(lb, 95.0, 94.0, 110.0, DateTime(2024, 1, 1)) == true
    @test Backtest.barrier_hit(lb, 95.0, 95.0, 110.0, DateTime(2024, 1, 1)) == true
    @test Backtest.barrier_hit(lb, 95.0, 96.0, 110.0, DateTime(2024, 1, 1)) == false

    # UpperBarrier: hit when high >= level
    @test Backtest.barrier_hit(ub, 105.0, 90.0, 106.0, DateTime(2024, 1, 1)) == true
    @test Backtest.barrier_hit(ub, 105.0, 90.0, 105.0, DateTime(2024, 1, 1)) == true
    @test Backtest.barrier_hit(ub, 105.0, 90.0, 104.0, DateTime(2024, 1, 1)) == false

    # TimeBarrier: hit when timestamp >= level
    @test Backtest.barrier_hit(tb, DateTime(2024, 1, 5), 0.0, 0.0, DateTime(2024, 1, 5)) == true
    @test Backtest.barrier_hit(tb, DateTime(2024, 1, 5), 0.0, 0.0, DateTime(2024, 1, 6)) == true
    @test Backtest.barrier_hit(tb, DateTime(2024, 1, 5), 0.0, 0.0, DateTime(2024, 1, 4)) == false

    # ConditionBarrier: hit when level is truthy (level function returns the boolean)
    @test Backtest.barrier_hit(cb, true, 0.0, 0.0, DateTime(2024, 1, 1)) == true
    @test Backtest.barrier_hit(cb, false, 0.0, 0.0, DateTime(2024, 1, 1)) == false
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Barrier: Boundary equality — lower at exactly low" tags = [
    :label, :barrier, :edge
] begin
    using Backtest, Test, Dates

    lb = LowerBarrier(d -> 100.0)
    # Exactly at level is a hit (<=)
    @test Backtest.barrier_hit(lb, 100.0, 100.0, 110.0, DateTime(2024, 1, 1)) == true
    # One tick above is not a hit
    @test Backtest.barrier_hit(lb, 100.0, 100.0 + eps(100.0), 110.0, DateTime(2024, 1, 1)) == false
end

@testitem "Barrier: Boundary equality — upper at exactly high" tags = [
    :label, :barrier, :edge
] begin
    using Backtest, Test, Dates

    ub = UpperBarrier(d -> 110.0)
    # Exactly at level is a hit (>=)
    @test Backtest.barrier_hit(ub, 110.0, 90.0, 110.0, DateTime(2024, 1, 1)) == true
    # One tick below is not a hit
    @test Backtest.barrier_hit(ub, 110.0, 90.0, 110.0 - eps(110.0), DateTime(2024, 1, 1)) == false
end

# ── Phase 3: Robustness — Macro Tests ──

@testitem "Macro: @UpperBarrier default label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    ub = @UpperBarrier :entry_price * 1.05
    @test ub isa UpperBarrier
    @test ub.label == Int8(1)
    @test ub.exit_basis isa Immediate
end

@testitem "Macro: @LowerBarrier default label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    lb = @LowerBarrier :entry_price * 0.95
    @test lb isa LowerBarrier
    @test lb.label == Int8(-1)
    @test lb.exit_basis isa Immediate
end

@testitem "Macro: @TimeBarrier default label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test, Dates

    tb = @TimeBarrier :entry_ts + Day(20)
    @test tb isa TimeBarrier
    @test tb.label == Int8(0)
end

@testitem "Macro: @ConditionBarrier default label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    cb = @ConditionBarrier :close <= :entry_price
    @test cb isa ConditionBarrier
    @test cb.label == Int8(0)
    @test cb.exit_basis isa NextOpen
end

@testitem "Macro: @UpperBarrier with custom label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    ub = @UpperBarrier :entry_price * 1.10 label = 0
    @test ub isa UpperBarrier
    @test ub.label == Int8(0)
end

@testitem "Macro: @LowerBarrier with custom label" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    lb = @LowerBarrier :entry_price * 0.90 label = 0
    @test lb isa LowerBarrier
    @test lb.label == Int8(0)
end

@testitem "Macro: Invalid label throws ArgumentError" tags = [:macro, :label, :barrier] begin
    using Backtest, Test

    @test_throws ArgumentError @UpperBarrier :entry_price * 1.10 label = 2
    @test_throws ArgumentError @LowerBarrier :entry_price * 0.90 label = -5
end

@testitem "Macro: Barrier symbol rewriting — direct fields" tags = [
    :macro, :label, :barrier
] begin
    using Backtest, Test, Dates

    # @UpperBarrier :entry_price * 1.05 should produce a function that
    # accesses d.entry_price (a direct field in barrier context)
    ub = @UpperBarrier :entry_price * 1.05
    manual_ub = UpperBarrier(d -> d.entry_price * 1.05)

    d = (;
        entry_price=100.0,
        entry_ts=DateTime(2024, 1, 1),
        idx=5,
        bars=PriceBars(
            fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
            fill(105.0, 10), fill(1000.0, 10),
            [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
        ),
    )

    @test Backtest.barrier_level(ub, d) ≈ Backtest.barrier_level(manual_ub, d)
end

@testitem "Macro: Barrier symbol rewriting — bars fields" tags = [
    :macro, :label, :barrier
] begin
    using Backtest, Test, Dates

    # :close in BarrierContext should rewrite to d.bars.close[d.idx]
    cb = @ConditionBarrier :close > :entry_price
    manual_cb = ConditionBarrier(d -> d.bars.close[d.idx] > d.entry_price)

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        [95.0 + i for i in 1:10], fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )

    d = (; entry_price=100.0, entry_ts=DateTime(2024, 1, 1), idx=5, bars=bars)

    @test Backtest.barrier_level(cb, d) == Backtest.barrier_level(manual_cb, d)
end

@testitem "Macro: Barrier symbol rewriting — feature fields" tags = [
    :macro, :label, :barrier
] begin
    using Backtest, Test, Dates

    # :ema_10 in BarrierContext should rewrite to d.ema_10[d.idx]
    ub = @UpperBarrier :entry_price + :ema_10

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        fill(100.0, 10), fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )
    ema_10 = collect(1.0:10.0)

    d = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        idx=5, bars=bars, ema_10=ema_10,
    )

    @test Backtest.barrier_level(ub, d) ≈ 100.0 + 5.0  # entry_price + ema_10[5]
end

@testitem "Macro: Complex barrier expression — nested arithmetic" tags = [
    :macro, :label, :barrier, :edge
] begin
    using Backtest, Test, Dates

    # Multiple symbols mixed with literals
    ub = @UpperBarrier :entry_price * 0.5 + :ema_10 * 0.5

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        fill(100.0, 10), fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )
    ema_10 = fill(200.0, 10)

    d = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        idx=3, bars=bars, ema_10=ema_10,
    )

    @test Backtest.barrier_level(ub, d) ≈ 100.0 * 0.5 + 200.0 * 0.5  # = 150.0
end

@testitem "Macro: @ConditionBarrier with boolean operators" tags = [
    :macro, :label, :barrier, :edge
] begin
    using Backtest, Test, Dates

    # Boolean combination: :close <= :entry_price
    cb = @ConditionBarrier :close <= :entry_price

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        [105.0, 100.0, 95.0, 90.0, 85.0, 80.0, 75.0, 70.0, 65.0, 60.0],
        fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )

    # At idx=1, close=105 > entry_price=100 → false
    d1 = (; entry_price=100.0, entry_ts=DateTime(2024, 1, 1), idx=1, bars=bars)
    @test Backtest.barrier_level(cb, d1) == false

    # At idx=2, close=100 <= entry_price=100 → true
    d2 = (; entry_price=100.0, entry_ts=DateTime(2024, 1, 1), idx=2, bars=bars)
    @test Backtest.barrier_level(cb, d2) == true

    # At idx=3, close=95 <= entry_price=100 → true
    d3 = (; entry_price=100.0, entry_ts=DateTime(2024, 1, 1), idx=3, bars=bars)
    @test Backtest.barrier_level(cb, d3) == true
end

@testitem "Macro: Literal-heavy barrier expression" tags = [:macro, :label, :barrier, :edge] begin
    using Backtest, Test

    # The symbol walker must not rewrite numeric literals
    lb = @LowerBarrier 0.95 * :entry_price - 2.0
    @test lb isa LowerBarrier
    @test lb.label == Int8(-1)

    d = (; entry_price=100.0, entry_ts=nothing, idx=1,
        bars=(; close=[0.0], open=[0.0], high=[0.0], low=[0.0], volume=[0.0], timestamp=[nothing]))
    @test Backtest.barrier_level(lb, d) ≈ 0.95 * 100.0 - 2.0  # = 93.0
end

# ── entry_side macro rewriting ──

@testitem "Macro: :entry_side is a direct field (scalar access)" tags = [
    :macro, :label, :barrier
] begin
    using Backtest, Test, Dates

    # :entry_side should rewrite to d.entry_side (scalar), not d.entry_side[d.idx]
    lb = @LowerBarrier :entry_side == 1 ? :entry_price * 0.95 : :entry_price * 0.90

    bars = PriceBars(
        fill(100.0, 10), fill(110.0, 10), fill(90.0, 10),
        fill(100.0, 10), fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )

    # Long trade (entry_side = 1) → barrier at 0.95 * 100 = 95.0
    d_long = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        entry_side=Int8(1), idx=5, bars=bars,
    )
    @test Backtest.barrier_level(lb, d_long) ≈ 95.0

    # Short trade (entry_side = -1) → barrier at 0.90 * 100 = 90.0
    d_short = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        entry_side=Int8(-1), idx=5, bars=bars,
    )
    @test Backtest.barrier_level(lb, d_short) ≈ 90.0
end

@testitem "Macro: :entry_side in @UpperBarrier" tags = [:macro, :label, :barrier] begin
    using Backtest, Test, Dates

    ub = @UpperBarrier :entry_side == 1 ? :entry_price * 1.05 : :entry_price * 1.10

    bars = PriceBars(
        fill(100.0, 5), fill(110.0, 5), fill(90.0, 5),
        fill(100.0, 5), fill(1000.0, 5),
        [DateTime(2024, 1, i) for i in 1:5], TimeBar(),
    )

    d_long = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        entry_side=Int8(1), idx=3, bars=bars,
    )
    @test Backtest.barrier_level(ub, d_long) ≈ 105.0

    d_short = (;
        entry_price=100.0, entry_ts=DateTime(2024, 1, 1),
        entry_side=Int8(-1), idx=3, bars=bars,
    )
    @test Backtest.barrier_level(ub, d_short) ≈ 110.0
end
