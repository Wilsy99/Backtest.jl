using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain

daily_data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
weekly_data = get_data("SPY"; timeframe=Weekly())

big_data = reduce(vcat, repeat([daily_data], 500))
@chain big_data begin
    @groupby(:ticker)
    @transform(
        $AsTable = calculate_indicators(:close, EMA(10), EMA(20)),
        :cusum = calculate_indicators(:close, CUSUM(1)),
    )
end
