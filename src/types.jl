abstract type AbstractBarType end
abstract type AbstractIndicator end
abstract type AbstractSide end
abstract type AbstractEvent end
abstract type AbstractLabeler end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

@enum Direction LongOnly ShortOnly LongShort

const PipelineObject = Union{AbstractIndicator,AbstractSide,AbstractEvent,AbstractLabeler}
const PipeOrFunc = Union{PipelineObject,Function}

struct Job{D,F}
    data::D
    pipeline::F
end

(j::Job)() = j.pipeline(j.data)

import Base: >>

>>(f::PipeOrFunc, g::PipeOrFunc) = g ∘ f
>>(data::Any, pipe::PipeOrFunc) = Job(data, pipe)
>>(j::Job, next_step::PipeOrFunc) = Job(j.data, next_step ∘ j.pipeline)

# Core data container
struct PriceBars{B<:AbstractBarType,T<:AbstractFloat,V<:AbstractVector{T}}
    open::V
    high::V
    low::V
    close::V
    volume::V
    timestamp::Vector{DateTime}
    bartype::B
end

# # Signals
# struct CrossSignal <: AbstractSignal end

# # Labelers
# struct TripleBarrier{T<:AbstractFloat} <: Label
#     take_profit::T
#     stop_loss::T
#     time_out::Int # Max bars to hold (Vertical Barrier)

#     function TripleBarrier{T}(tp, sl, to) where {T<:AbstractFloat}
#         return new{T}(_positive_float(T(tp)), _positive_float(T(sl)), _natural(Int(to)))
#     end
# end
