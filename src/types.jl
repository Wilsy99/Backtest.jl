abstract type AbstractBarType end
abstract type AbstractFeature end
abstract type AbstractSide end
abstract type AbstractDirection end
"""
    AbstractEvent

Supertype for all event detectors in the pipeline.

An event detector identifies bar indices where one or more conditions on price
data or computed features are satisfied. The result is a `Vector{Int}` of
matching indices that downstream labelling stages consume.

# Interface

Subtypes must implement the callable interface:

- `(e::MyEvent)(bars::PriceBars) -> NamedTuple`: evaluate the event on raw
    price data. Return a `NamedTuple` with at least `bars::PriceBars` and
    `event_indices::Vector{Int}`.
- `(e::MyEvent)(d::NamedTuple) -> NamedTuple`: evaluate the event on a
    pipeline `NamedTuple`. Return the input merged with
    `event_indices::Vector{Int}`.

# Existing Subtypes

- [`Event`](@ref): evaluates boolean condition functions with AND/OR logic.

# See also
- [`Event`](@ref): the standard event detector.
- [`@Event`](@ref): DSL macro for constructing `Event` instances.
"""
abstract type AbstractEvent end
abstract type AbstractBarrier end
abstract type AbstractLabel end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

struct LongOnly <: AbstractDirection end
struct ShortOnly <: AbstractDirection end
struct LongShort <: AbstractDirection end

const PipelineObject = Union{AbstractFeature,AbstractSide,AbstractEvent,AbstractLabel}
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