using Pkg
Pkg.activate(".")

using Backtest, BenchmarkTools, DataFrames, DataFramesMeta, Chain

data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])

bars = PriceBars(
    data.open, data.high, data.low, data.close, data.volume, data.timestamp, TimeBar()
)

bars |> EMA(10, 20) |> CUSUM(1) |> EMACrossover(:ema_10, :ema_20; direction=LongOnly)

inds = EMA(10, 20) >> CUSUM(1)
side = EMACrossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly)

bars |> inds |> side

test = bars >> inds >> side

test()

@chain data begin
    @transform(
        :ema_10 = calculate_indicator(EMA(10), :close),
        :ema_20 = calculate_indicator(EMA(20), :close),
        :cusum = calculate_indicator(CUSUM(1), :close)
    )
    @transform(:side = calculate_side(EMACrossover(), :ema_10, :ema_20))
end

bars |>
EMA(10, 20) |>
CUSUM(1) |>
EMACrossover(:ema_10, :ema_20; wait_for_cross=false, direction=LongOnly)