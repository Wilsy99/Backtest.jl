using Pkg
Pkg.activate(".")

using Backtest

daily_data = get_data("SPY")

weekly_data = get_data("SPY"; timeframe="W")

calculate_ema!(daily_data, EMA(12), EMA(26))