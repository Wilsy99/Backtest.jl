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
- [`calculate_event`](@ref): standalone computation function.
- [`@Event`](@ref): DSL macro for constructing `Event` instances.
"""
abstract type AbstractEvent end
abstract type AbstractBarrier end
abstract type AbstractLabel end

"""
    AbstractWeights

Supertype for all sample-weight functors in the pipeline.

A weight functor takes a pipeline `NamedTuple` containing
[`LabelResults`](@ref) and [`PriceBars`](@ref), computes sample
weights via uniqueness-weighted attribution returns with optional
time decay and class-imbalance correction, and either merges
them into the pipeline or returns the raw vector.

# Interface

Subtypes must implement the callable interface:

- `(w::MyWeights)(d::NamedTuple) -> NamedTuple`: compute weights
    from `d.labels` and `d.bars`. Return the input merged with
    `(; weights=...)`.
- `(w::MyWeights)(labels::LabelResults, bars::PriceBars) -> Vector{T}`:
    compute and return the raw weight vector directly.

# Existing Subtypes

- [`AttributionWeights`](@ref): uniqueness-weighted attribution with
    time decay and class-imbalance correction.

# See also
- [`compute_weights`](@ref): the underlying computation function.
- [`LabelResults`](@ref): the input container for weight computation.
"""
abstract type AbstractWeights end
abstract type AbstractCrossValidation end
abstract type AbstractMetaLabeler end
abstract type AbstractBetSize end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

struct LongOnly <: AbstractDirection end
struct ShortOnly <: AbstractDirection end
struct LongShort <: AbstractDirection end

const PipelineObject = Union{AbstractFeature,AbstractSide,AbstractEvent,AbstractLabel,AbstractWeights}
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