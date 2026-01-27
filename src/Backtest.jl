module Backtest

using YFinance
using DataFrames, DataFramesMeta
using Chain
using Dates
using Base.Threads
using Combinatorics
using Logging

include("utility.jl")
include("data.jl")
include("indicator/indicator.jl")
include("indicator/ema.jl")
include("indicator/cusum.jl")
include("strategy/strategy.jl")
include("strategy/ema_cross.jl")
include("triple_barrier.jl")

export Timeframe, Daily, Weekly
export get_data, transform_to_weekly

export Indicator, EMA, CUSUM
export calculate_indicators

export Strategy, EMACross
export calculate_sides, calculate_signals

export Label, TripleBarrier
export calculate_labels

end
