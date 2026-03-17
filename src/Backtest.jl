module Backtest

using DataFrames, DataFramesMeta, Chain
using YFinance
using Dates
using Base.Threads

include("types.jl")
include("utility.jl")
include("data.jl")
include("feature/feature.jl")
include("side/side.jl")
include("event.jl")
include("label/label.jl")

export PriceBars, TimeBar
export AbstractFeature, EMA, CUSUM, Features, compute, compute!
export AbstractDirection, LongOnly, ShortOnly, LongShort
export AbstractSide, Crossover, compute_side
export AbstractEvent, Event, @Event, compute_event
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
export AbstractLabel, Label, Label!, compute_label
export AbstractWeights, AttributionWeights, compute_weights

export get_data

end