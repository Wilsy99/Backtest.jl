# ── Phase 2: Core Correctness — Reference Values ──

@testitem "Weights: Hand-calculated reference — two non-overlapping trades" tags = [
    :weights, :reference
] begin
    using Backtest, Test, Dates

    # 10 bars, two non-overlapping trades with known close prices.
    # Trade 1: entry=2, exit=4 (bars 2–4)
    # Trade 2: entry=6, exit=8 (bars 6–8)
    # No overlap → concurrency=1 for all active bars.
    n = 10
    closes = [100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0, 109.0]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Manually construct LabelResults for two trades
    trade_ranges = [2:4, 6:8]
    sides = Int8[0, 0]
    labels = Int8[0, 0]  # same class → no class rebalancing effect
    bins = Int8[0, 0]
    rets = [0.0, 0.0]
    log_rets = [0.0, 0.0]
    lr = Backtest.LabelResults(trade_ranges, sides, labels, bins, rets, log_rets)

    w = compute_weights(lr, bars)

    @test length(w) == 2

    # exposure_offset=0 (NextOpen default). Concurrency=1 for all bars.
    # Trade 1 (bars 2–4): attributed return = log(101/100) + log(102/101)
    #   + log(103/102) = log(103/100)
    # Trade 2 (bars 6–8): attributed return = log(105/104) + log(106/105)
    #   + log(107/106) = log(107/104)
    # Both same class → class correction is identity. Normalise: sum=2.
    raw1 = log(103 / 100)
    raw2 = log(107 / 104)
    total = raw1 + raw2
    norm = 2.0 / total

    @test w[1] ≈ raw1 * norm atol = 1e-12
    @test w[2] ≈ raw2 * norm atol = 1e-12
    @test sum(w) ≈ 2.0 atol = 1e-12
end

@testitem "Weights: Hand-calculated reference — overlapping trades" tags = [
    :weights, :reference
] begin
    using Backtest, Test, Dates

    # Two overlapping trades: trade 1 spans bars 2–5, trade 2 spans bars 4–7.
    # Overlap at bars 4–5 → concurrency=2 there.
    n = 10
    closes = Float64[100, 101, 102, 103, 104, 105, 106, 107, 108, 109]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    trade_ranges = [2:5, 4:7]
    sides = Int8[0, 0]
    labels = Int8[0, 0]
    bins = Int8[0, 0]
    rets = [0.0, 0.0]
    log_rets = [0.0, 0.0]
    lr = Backtest.LabelResults(trade_ranges, sides, labels, bins, rets, log_rets)

    w = compute_weights(lr, bars)

    # delta[2]+=1, delta[6]-=1 for trade 1
    # delta[4]+=1, delta[8]-=1 for trade 2
    # Sweep:
    #   t=1: concur=0, skip → cum[2]=0
    #   t=2: concur=1, log(101/100)/1 → cum[3]
    #   t=3: concur=1, log(102/101)/1 → cum[4]
    #   t=4: concur=2, log(103/102)/2 → cum[5]
    #   t=5: concur=2, log(104/103)/2 → cum[6]
    #   t=6: concur=1 (delta[6]=-1), log(105/104)/1 → cum[7]
    #   t=7: concur=1, log(106/105)/1 → cum[8]

    lr2 = log(101 / 100)
    lr3 = log(102 / 101)
    lr4 = log(103 / 102) / 2
    lr5 = log(104 / 103) / 2
    lr6 = log(105 / 104)
    lr7 = log(106 / 105)

    cum2 = 0.0
    cum3 = lr2
    cum4 = cum3 + lr3
    cum5 = cum4 + lr4
    cum6 = cum5 + lr5
    cum7 = cum6 + lr6
    cum8 = cum7 + lr7

    raw1 = abs(cum6 - cum2)   # trade 1: cum[exit+1=6] - cum[start=2]
    raw2 = abs(cum8 - cum4)   # trade 2: cum[exit+1=8] - cum[start=4]

    total = raw1 + raw2
    norm = 2.0 / total

    @test w[1] ≈ raw1 * norm atol = 1e-12
    @test w[2] ≈ raw2 * norm atol = 1e-12
    @test sum(w) ≈ 2.0 atol = 1e-12
end

@testitem "Weights: Hand-calculated reference — time decay" tags = [
    :weights, :reference
] begin
    using Backtest, Test, Dates

    # Two non-overlapping trades, time_decay_start=0.5.
    # Decay ramp: event 1 gets 0.5, event 2 gets 1.0.
    n = 10
    closes = Float64[100, 101, 102, 103, 104, 105, 106, 107, 108, 109]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    trade_ranges = [2:4, 6:8]
    sides = Int8[0, 0]
    labels = Int8[0, 0]
    bins = Int8[0, 0]
    rets = [0.0, 0.0]
    log_rets = [0.0, 0.0]
    lr = Backtest.LabelResults(trade_ranges, sides, labels, bins, rets, log_rets)

    w = compute_weights(lr, bars; time_decay_start=0.5)

    # Same cumulative attributed returns as the non-overlapping reference test
    raw1 = log(103 / 100)
    raw2 = log(107 / 104)

    # With time_decay_start=0.5 and 2 events:
    #   decay_incr = (1.0 - 0.5) / 1 = 0.5
    #   event 1: decay=0.5, weight = raw1 * 0.5
    #   event 2: decay=1.0, weight = raw2 * 1.0
    w1_raw = raw1 * 0.5
    w2_raw = raw2 * 1.0

    # Same class → class correction is identity
    total = w1_raw + w2_raw
    norm = 2.0 / total

    @test w[1] ≈ w1_raw * norm atol = 1e-12
    @test w[2] ≈ w2_raw * norm atol = 1e-12
    @test sum(w) ≈ 2.0 atol = 1e-12

    # Verify directionality: later event has higher weight with decay
    @test w[2] > w[1]
end

# ── Phase 2: Core Correctness — Type Stability ──

@testitem "Weights: Type stability — compute_weights" tags = [
    :weights, :stability
] begin
    using Backtest, Test, Dates

    n = 20
    closes64 = [100.0 + 0.5i for i in 1:n]
    closes32 = Float32.(closes64)
    opens  = closes64
    highs  = closes64 .+ 0.5
    lows   = closes64 .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars64 = PriceBars(opens, highs, lows, closes64, vols, ts, TimeBar())

    tb = TimeBarrier(d -> d.entry_ts + Day(3))
    labels = calculate_label([1, 5, 10], bars64, (tb,); side=zeros(Int8, n))

    @test @inferred(compute_weights(labels, bars64)) isa Vector{Float64}
    @test @inferred(compute_weights(labels, closes64)) isa Vector{Float64}
end

# ── Phase 2: Core Correctness — Property Tests ──

@testitem "Weights: Normalization — sum(weights) ≈ n_labels" tags = [
    :weights, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = merge(evt(bars), (; side=zeros(Int8, length(bars))))

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)
    weights = compute_weights(result, bars)

    n = length(weights)
    if n > 0
        @test sum(weights) ≈ n atol = 1e-6
        @test all(w >= 0 for w in weights)
    end
end

@testitem "Weights: Class imbalance correction — equal weight per class" tags = [
    :weights, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = merge(evt(bars), (; side=zeros(Int8, length(bars))))

    lab = Label!(
        UpperBarrier(d -> d.entry_price * 1.03),
        LowerBarrier(d -> d.entry_price * 0.97),
        TimeBarrier(d -> d.entry_ts + Day(30)),
    )

    result = lab(pipe_data)
    weights = compute_weights(result, bars)

    classes = unique(result.label)
    if length(classes) > 1
        class_weights = Dict{Int8,Float64}()
        for i in eachindex(result.label)
            c = result.label[i]
            class_weights[c] = get(class_weights, c, 0.0) + weights[i]
        end

        weights_per_class = collect(values(class_weights))
        @test maximum(weights_per_class) / minimum(weights_per_class) < 2.0
    end
end

@testitem "Weights: Time decay — later events get higher weight" tags = [
    :weights, :property
] begin
    using Backtest, Test, Dates

    n = 100
    opens  = [100.0 + 0.05 * i for i in 1:n]
    highs  = [101.0 + 0.05 * i for i in 1:n]
    lows   = [99.0 + 0.05 * i for i in 1:n]
    closes = [100.5 + 0.05 * i for i in 1:n]
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    event_indices = [1, 20, 40, 60]
    tb = TimeBarrier(d -> d.entry_ts + Day(5))
    result = calculate_label(event_indices, bars, (tb,); side=zeros(Int8, n))

    weights_decay = compute_weights(result, bars; time_decay_start=0.5)
    weights_no_decay = compute_weights(result, bars; time_decay_start=1.0)

    @test length(weights_decay) == length(weights_no_decay)

    if length(weights_decay) >= 2
        # With decay, the ratio between last and first weight should differ
        # from the no-decay case
        decay_ratio = weights_decay[end] / weights_decay[1]
        no_decay_ratio = weights_no_decay[end] / weights_no_decay[1]
        @test decay_ratio != no_decay_ratio
    end
end

@testitem "Weights: Overlapping trades — concurrency reduces attribution" tags = [
    :weights, :property
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

    event_indices = collect(1:5:30)
    tb = TimeBarrier(d -> d.entry_ts + Day(10))
    result = calculate_label(event_indices, bars, (tb,); side=zeros(Int8, n))

    @test length(result.label) > 0
    @test all(result.label .== Int8(0))
    weights = compute_weights(result, bars)
    @test sum(weights) ≈ length(weights) atol = 1e-6
end

# ── Phase 2: Core Correctness — Functor Tests ──

@testitem "Weights: Weights functor merges into NamedTuple" tags = [
    :weights, :unit
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))

    pipe = bars >> evt >>
        Label(
            UpperBarrier(d -> d.entry_price * 1.03),
            LowerBarrier(d -> d.entry_price * 0.97),
            TimeBarrier(d -> d.entry_ts + Day(30)),
        ) >>
        Weights()

    result = pipe()

    @test result isa NamedTuple
    @test haskey(result, :weights)
    @test haskey(result, :labels)
    @test haskey(result, :bars)
    @test result.weights isa Vector{Float64}
    @test length(result.weights) == length(result.labels)

    n = length(result.weights)
    if n > 0
        @test sum(result.weights) ≈ n atol = 1e-6
        @test all(w >= 0 for w in result.weights)
    end
end

@testitem "Weights: Weights! returns raw weight vector" tags = [
    :weights, :unit
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = (bars >> evt >>
        Label(
            UpperBarrier(d -> d.entry_price * 1.03),
            LowerBarrier(d -> d.entry_price * 0.97),
            TimeBarrier(d -> d.entry_ts + Day(30)),
        ))()

    weights = Weights!()(pipe_data)

    @test weights isa Vector{Float64}
    @test length(weights) == length(pipe_data.labels)
end

@testitem "Weights: time_decay_start kwarg propagates through functor" tags = [
    :weights, :unit
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)
    evt = Event(d -> trues(length(d.bars.close)))
    pipe_data = (bars >> evt >>
        Label(
            UpperBarrier(d -> d.entry_price * 1.03),
            LowerBarrier(d -> d.entry_price * 0.97),
            TimeBarrier(d -> d.entry_ts + Day(30)),
        ))()

    w_no_decay = Weights!()(pipe_data)
    w_decay = Weights!(time_decay_start=0.5)(pipe_data)

    @test length(w_no_decay) == length(w_decay)

    if length(w_decay) >= 2
        ratio_decay = w_decay[end] / w_decay[1]
        ratio_none = w_no_decay[end] / w_no_decay[1]
        @test ratio_decay != ratio_none
    end
end

@testitem "Weights: compute_weights(labels, bars) matches compute_weights(labels, bars.close)" tags = [
    :weights, :unit
] begin
    using Backtest, Test, Dates

    n = 30
    closes = [100.0 + 0.5i for i in 1:n]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    tb = TimeBarrier(d -> d.entry_ts + Day(5))
    labels = calculate_label([1, 10, 20], bars, (tb,); side=zeros(Int8, n))

    w_bars = compute_weights(labels, bars)
    w_closes = compute_weights(labels, bars.close)

    @test w_bars ≈ w_closes atol = 1e-15
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Weights: Empty labels → empty weight vector" tags = [:weights, :edge] begin
    using Backtest, Test, Dates

    n = 10
    closes = fill(100.0, n)
    bars = PriceBars(closes, closes .+ 1, closes .- 1, closes,
        fill(1000.0, n), [DateTime(2024, 1, i) for i in 1:n], TimeBar())

    # Empty LabelResults
    lr = Backtest.LabelResults(
        UnitRange{Int}[], Int8[], Int8[], Int8[], Float64[], Float64[],
    )

    w = compute_weights(lr, bars)
    @test length(w) == 0
    @test w isa Vector{Float64}
end

@testitem "Weights: Single label" tags = [:weights, :edge] begin
    using Backtest, Test, Dates

    n = 10
    closes = [100.0 + 1.0i for i in 1:n]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    lr = Backtest.LabelResults(
        [2:5], Int8[0], Int8[0], Int8[0], [0.0], [0.0],
    )

    w = compute_weights(lr, bars)
    @test length(w) == 1
    # Single label normalises to sum==1
    @test w[1] ≈ 1.0 atol = 1e-12
end

@testitem "Weights: All same class — no rebalancing distortion" tags = [
    :weights, :edge
] begin
    using Backtest, Test, Dates

    n = 20
    closes = [100.0 + 0.5i for i in 1:n]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Three trades, all with same label (class 0)
    lr = Backtest.LabelResults(
        [2:5, 7:10, 12:15],
        Int8[0, 0, 0], Int8[0, 0, 0], Int8[0, 0, 0],
        [0.0, 0.0, 0.0], [0.0, 0.0, 0.0],
    )

    w = compute_weights(lr, bars)
    @test length(w) == 3
    @test sum(w) ≈ 3.0 atol = 1e-6
    @test all(w .>= 0)
end

@testitem "Weights: Flat prices — zero attributed returns → uniform weights" tags = [
    :weights, :edge
] begin
    using Backtest, Test, Dates

    n = 20
    closes = fill(100.0, n)
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    # Three trades on flat prices: all log returns = 0
    lr = Backtest.LabelResults(
        [2:5, 7:10, 12:15],
        Int8[0, 0, 0], Int8[0, 0, 0], Int8[0, 0, 0],
        [0.0, 0.0, 0.0], [0.0, 0.0, 0.0],
    )

    w = compute_weights(lr, bars)
    @test length(w) == 3
    # When all attributed returns are zero, weights fall back to uniform
    @test all(w .≈ 1.0)
end

@testitem "Weights: time_decay_start=1.0 is identity (no decay)" tags = [
    :weights, :edge
] begin
    using Backtest, Test, Dates

    n = 20
    closes = [100.0 + 0.5i for i in 1:n]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    lr = Backtest.LabelResults(
        [2:4, 6:8, 10:12],
        Int8[0, 0, 0], Int8[0, 0, 0], Int8[0, 0, 0],
        [0.0, 0.0, 0.0], [0.0, 0.0, 0.0],
    )

    w1 = compute_weights(lr, bars; time_decay_start=1.0)
    w2 = compute_weights(lr, bars)  # default is 1.0

    @test w1 ≈ w2 atol = 1e-15
end

# ── Phase 3: Robustness — Allocation Budget Tests ──

@testitem "Weights: Allocation budget — compute_weights" tags = [
    :weights, :allocation
] begin
    using Backtest, Test, Dates

    n = 200
    closes = [100.0 + 0.05i for i in 1:n]
    opens  = closes
    highs  = closes .+ 0.5
    lows   = closes .- 0.5
    vols   = fill(1000.0, n)
    ts     = [DateTime(2024, 1, i) for i in 1:n]
    bars   = PriceBars(opens, highs, lows, closes, vols, ts, TimeBar())

    tb = TimeBarrier(d -> d.entry_ts + Day(5))
    labels = calculate_label(collect(1:10:100), bars, (tb,); side=zeros(Int8, n))

    # Warmup
    compute_weights(labels, bars)

    n_labels = length(labels)
    # Budget: result vector + internal arrays (concur_deltas, cum_attrib_rets,
    # entry/exit index vectors, class vectors) + overhead
    # Internal allocations: Vector{Int32}(n+2), Vector{T}(n+1),
    #   Vector{Int}(n_labels) x2, Vector{T}(n_labels),
    #   Vector{Int8} from unique(), Vector{T} for class arrays x2
    budget = sizeof(Float64) * n_labels +       # result vector
        sizeof(Int32) * (n + 2) +                # concur_deltas
        sizeof(Float64) * (n + 1) +              # cum_attrib_rets
        sizeof(Int) * n_labels * 2 +             # entry/exit indices
        4096                                     # overhead for containers, unique(), etc.

    allocs_fn(labels, bars) = @allocated compute_weights(labels, bars)
    actual = minimum([@allocated(allocs_fn(labels, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0  # must allocate result
end

# ── Phase 3: Robustness — Integration ──

@testitem "Weights: Full pipeline — Feature → Event → Label → Weights" tags = [
    :weights, :integration, :pipeline
] setup = [TestData] begin
    using Backtest, Test, Dates

    bars = TestData.make_pricebars(; n=200)

    pipe = bars >> EMA(10, 50) >> Crossover(:ema_10, :ema_50) >>
        Event(d -> d.bars.close .> d.bars.open) >>
        Label(
            UpperBarrier(d -> d.entry_price * 1.05),
            LowerBarrier(d -> d.entry_price * 0.95),
            TimeBarrier(d -> d.entry_ts + Day(20)),
        ) >>
        Weights(time_decay_start=0.75)

    result = pipe()

    @test result isa NamedTuple
    @test haskey(result, :weights)
    @test haskey(result, :labels)
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)

    n = length(result.weights)
    if n > 0
        @test sum(result.weights) ≈ n atol = 1e-6
        @test all(w >= 0 for w in result.weights)
        @test result.weights isa Vector{Float64}
    end
end
