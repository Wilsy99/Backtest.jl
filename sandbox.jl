using Pkg
Pkg.activate(".")

using Backtest

daily_data = get_data("SPY")

weekly_data = get_data("SPY"; timeframe="W")

calculate_indicators!(daily_data, ntuple(i -> EMA(i), 200)...)