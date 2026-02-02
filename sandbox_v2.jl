using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

bars |>
EMA(10, 20) |>
CUSUM(1) |>
EMACrossover(:ema_10, :ema_20; wait_for_cross=false, direction=:long_only)

inds = EMA(10, 20) >> CUSUM(1)
side = EMACrossover(:ema_10, :ema_20; wait_for_cross=false, direction=:long_only)

bars |> inds |> side

test = bars >> inds >> side

results = test()
