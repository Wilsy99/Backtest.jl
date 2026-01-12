using Pkg
Pkg.activate(".")

using Backtest
data = get_data("SPY", "1900-01-01", "2025-01-11")