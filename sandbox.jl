using Pkg
Pkg.activate(".")

using Backtest

daily_data = get_data("SPY")

weekly_data = get_data("SPY"; timeframe=Weekly())

calculate_indicators!(daily_data, ntuple(i -> EMA(i), 200)...)
calculate_indicators!(weekly_data, ntuple(i -> EMA(i), 50)...)