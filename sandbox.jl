using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain

daily_data = get_data("SPY")
weekly_data = get_data("SPY"; timeframe=Weekly())

@chain copy(daily_data) begin
    calculate_indicators!(ntuple(i -> EMA(i), 200)...)
end

@chain daily_data begin
    @subset(:high .< max.(:open, :close))
end
