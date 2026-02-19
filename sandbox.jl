using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools, InteractiveUtils, Dates, DataFrames, DataFramesMeta, Chain

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
big_data = vcat(fill(data, 500)...)

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

big_bars =
    bars = PriceBars(
        big_data.open,
        big_data.high,
        big_data.low,
        big_data.close,
        big_data.volume,
        big_data.timestamp,
        TimeBar(),
    )

#! format: off
bars |>
    EMA(10, 20) |>
    CUSUM(1) |>
    Crossover(:ema_10, :ema_20; direction=LongOnly()) |>
    @Event(:cusum .!= 0, :side .!= 0) |> 
    Label!(
        @LowerBarrier(:entry_price * 0.95, label=Int8(-1), exit_basis=Immediate()),
        @UpperBarrier(:entry_price * 1.2, label=Int8(1), exit_basis=Immediate()),
        @LowerBarrier(:ema_20, label=Int8(-1), exit_basis=NextOpen()),
        @TimeBarrier(:entry_ts + Day(10), label=Int8(0), exit_basis=NextOpen()),
        @ConditionBarrier(:ema_10 < :ema_20 && :close <= :entry_price, label=Int8(-1), exit_basis=NextOpen()),
        @ConditionBarrier(:ema_10 < :ema_20 && :close > :entry_price, label=Int8(1), exit_basis=NextOpen());
        entry_basis=NextOpen()
        )
#! format: on


strat(bars::PriceBars) = 
#! format: off
    bars >>
    EMA(10, 20) >>
    CUSUM(1) >>
    Crossover(:ema_10, :ema_20; direction=LongOnly()) >>
    @Event(:cusum .!= 0, :side .!= 0) >> 
    Label!(
        @LowerBarrier(:entry_price * 0.95, label=Int8(-1), exit_basis=Immediate()),
        @UpperBarrier(:entry_price * 1.2, label=Int8(1), exit_basis=Immediate()),
        @LowerBarrier(:ema_20, label=Int8(-1), exit_basis=NextOpen()),
        @TimeBarrier(:entry_ts + Day(10), label=Int8(0), exit_basis=NextOpen()),
        @ConditionBarrier(:ema_10 < :ema_20 && :close <= :entry_price, label=Int8(-1), exit_basis=NextOpen()),
        @ConditionBarrier(:ema_10 < :ema_20 && :close > :entry_price, label=Int8(1), exit_basis=NextOpen());
        entry_basis=NextOpen()
        )
#! format: on

@time strat(bars)()

@time strat(big_bars)()

@benchmark $strat(big_bars)()

feats = EMA(10, 20) >> CUSUM(1)
side = Crossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly())
event = Event(d -> d.cusum .!= 0 .&& d.side .!= 0)
label = Label(
    ConditionBarrier(a -> a.ema_10[a.idx] < a.ema_20[a.idx], Int8(-1), NextOpen()),
    LowerBarrier(a -> a.ema_20[a.idx], Int8(-1), NextOpen()),
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
        :ema_10 = calculate_feature(EMA(10), :close),
        :ema_20 = calculate_feature(EMA(20), :close),
        :cusum = calculate_feature(CUSUM(1), :close)
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
            LowerBarrier(a -> a.ema_20[a.idx], Int8(-1), NextOpen()),
            UpperBarrier(a -> a.entry_price * 1.2, Int8(1), Immediate()),
            TimeBarrier(a -> a.entry_ts + Day(10), Int8(0), NextOpen()),
        );
        entry_basis=NextOpen(),
        barrier_args=(; ema_20=_.ema_20),
    )
end

@allocations bars |> EMA(5,10,15,20,3,4,6,1)