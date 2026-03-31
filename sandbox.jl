using Pkg
Pkg.activate(".")

using Backtest,
    BenchmarkTools, InteractiveUtils, Dates, DataFrames, DataFramesMeta, MLJ, Chain

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
big_data = vcat(fill(data, 500)...)

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

big_bars = PriceBars(
    big_data.open,
    big_data.high,
    big_data.low,
    big_data.close,
    big_data.volume,
    big_data.timestamp,
    TimeBar(),
)

compute(EMA(10; field=:volume), bars)
compute(EMA(10), bars.volume)

EMA(20; field=:open)(bars)
EMA(20)(bars.open)
#! format: off
bars |> 
    Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1)) |>
    Crossover(:ema_10, :ema_20; direction=LongShort()) |> 
    Event((d, i) -> d.side[i] == 1 && d.features.cusum[i] == 1)
#! format: on

range(highs, lows) = highs .- lows

#! format: off
bars |> 
    @Features(ema_10 = EMA(10), cusum = CUSUM(1)) |> 
    @Features(:ema_20 .= EMA(20), range => range(data.high, data.low))

bars |> 
    Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1)) |> 
    Side(
        Long((d, i) -> d.features.ema_10[i] > d.features.ema_20[i]),
        Short((d, i) -> d.features.ema_10[i] < d.features.ema_20[i])
        ) |> 
    Event((d, i) -> d.features.cusum[i] .!= 0 .&& d.side[i] .!= 0)

@time bars |> 
    @Features(ema_10 = EMA(10), ema_20 = EMA(20), cusum = CUSUM(1)) |> 
    Side(
        @Long(ema_10 > ema_20 && close > lag(open, 10)), 
        @Short(ema_20 < ema_10)
        ) |> 
    @Event(cusum != 0 && side != 0) |> 
    Label(
        @LowerBarrier(
            entry_side == 1 ? entry_price * 0.95 : entry_price * 0.90,
            label = Int8(-1),
            exit_basis = Immediate()
        ),
        @UpperBarrier(
            entry_side == 1 ? entry_price * 1.2 : entry_price * 1.1,
            label = Int8(1),
            exit_basis = Immediate()
        ),
        @TimeBarrier(:entry_ts + Day(10), label = Int8(0), exit_basis = NextOpen())
        )
#! format: on

#! format: off
@time bars |>
    Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1)) |>
    Crossover(:ema_10, :ema_20; direction=LongShort()) |>
    @Event(:cusum .!= 0 && :side .!= 0) |>
    Label!(
        @LowerBarrier(
            :entry_side == 1 ? :entry_price * 0.95 : :entry_price * 0.90,
            label = Int8(-1),
            exit_basis = Immediate()
        ),
        @UpperBarrier(
            :entry_side == 1 ? :entry_price * 1.2 : :entry_price * 1.1,
            label = Int8(1),
            exit_basis = Immediate()
        ),
        @TimeBarrier(:entry_ts + Day(10), label = Int8(0), exit_basis = NextOpen()),
        @ConditionBarrier(
            if :entry_side == 1
                (:ema_10 < :ema_20 && :close <= :entry_price)
            else
                (:ema_10 > :ema_20 && :close < :entry_price)
            end,
            label = Int8(-1),
            exit_basis = NextOpen()
        ), #long postion; if ema_10 crosses below ema_20, then exit trade, if trade closes in loss (close < entry price) then label as 1, the opposite for short
        @ConditionBarrier(
            if :entry_side == 1
                (:ema_10 < :ema_20 && :close > :entry_price)
            else
                (:ema_10 > :ema_20 && :close >= :entry_price)
            end,
            label = Int8(1),
            exit_basis = NextOpen()
        );
        entry_basis=NextOpen(),
    )
#! format: on

function strat(bars::PriceBars, multi_thread)
    #! format: off
    return bars >> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1)) >>
           Crossover(:ema_10, :ema_20; direction=LongOnly()) >>
           @Event(:cusum .!= 0, :side .!= 0) >> Label!(
        @LowerBarrier(:entry_price * 0.95, label = Int8(-1), exit_basis = Immediate()),
        @UpperBarrier(:entry_price * 1.2, label = Int8(1), exit_basis = Immediate()),
        @LowerBarrier(:ema_20, label = Int8(-1), exit_basis = NextOpen()),
        @TimeBarrier(:entry_ts + Day(10), label = Int8(0), exit_basis = NextOpen()),
        @ConditionBarrier(
            :ema_10 < :ema_20 && :close <= :entry_price,
            label = Int8(-1),
            exit_basis = NextOpen()
        ),
        @ConditionBarrier(
            :ema_10 < :ema_20 && :close > :entry_price,
            label = Int8(1),
            exit_basis = NextOpen()
        );
        entry_basis=NextOpen(),
        multi_thread=multi_thread,
    )
end
#! format: on

@time strat(bars, false)()
@benchmark $strat(bars, false)()

@time strat(big_bars, true)()

@benchmark $strat(big_bars, false)()

feats = Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1))
side = Crossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly())
event = Event(d -> d.features.cusum .!= 0 .&& d.side .!= 0)
label = Label(
    ConditionBarrier(
        a -> a.features.ema_10[a.idx] < a.features.ema_20[a.idx], Int8(-1), NextOpen()
    ),
    LowerBarrier(a -> a.features.ema_20[a.idx], Int8(-1), NextOpen()),
    UpperBarrier(a -> a.entry_price * 1.2, Int8(1), NextOpen()),
    TimeBarrier(a -> a.entry_ts + Day(10), Int8(0), NextOpen());
    entry_basis=NextOpen(),
)

bars |> feats |> side |> event |> label

benchmark_strat = big_bars >> feats >> side >> event >> label

@btime $benchmark_strat()
@code_warntype benchmark_strat()

@chain data begin
    @transform(
        :ema_10 = compute(EMA(10), :close),
        :ema_20 = compute(EMA(20), :close),
        :cusum = compute(CUSUM(1), :close)
    )
    @transform(:side = calculate_side(Crossover(), :ema_10, :ema_20))
    @transform(:event = Int8.(:cusum .≠ 0 .&& :side .≠ 0))
    calculate_label(
        findall(_.event .!= 0),
        _.timestamp,
        _.open,
        _.high,
        _.low,
        _.close,
        _.volume,
        (
            LowerBarrier(a -> a.features.ema_20[a.idx], Int8(-1), NextOpen()),
            UpperBarrier(a -> a.entry_price * 1.2, Int8(1), Immediate()),
            TimeBarrier(a -> a.entry_ts + Day(10), Int8(0), NextOpen()),
        );
        entry_basis=NextOpen(),
        barrier_args=(; features=(ema_20=_.ema_20,)),
    )
end

@allocations bars |> Features(:ema_5 => EMA(5))

# ── Fully Standalone Approach (no pipeline, no functors) ──

# 1. Features — raw vectors in, raw vectors out
ema_10 = compute(EMA(10), data.close)
ema_20 = compute(EMA(20), data.close)
cusum = compute(CUSUM(1), data.close)

# 2. Side — raw vectors in, Vector{Int8} out
sides = calculate_side(Crossover(), ema_10, ema_20)

# 3. Event — standalone calculation using calculate_event
#    Conditions reference pipeline data, so we build a minimal NamedTuple
evt = Event(d -> d.features.cusum .!= 0 .&& d.side .!= 0)
event_indices = calculate_event(evt, (bars=bars, features=(cusum=cusum,), side=sides))

# 4. Label — raw vectors + barriers in, LabelResults out
results = calculate_label(
    event_indices,
    data.timestamp,
    data.open,
    data.high,
    data.low,
    data.close,
    data.volume,
    (
        LowerBarrier(a -> a.entry_price * 0.95, Int8(-1), Immediate()),
        UpperBarrier(a -> a.entry_price * 1.2, Int8(1), Immediate()),
        LowerBarrier(a -> a.features.ema_20[a.idx], Int8(-1), NextOpen()),
        TimeBarrier(a -> a.entry_ts + Day(10), Int8(0), NextOpen()),
    );
    side=sides,
    entry_basis=NextOpen(),
    barrier_args=(; features=(ema_20=ema_20,)),
)
