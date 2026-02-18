# ── Shared Test Data ──────────────────────────────────────────────────────────
#
# 60 bars with close prices rising 100 → 159.  Highs are close + 1, lows are
# close - 1.  Three events at bars 1, 10, 20.  A fixed UpperBarrier at 130.0
# (hit when high >= 130, i.e. bar 31 where close = 130, high = 131) and a
# TimeBarrier that fires at the timestamp of bar 50.  The LowerBarrier at 80.0
# is never hit.  All three events finish within the 60-bar window so
# drop_unfinished=true produces three rows.

@testsetup module LabelTestData
using Backtest, Dates, Test

function make_label_bars(; n=60)
    closes = [100.0 + (i - 1) for i in 1:n]
    opens = closes .- 0.5
    highs = closes .+ 1.0
    lows = closes .- 1.0
    volumes = fill(1000.0, n)
    timestamps = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    return PriceBars(opens, highs, lows, closes, volumes, timestamps, TimeBar())
end

end  # module LabelTestData

# ── Phase 1: Constructor ───────────────────────────────────────────────────────

@testitem "Label: multi_thread=false — default" tags = [:label, :unit] begin
    using Backtest, Test

    upper = UpperBarrier(d -> 130.0)
    lab = Label(upper)
    @test lab.multi_thread === false

    lab_mt = Label(upper; multi_thread=true)
    @test lab_mt.multi_thread === true
end

@testitem "Label!: multi_thread=false — default" tags = [:label, :unit] begin
    using Backtest, Test

    upper = UpperBarrier(d -> 130.0)
    lab = Label!(upper)
    @test lab.multi_thread === false

    lab_mt = Label!(upper; multi_thread=true)
    @test lab_mt.multi_thread === true
end

# ── Phase 2: Correctness ──────────────────────────────────────────────────────

@testitem "Label: multi_thread=true matches single-threaded results" tags = [
    :label, :unit
] setup = [LabelTestData] begin
    using Backtest, Test

    bars = LabelTestData.make_label_bars()
    event_indices = [1, 10, 20]
    upper = UpperBarrier(d -> 130.0; label=1)
    lower = LowerBarrier(d -> 80.0; label=-1)

    result_mt = calculate_label(
        event_indices, bars, (upper, lower); multi_thread=true
    )
    result_st = calculate_label(
        event_indices, bars, (upper, lower); multi_thread=false
    )

    @test result_mt.entry_idx == result_st.entry_idx
    @test result_mt.exit_idx == result_st.exit_idx
    @test result_mt.label == result_st.label
    @test result_mt.ret ≈ result_st.ret
    @test result_mt.log_ret ≈ result_st.log_ret
    @test result_mt.weight ≈ result_st.weight
end

@testitem "Label: multi_thread=true — Label functor matches single-threaded" tags = [
    :label, :unit
] setup = [LabelTestData] begin
    using Backtest, Test

    bars = LabelTestData.make_label_bars()
    nt_input = EMA(10)(bars)
    nt_with_events = merge(nt_input, (; event_indices=[1, 10, 20]))

    upper = UpperBarrier(d -> 130.0; label=1)

    lab_mt = Label(upper; multi_thread=true)
    lab_st = Label(upper; multi_thread=false)

    r_mt = lab_mt(nt_with_events)
    r_st = lab_st(nt_with_events)

    @test r_mt.labels.entry_idx == r_st.labels.entry_idx
    @test r_mt.labels.exit_idx == r_st.labels.exit_idx
    @test r_mt.labels.label == r_st.labels.label
    @test r_mt.labels.ret ≈ r_st.labels.ret
end

@testitem "Label!: multi_thread=true matches single-threaded results" tags = [
    :label, :unit
] setup = [LabelTestData] begin
    using Backtest, Test

    bars = LabelTestData.make_label_bars()
    nt_input = EMA(10)(bars)
    nt_with_events = merge(nt_input, (; event_indices=[1, 10, 20]))

    upper = UpperBarrier(d -> 130.0; label=1)

    lab_mt = Label!(upper; multi_thread=true)
    lab_st = Label!(upper; multi_thread=false)

    r_mt = lab_mt(nt_with_events)
    r_st = lab_st(nt_with_events)

    @test r_mt.entry_idx == r_st.entry_idx
    @test r_mt.exit_idx == r_st.exit_idx
    @test r_mt.label == r_st.label
    @test r_mt.ret ≈ r_st.ret
end
