module Backtest

using YFinance
using DataFrames, DataFramesMeta
using Chain
using Dates
using Base.Threads

include("data.jl")
include("indicator/indicator.jl")
include("indicator/ema.jl")

export Timeframe, Daily, Weekly
export get_data, transform_to_weekly

export Indicator, EMA
export calculate_indicators!

end
