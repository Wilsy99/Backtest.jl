using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain, BenchmarkTools

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

CUSUM(1)(EMAs([10, 20])(bars))

EMA(10)(bars)