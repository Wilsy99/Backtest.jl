using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools, Dates, DataFrames, DataFramesMeta, Chain

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
    Crossover(:ema_10, :ema_20; direction=LongOnly) |>
    @Event(:cusum ≠ 0, :side ≠ 0)
#! format: on

inds = EMA(10, 20) >> CUSUM(1)
side = Crossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly)
event = @Event(:cusum .!= 0, :side .!= 0)
label = Label(
    ConditionBarrier(a -> a.ema_10[a.idx] < a.ema_20[a.idx], Int8(-1), NextOpen()),
    LowerBarrier(a -> a.ema_20[a.idx], Int8(-1), NextOpen()),
    UpperBarrier(a -> a.entry_price * 1.2, Int8(1), NextOpen()),
    TimeBarrier(a -> a.entry_ts + Day(10), Int8(0), NextOpen());
    entry_basis=NextOpen(),
)

bars |> inds |> side |> event |> label

benchmark_strat = big_bars >> inds >> side >> event >> label

@btime $benchmark_strat()

@chain data begin
    @transform(
        :ema_10 = calculate_indicator(EMA(10), :close),
        :ema_20 = calculate_indicator(EMA(20), :close),
        :cusum = calculate_indicator(CUSUM(1), :close)
    )
    @transform(:side = calculate_side(Crossover(), :ema_10, :ema_20))
    @transform(:event = Int8.(:cusum .≠ 0 .&& :side .≠ 0))
end
