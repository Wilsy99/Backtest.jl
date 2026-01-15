module Backtest

using YFinance
using DataFrames
using DataFramesMeta
using Chain
using Dates
using Base.Threads

include("data.jl")
include("indicator/ema.jl")
include("indicator/indicator.jl")

export get_data
export transform_to_weekly
export Indicator
export EMA
export calculate_indicators!

end
