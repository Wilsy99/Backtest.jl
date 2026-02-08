abstract type AbstractBarType end
abstract type AbstractIndicator end
abstract type AbstractSide end
abstract type AbstractDirection end
abstract type AbstractEvent end
abstract type AbstractBarrier end
abstract type AbstractLabel end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

struct LongOnly <: AbstractDirection end
struct ShortOnly <: AbstractDirection end
struct LongShort <: AbstractDirection end

const PipelineObject = Union{AbstractIndicator,AbstractSide,AbstractEvent,AbstractLabel}
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

Base.length(pb::PriceBars) = length(pb.close)