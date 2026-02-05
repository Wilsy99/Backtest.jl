using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools, DataFrames, DataFramesMeta, Chain

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

#! format: off
bars |>
    EMA(10, 20) |>
    CUSUM(1) |>
    Crossover(:ema_10, :ema_20; direction=LongOnly) |>
    @Event(:cusum ≠ 0, :side ≠ 0)
    @Label(
        entry_basis=next_open, 
        exit_basis=next_open,
        entry_price * (1 - :adr_20),
        entry_price * 1.05,
        entry_date + 10,
        :ema_10
        )
#! format: on

inds = EMA(10, 20) >> CUSUM(1)
side = Crossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly)
event = @Event(:cusum .!= 0, :side .!= 0)

bars |> inds |> side |> event

test = bars >> inds >> side >> event

test()

@chain data begin
    @transform(
        :ema_10 = calculate_indicator(EMA(10), :close),
        :ema_20 = calculate_indicator(EMA(20), :close),
        :cusum = calculate_indicator(CUSUM(1), :close)
    )
    @transform(:side = calculate_side(Crossover(), :ema_10, :ema_20))
    @transform(:event = Int8.(:cusum .≠ 0 .&& :side .≠ 0))
end
