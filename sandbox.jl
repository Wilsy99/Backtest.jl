using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain, BenchmarkTools

daily_data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
weekly_data = get_data("SPY"; timeframe=Weekly())

big_data = reduce(
    vcat, repeat([get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])], 500)
)

@chain big_data begin
    @groupby(:ticker)
    @transform(
        $AsTable = calculate_indicators(:close, EMA(10), EMA(20)),
        :cusum = calculate_indicators(:close, CUSUM(1)),
    )
end

@btime @chain $big_data begin
    @select(:ticker, :timestamp, :close)
    @groupby(:ticker)
    @transform(
        :cusum = calculate_indicators(:close, CUSUM(1)),
        :side = calculate_strategy_sides(:close, EMACross(EMA(5), EMA(20); long=true))
    )
    @subset!(:cusum .== 1)
end