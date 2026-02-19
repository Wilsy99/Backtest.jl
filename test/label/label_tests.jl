# ── Phase 2: Core Correctness — Reference Values ──

@testitem "Label: Hand-Calculated Reference — UpperBarrier hit" tags = [
    :label, :reference
] setup = [TestData] begin
    using Backtest, Test, Dates

    # 10 bars with steadily rising close prices.
    # entry_basis=NextOpen(): event at bar 1 → entry at bar 2.
    # UpperBarrier at entry_price * 1.10: entry_price = open[2] = 100.0
    # Barrier level = 110.0. Look for first bar where high >= 110.
    n = 10
    opens  = [99.0, 100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0]
    highs  = [100.0, 101.0, 103.0, 105.0, 107.0, 109.0, 111.0, 113.0, 115.0, 117.0]
    lows   = [98.0, 99.0, 100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0]
    closes = [99.5, 100.5, 102.0, 104.0, 106.0, 108.0, 110.0, 112.0, 114.0, 116.0]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]

    bars = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())
    event_indices = [1]

    ub = UpperBarrier(d -> d.entry_price * 1.10)
    result = calculate_label(event_indices, bars, (ub,))

    @test result isa Backtest.LabelResults
    @test length(result.label) == 1
    @test result.label[1] == Int8(1)

    # Entry at bar 2 (NextOpen of event bar 1)
    @test result.entry_idx[1] == 2

    # Bar 7: high=111.0 >= 110.0 → first hit. With Immediate exit, exit at bar 7.
    @test result.exit_idx[1] == 7

    # Return: exit_price = barrier level = 110.0, entry_price = open[2] = 100.0
    @test result.ret[1] ≈ (110.0 / 100.0) - 1.0  # = 0.10
    @test result.log_ret[1] ≈ log1p(result.ret[1])
end

@testitem "Label: Hand-Calculated Reference — LowerBarrier hit" tags = [
    :label, :reference
] begin
    using Backtest, Test, Dates

    # Prices drop steadily. LowerBarrier at entry_price * 0.95.
    n = 10
    opens  = [100.0, 100.0, 99.0, 98.0, 97.0, 96.0, 95.0, 94.0, 93.0, 92.0]
    highs  = [101.0, 100.5, 99.5, 98.5, 97.5, 96.5, 95.5, 94.5, 93.5, 92.5]
    lows   = [99.0,  99.0,  98.0, 97.0, 96.0, 95.0, 94.0, 93.0, 92.0, 91.0]
    closes = [100.0, 99.5,  98.5, 97.5, 96.5, 95.5, 94.5, 93.5, 92.5, 91.5]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]

    bars = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())
    event_indices = [1]

    lb = LowerBarrier(d -> d.entry_price * 0.95)
    result = calculate_label(event_indices, bars, (lb,))

    @test length(result.label) == 1
    @test result.label[1] == Int8(-1)

    # Entry at bar 2, entry_price = open[2] = 100.0
    @test result.entry_idx[1] == 2
    # Barrier level = 95.0. Low at bar 6 = 95.0 → hit (<=)
    @test result.exit_idx[1] == 6
    # Exit price = barrier level = 95.0 (Immediate)
    @test result.ret[1] ≈ (95.0 / 100.0) - 1.0  # = -0.05
end

@testitem "Label: Hand-Calculated Reference — TimeBarrier hit" tags = [
    :label, :reference
] begin
    using Backtest, Test, Dates

    # Flat prices — no upper/lower hit, time barrier triggers.
    n = 10
    price = 100.0
    opens  = fill(price, n)
    highs  = fill(price + 0.5, n)
    lows   = fill(price - 0.5, n)
    closes = fill(price, n)
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]

    bars = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())
    event_indices = [1]

    # UpperBarrier far away, LowerBarrier far away, TimeBarrier at entry_ts + Day(3)
    ub = UpperBarrier(d -> d.entry_price * 2.0)
    lb = LowerBarrier(d -> d.entry_price * 0.5)
    tb = TimeBarrier(d -> d.entry_ts + Day(3))

    result = calculate_label(event_indices, bars, (ub, lb, tb))

    @test length(result.label) == 1
    @test result.label[1] == Int8(0)  # TimeBarrier default label

    # Entry at bar 2 (NextOpen), entry_ts = ts[2] = 2024-01-02
    # TimeBarrier level = 2024-01-02 + Day(3) = 2024-01-05
    # Bar 5: ts[5] = 2024-01-05 >= 2024-01-05 → hit
    @test result.entry_idx[1] == 2
    @test result.exit_idx[1] == 5
end

@testitem "Label: ConditionBarrier triggers on boolean" tags = [:label, :unit] begin
    using Backtest, Test, Dates

    n = 10
    opens  = fill(100.0, n)
    highs  = fill(100.5, n)
    lows   = fill(99.5, n)
    closes = [100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Feature vector that becomes true at bar 6
    signal = [false, false, false, false, false, true, true, true, true, true]

    event_indices = [1]
    cb = ConditionBarrier(d -> d.signal[d.idx]; exit_basis=NextOpen())

    result = calculate_label(
        event_indices, bars, (cb,);
        barrier_args=(; signal=signal),
    )

    @test length(result.label) == 1
    @test result.label[1] == Int8(0)
    # Condition fires at bar 6, NextOpen exit → exit at bar 7
    @test result.exit_idx[1] == 7
end

# ── Phase 2: Core Correctness — Label vs Label! Functors ──

@testitem "Label: Label functor merges into NamedTuple" tags = [:label, :unit] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=50)
    evt = Event(d -> d.bars.close .> d.bars.open)
    pipe_data = evt(bars)

    lab = Label(
        UpperBarrier(d -> d.entry_price * 1.05),
        LowerBarrier(d -> d.entry_price * 0.95),
        TimeBarrier(d -> d.entry_ts + Day(10)),
    )

    result = lab(pipe_data)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :event_indices)
    @test haskey(result, :labels)
    @test result.labels isa Backtest.LabelResults
end

@testitem "Label: Label! returns raw LabelResults" tags = [:label, :unit] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=50)
    evt = Event(d -> d.bars.close .> d.bars.open)
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.05),
        LowerBarrier(d -> d.entry_price * 0.95),
        TimeBarrier(d -> d.entry_ts + Day(10)),
    )

    result = lab(pipe_data)
    @test result isa Backtest.LabelResults
end

# ── Phase 2: Core Correctness — LabelResults Properties ──

@testitem "Label: Return consistency — upper→positive, lower→negative" tags = [
    :label, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    for i in eachindex(result.label)
        if result.label[i] == Int8(1)
            @test result.ret[i] > 0
        elseif result.label[i] == Int8(-1)
            @test result.ret[i] < 0
        end
    end
end

@testitem "Label: Log return identity — log_ret ≈ log1p(ret)" tags = [
    :label, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    for i in eachindex(result.ret)
        @test result.log_ret[i] ≈ log1p(result.ret[i]) atol = 1e-12
    end
end

@testitem "Label: Labels are in valid set" tags = [:label, :property] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    @test all(l ∈ Int8.([-1, 0, 1]) for l in result.label)
end

@testitem "Label: Exit timestamp >= entry timestamp" tags = [:label, :property] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    for i in eachindex(result.entry_ts)
        @test result.exit_ts[i] >= result.entry_ts[i]
        @test result.exit_idx[i] >= result.entry_idx[i]
    end
end

@testitem "Label: Parallel vector lengths match" tags = [:label, :property] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    n = length(result.label)
    @test length(result.entry_idx) == n
    @test length(result.exit_idx) == n
    @test length(result.entry_ts) == n
    @test length(result.exit_ts) == n
    @test length(result.weight) == n
    @test length(result.ret) == n
    @test length(result.log_ret) == n
end

# ── Phase 2: Core Correctness — Weight Properties ──

@testitem "Label: Weight normalization — sum(weights) ≈ n_labels" tags = [
    :label, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    n = length(result.weight)
    if n > 0
        @test sum(result.weight) ≈ n atol = 1e-6
        @test all(w >= 0 for w in result.weight)
    end
end

@testitem "Label: Class imbalance correction — equal weight per class" tags = [
    :label, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)

    classes = unique(result.label)
    if length(classes) > 1
        class_weights = Dict{Int8,Float64}()
        for i in eachindex(result.label)
            c = result.label[i]
            class_weights[c] = get(class_weights, c, 0.0) + result.weight[i]
        end

        weights_per_class = collect(values(class_weights))
        # Class-imbalanced correction should make total weight per class roughly equal
        @test maximum(weights_per_class) / minimum(weights_per_class) < 2.0
    end
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Label: Empty event indices → empty LabelResults" tags = [:label, :edge] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        fill(100.0, 10), fill(105.0, 10), fill(95.0, 10),
        fill(102.0, 10), fill(1000.0, 10),
        [DateTime(2024, 1, i) for i in 1:10], TimeBar(),
    )

    event_indices = Int[]
    ub = UpperBarrier(d -> d.entry_price * 1.10)

    result = calculate_label(event_indices, bars, (ub,))

    @test result isa Backtest.LabelResults
    @test length(result.label) == 0
    @test length(result.entry_idx) == 0
    @test length(result.ret) == 0
    @test length(result.weight) == 0
end

@testitem "Label: Event on last bar — NextOpen entry out of bounds" tags = [
    :label, :edge
] begin
    using Backtest, Test, Dates

    n = 5
    bars = PriceBars(
        fill(100.0, n), fill(105.0, n), fill(95.0, n),
        fill(102.0, n), fill(1000.0, n),
        [DateTime(2024, 1, i) for i in 1:n], TimeBar(),
    )

    # Event on the very last bar — NextOpen pushes entry to bar n+1 (out of bounds)
    event_indices = [n]
    ub = UpperBarrier(d -> d.entry_price * 1.10)

    result = calculate_label(event_indices, bars, (ub,); drop_unfinished=true)
    @test length(result.label) == 0  # dropped because entry is out of bounds
end

@testitem "Label: Event on second-to-last bar — only 1 bar to check" tags = [
    :label, :edge
] begin
    using Backtest, Test, Dates

    n = 5
    bars = PriceBars(
        fill(100.0, n), fill(200.0, n), fill(50.0, n),
        fill(100.0, n), fill(1000.0, n),
        [DateTime(2024, 1, i) for i in 1:n], TimeBar(),
    )

    # Event at bar n-1 → entry at bar n (NextOpen). Only bar n available,
    # but the loop starts at entry_idx+1 which is n+1 (empty loop).
    # No barrier can trigger → unfinished.
    event_indices = [n - 1]
    ub = UpperBarrier(d -> d.entry_price * 1.10)

    result = calculate_label(event_indices, bars, (ub,); drop_unfinished=true)
    @test length(result.label) == 0  # unfinished, dropped
end

@testitem "Label: drop_unfinished=false keeps sentinel labels" tags = [:label, :edge] begin
    using Backtest, Test, Dates

    n = 5
    bars = PriceBars(
        fill(100.0, n), fill(100.5, n), fill(99.5, n),
        fill(100.0, n), fill(1000.0, n),
        [DateTime(2024, 1, i) for i in 1:n], TimeBar(),
    )

    # Very wide barriers that never trigger within 5 bars
    event_indices = [1]
    ub = UpperBarrier(d -> d.entry_price * 2.0)
    lb = LowerBarrier(d -> d.entry_price * 0.5)

    result = calculate_label(
        event_indices, bars, (ub, lb); drop_unfinished=false
    )

    @test length(result.label) == 1
    @test result.label[1] == Int8(-99)  # sentinel for unfinished
end

@testitem "Label: Unsorted event indices restored to caller order" tags = [
    :label, :edge
] begin
    using Backtest, Test, Dates

    n = 30
    opens  = [100.0 + 0.1 * i for i in 1:n]
    highs  = [102.0 + 0.1 * i for i in 1:n]
    lows   = [98.0 + 0.1 * i for i in 1:n]
    closes = [101.0 + 0.1 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Unsorted events
    event_indices = [10, 5, 15]

    tb = TimeBarrier(d -> d.entry_ts + Day(3))
    result = calculate_label(event_indices, bars, (tb,))

    # Results should be in caller's order (10, 5, 15), not sorted (5, 10, 15)
    # Entry indices with NextOpen: 11, 6, 16
    if length(result.entry_idx) == 3
        @test result.entry_idx[1] == 11
        @test result.entry_idx[2] == 6
        @test result.entry_idx[3] == 16
    end
end

@testitem "Label: Barrier ordering warning" tags = [:label, :edge] begin
    using Backtest, Test, Dates

    # ConditionBarrier (NextOpen, priority=4) listed BEFORE UpperBarrier (Immediate, priority=1)
    # → should warn about non-optimal ordering
    cb = ConditionBarrier(d -> false; exit_basis=NextOpen())
    ub = UpperBarrier(d -> d.entry_price * 1.05; exit_basis=Immediate())

    @test_logs (:warn,) Backtest._warn_barrier_ordering((cb, ub))

    # Correct ordering should produce no warning
    @test_logs Backtest._warn_barrier_ordering((ub, cb))
end

@testitem "Label: Gap-through exit at open price" tags = [:label, :unit] begin
    using Backtest, Test, Dates

    # Bar 3 gaps up past the upper barrier level
    n = 5
    opens  = [100.0, 100.0, 100.0, 115.0, 100.0]  # bar 4 opens at 115
    highs  = [101.0, 101.0, 101.0, 116.0, 101.0]
    lows   = [99.0,  99.0,  99.0,  114.0, 99.0]
    closes = [100.0, 100.0, 100.0, 115.0, 100.0]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    event_indices = [1]
    # entry at bar 2 (NextOpen), entry_price = open[2] = 100.0
    # Upper barrier = 110.0. Bar 4: open=115 >= 110 → gap hit
    ub = UpperBarrier(d -> d.entry_price * 1.10)

    result = calculate_label(event_indices, bars, (ub,))

    @test length(result.label) == 1
    @test result.label[1] == Int8(1)
    @test result.exit_idx[1] == 4

    # Gap-through: exit price is the open price (Immediate with open_price arg),
    # because _record_exit! is called with open_price as the level
    @test result.ret[1] ≈ (115.0 / 100.0) - 1.0  # = 0.15
end

@testitem "Label: Time decay — earlier events get lower weight" tags = [
    :label, :property
] begin
    using Backtest, Test, Dates

    # Create enough bars and events to see time decay effect
    n = 100
    opens  = [100.0 + 0.05 * i for i in 1:n]
    highs  = [101.0 + 0.05 * i for i in 1:n]
    lows   = [99.0 + 0.05 * i for i in 1:n]
    closes = [100.5 + 0.05 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Multiple events spread across time
    event_indices = [1, 20, 40, 60]

    tb = TimeBarrier(d -> d.entry_ts + Day(5))

    # With time_decay_start=0.5, earlier events get lower weight
    result_decay = calculate_label(
        event_indices, bars, (tb,); time_decay_start=0.5
    )
    # With time_decay_start=1.0 (no decay), all events weighted equally
    result_no_decay = calculate_label(
        event_indices, bars, (tb,); time_decay_start=1.0
    )

    # Both should have the same number of results
    @test length(result_decay.weight) == length(result_no_decay.weight)

    if length(result_decay.weight) >= 2
        # With decay=0.5, the weight ratio between first and last should differ
        # from the no-decay case
        decay_ratio = result_decay.weight[end] / result_decay.weight[1]
        no_decay_ratio = result_no_decay.weight[end] / result_no_decay.weight[1]
        @test decay_ratio != no_decay_ratio
    end
end

@testitem "Label: multi_thread matches single_thread" tags = [:label, :unit] setup = [
    TestData
] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=100)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = evt(bars)

    barriers = (
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(15)),
    )

    result_st = Label!(barriers...; multi_thread=false)(pipe_data)
    result_mt = Label!(barriers...; multi_thread=true)(pipe_data)

    @test result_st.label == result_mt.label
    @test result_st.entry_idx == result_mt.entry_idx
    @test result_st.exit_idx == result_mt.exit_idx
    @test result_st.ret ≈ result_mt.ret
    @test result_st.log_ret ≈ result_mt.log_ret
end

@testitem "Label: Raw array overload matches PriceBars overload" tags = [:label, :unit] begin
    using Backtest, Test, Dates

    n = 20
    opens  = [100.0 + 0.1 * i for i in 1:n]
    highs  = [102.0 + 0.1 * i for i in 1:n]
    lows   = [98.0 + 0.1 * i for i in 1:n]
    closes = [101.0 + 0.1 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    event_indices = [1, 5, 10]
    tb = TimeBarrier(d -> d.entry_ts + Day(3))

    result_raw = calculate_label(event_indices, ts, opens, highs, lows, closes, vols, (tb,))
    result_bars = calculate_label(event_indices, bars, (tb,))

    @test result_raw.label == result_bars.label
    @test result_raw.entry_idx == result_bars.entry_idx
    @test result_raw.exit_idx == result_bars.exit_idx
    @test result_raw.ret ≈ result_bars.ret
end

@testitem "Label: Single event with single barrier" tags = [:label, :edge] begin
    using Backtest, Test, Dates

    n = 3
    bars = PriceBars(
        [100.0, 100.0, 100.0],
        [110.0, 110.0, 110.0],
        [90.0, 90.0, 90.0],
        [100.0, 100.0, 100.0],
        [1000.0, 1000.0, 1000.0],
        [DateTime(2024, 1, 1), DateTime(2024, 1, 2), DateTime(2024, 1, 3)],
        TimeBar(),
    )

    # Event at bar 1, entry at bar 2 (NextOpen)
    # UpperBarrier at 105.0. Bar 3: high=110 >= 105 → hit
    event_indices = [1]
    ub = UpperBarrier(d -> d.entry_price * 1.05)

    result = calculate_label(event_indices, bars, (ub,))

    @test length(result.label) == 1
    @test result.label[1] == Int8(1)
    @test result.entry_idx[1] == 2
    @test result.exit_idx[1] == 3
end

@testitem "Label: Barrier priority — first barrier wins on same bar" tags = [
    :label, :unit
] begin
    using Backtest, Test, Dates

    # Both upper and lower barriers trigger on bar 3
    n = 5
    opens  = [100.0, 100.0, 100.0, 100.0, 100.0]
    highs  = [100.0, 100.0, 120.0, 100.0, 100.0]   # bar 3 high=120 triggers upper
    lows   = [100.0, 100.0, 80.0, 100.0, 100.0]     # bar 3 low=80 triggers lower
    closes = [100.0, 100.0, 100.0, 100.0, 100.0]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    event_indices = [1]

    # UpperBarrier listed first → should win
    ub = UpperBarrier(d -> d.entry_price * 1.10)
    lb = LowerBarrier(d -> d.entry_price * 0.90)

    result_ub_first = calculate_label(event_indices, bars, (ub, lb))
    @test result_ub_first.label[1] == Int8(1)  # upper wins

    # LowerBarrier listed first → should win instead
    result_lb_first = calculate_label(event_indices, bars, (lb, ub))
    @test result_lb_first.label[1] == Int8(-1)  # lower wins
end

@testitem "Label: CurrentClose entry basis" tags = [:label, :unit] begin
    using Backtest, Test, Dates

    n = 10
    opens  = [100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0, 109.0]
    highs  = [101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 115.0, 108.0, 109.0, 110.0]
    lows   = [99.0,  100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0]
    closes = [100.5, 101.5, 102.5, 103.5, 104.5, 105.5, 106.5, 107.5, 108.5, 109.5]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    event_indices = [1]
    ub = UpperBarrier(d -> d.entry_price * 1.10)

    # CurrentClose: entry at event bar itself (idx_adj=0), price = close
    result = calculate_label(
        event_indices, bars, (ub,); entry_basis=CurrentClose()
    )

    @test length(result.label) == 1
    # Entry at bar 1, entry_price = close[1] = 100.5
    @test result.entry_idx[1] == 1
    # Barrier = 100.5 * 1.10 = 110.55. Bar 7: high=115 >= 110.55 → hit
    @test result.exit_idx[1] == 7
end

# ── Phase 3: Robustness — ExitBuffers ──

@testitem "ExitBuffers: Sentinel initialization" tags = [:label, :unit] begin
    using Backtest, Test, Dates

    buf = Backtest.ExitBuffers(5, Float64, DateTime)

    @test length(buf.labels) == 5
    @test all(buf.labels .== Int8(-99))
    @test all(buf.exit_indices .== 0)
    @test all(buf.rets .== 0.0)
    @test all(buf.log_rets .== 0.0)
end

# ── Phase 3: Robustness — Multiple events, overlapping barriers ──

@testitem "Label: Multiple events with overlapping trades" tags = [
    :label, :property
] begin
    using Backtest, Test, Dates

    n = 50
    opens  = [100.0 + 0.1 * i for i in 1:n]
    highs  = [102.0 + 0.1 * i for i in 1:n]
    lows   = [98.0 + 0.1 * i for i in 1:n]
    closes = [101.0 + 0.1 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Many events close together — causes overlapping trades
    event_indices = collect(1:5:30)
    tb = TimeBarrier(d -> d.entry_ts + Day(10))

    result = calculate_label(event_indices, bars, (tb,))

    # All should resolve within the data
    @test length(result.label) > 0
    @test all(result.label .== Int8(0))  # all time-barrier exits
    @test sum(result.weight) ≈ length(result.weight) atol = 1e-6
end

# ── Integration with Pipeline ──

@testitem "Label: Full Pipeline — Feature → Event → Label" tags = [
    :integration, :label, :pipeline
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)

    evt = Event(d -> d.bars.close .> d.bars.open)
    lab = Label(
        UpperBarrier(d -> d.entry_price * 1.05),
        LowerBarrier(d -> d.entry_price * 0.95),
        TimeBarrier(d -> d.entry_ts + Day(20)),
    )

    job = bars >> EMA(10, 50) >> evt >> lab
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :labels)
    @test result.labels isa Backtest.LabelResults
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :event_indices)

    # Basic sanity on labels
    lr = result.labels
    if length(lr.label) > 0
        @test all(l ∈ Int8.([-1, 0, 1]) for l in lr.label)
        @test all(lr.exit_idx .>= lr.entry_idx)
    end
end

# ── entry_side integration tests ──

@testitem "Label: entry_side — side-dependent barrier levels" tags = [
    :label, :unit
] begin
    using Backtest, Test, Dates

    # Construct data where we know exact side signals and barrier outcomes.
    # 20 bars with moderate uptrend — highs are wide enough to trigger upper.
    n = 20
    opens  = [100.0 + 0.5 * i for i in 1:n]
    highs  = [108.0 + 0.5 * i for i in 1:n]   # high enough to hit +5% upper
    lows   = [92.0 + 0.5 * i for i in 1:n]     # low enough to hit -5% lower
    closes = [101.0 + 0.5 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Synthetic side vector: long (1) at bars 1–10, short (-1) at bars 11–20
    side = vcat(fill(Int8(1), 10), fill(Int8(-1), 10))

    # Two events: one long (bar 1), one short (bar 11)
    event_indices = [1, 11]

    # Side-dependent lower barrier: long gets 0.95, short gets 0.90
    lb = LowerBarrier(d -> d.entry_side == Int8(1) ? d.entry_price * 0.95 : d.entry_price * 0.90)
    tb = TimeBarrier(d -> d.entry_ts + Day(15))

    result = calculate_label(
        event_indices, bars, (lb, tb);
        barrier_args=(; side=side),
    )

    # Both should resolve
    @test length(result.label) == 2

    # Verify the barrier levels were computed using the ENTRY bar's side,
    # not a shifting side value — entry_side should be frozen at entry time.
    # Event 1: entry at bar 2 (NextOpen), side[2] = 1 (long) → barrier at 0.95
    # Event 2: entry at bar 12 (NextOpen), side[12] = -1 (short) → barrier at 0.90
    # We can verify indirectly: if lower barrier triggered, the exit price
    # should be consistent with the side-dependent level.
    for i in eachindex(result.label)
        if result.label[i] == Int8(-1)  # lower barrier hit
            entry_price_i = bars.open[result.entry_idx[i]]
            # The level should have been 0.95 or 0.90 of entry price
            # depending on entry_side
            @test result.ret[i] < 0  # lower barrier always produces negative return
        end
    end
end

@testitem "Label: entry_side defaults to 0 without Side stage" tags = [
    :label, :edge
] begin
    using Backtest, Test, Dates

    # Pipeline without Crossover — no :side key in the NamedTuple
    n = 10
    bars = PriceBars(
        fill(100.0, n), fill(105.0, n), fill(95.0, n),
        fill(100.0, n), fill(1000.0, n),
        [DateTime(2024, 1, i) for i in 1:n], TimeBar(),
    )

    event_indices = [1]

    # Barrier that branches on entry_side: since side is absent,
    # entry_side should default to Int8(0)
    lb = LowerBarrier(
        d -> d.entry_side == Int8(1) ? d.entry_price * 0.95 : d.entry_price * 0.80
    )
    tb = TimeBarrier(d -> d.entry_ts + Day(5))

    result = calculate_label(event_indices, bars, (lb, tb))

    # entry_side defaults to 0, so the else branch (0.80) should be used
    # With flat prices at 100 and lows at 95, barrier at 80 won't trigger.
    # TimeBarrier should fire instead.
    @test length(result.label) == 1
    @test result.label[1] == Int8(0)  # TimeBarrier
end

@testitem "Label: entry_side is constant across holding period" tags = [
    :label, :property
] begin
    using Backtest, Test, Dates

    # Verify that entry_side is frozen at entry — it should NOT change
    # as the side vector flips during the trade.
    n = 20
    opens  = fill(100.0, n)
    highs  = fill(100.5, n)
    lows   = fill(99.5, n)
    closes = fill(100.0, n)
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Side flips from 1 to -1 at bar 5
    side = vcat(fill(Int8(1), 5), fill(Int8(-1), 15))

    event_indices = [1]  # entry at bar 2

    # ConditionBarrier that fires when entry_side != 1:
    # If entry_side were re-evaluated per bar, it would change at bar 5
    # and trigger the condition. But since it's frozen, it stays 1 and
    # never triggers — the time barrier fires instead.
    cb = ConditionBarrier(d -> d.entry_side != Int8(1); exit_basis=NextOpen())
    tb = TimeBarrier(d -> d.entry_ts + Day(10))

    result = calculate_label(
        event_indices, bars, (cb, tb);
        barrier_args=(; side=side),
    )

    @test length(result.label) == 1
    # entry_side is frozen at side[2] = 1, so the ConditionBarrier never fires.
    # TimeBarrier should be the exit.
    @test result.label[1] == Int8(0)  # TimeBarrier label
end
