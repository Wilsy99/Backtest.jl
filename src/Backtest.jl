module Backtest

using DataFrames, DataFramesMeta, Chain
using YFinance
using Dates
using Base.Threads
using Combinatorics

include("types.jl")
include("utility.jl")
include("data.jl")
include("indicator/indicator.jl")
include("side/side.jl")

export PriceBars, TimeBar
export AbstractIndicator, EMA, CUSUM, calculate_indicator
export AbstractSide, EMACrossover, calculate_side

export get_data

end
