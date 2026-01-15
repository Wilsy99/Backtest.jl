using Pkg
Pkg.activate(".")

using Backtest, DataFrames, Chain

daily_data = get_data("SPY")
weekly_data = get_data("SPY"; timeframe=Weekly())

@chain daily_data begin
    calculate_indicators!(ntuple(i -> EMA(i), 200)...)
end
