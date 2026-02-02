using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

bars |> EMA(10, 20) |> CUSUM(1)

inds = EMA(10, 20) >> CUSUM(1)

bars |> inds |> EMA(5)

test = bars >> inds

test()