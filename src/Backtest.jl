module Backtest

using YFinance
using DataFrames
using DataFramesMeta
using Chain
using Dates
using Base.Threads

include("data.jl")
include("indicator.jl")

export get_data
export transform_to_weekly

end
