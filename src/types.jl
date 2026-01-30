abstract type AbstractBarType end
abstract type AbstractIndicator end
abstract type AbstractEvent end
abstract type AbstractSignal end
abstract type AbstractLabeler end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

const PipelineObject = Union{AbstractIndicator,AbstractEvent,AbstractSignal,AbstractLabeler}

import Base: >>
>>(f::PipelineObject, g::PipelineObject) = g ∘ f
>>(f::PipelineObject, g::Function) = g ∘ f
>>(f::Function, g::PipelineObject) = g ∘ f

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

struct EMA{Periods} <: AbstractIndicator
    function EMA{Periods}() where {Periods}
        foreach(_natural, Periods)
        return new{Periods}()
    end
end

EMA(p::Int) = EMA{(p,)}()
EMA(ps::Vararg{Int}) = EMA{ps}()

struct CUSUM{T<:AbstractFloat} <: AbstractIndicator
    multiplier::T
    span::Int
    expected_value::T

    function CUSUM{T}(m, s, e) where {T<:AbstractFloat}
        return new{T}(_positive_float(T(m)), _natural(Int(s)), T(e))
    end
end

function CUSUM(multiplier::Real; span=100, expected_value=0.0)
    T = typeof(float(multiplier))
    return CUSUM{T}(multiplier, span, expected_value)
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
