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
include("event.jl")
include("label/label.jl")

export PriceBars, TimeBar
export AbstractIndicator, EMA, CUSUM, calculate_indicator
export AbstractDirection, LongOnly, ShortOnly, LongShort
export AbstractSide, Crossover, calculate_side
export AbstractEvent, Event, @Event
export AbstractExecutionBasis, CurrentOpen, CurrentClose, NextOpen, NextClose, Immediate
export AbstractBarrier,
    LowerBarrier,
    UpperBarrier,
    TimeBarrier,
    ConditionBarrier,
    @LowerBarrier,
    @UpperBarrier,
    @TimeBarrier,
    @ConditionBarrier
export AbstractLabel, Label, Label!, calculate_label

export get_data

end