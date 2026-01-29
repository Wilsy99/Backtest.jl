abstract type AbstractBarType end
abstract type AbstractIndicator end
abstract type AbstractEvent end
abstract type AbstractSignal end
abstract type AbstractLabeler end

struct TimeBar <: AbstractBarType end
struct DollarBar <: AbstractBarType end

# Core data container
struct PriceBars{B<:AbstractBarType,T<:Real,V<:AbstractVector{T}}
    open::V
    high::V
    low::V
    close::V
    volume::V
    timestamp::Vector{DateTime}
    bartype::B
end

# Indicators
struct EMA <: AbstractIndicator
    period::Int
    EMA(period::Int) = new(_natural(period))
end

struct EMAs <: AbstractIndicator
    periods::Vector{Int}
    EMAs(periods::Vector{Int}) = new(map(_natural, periods))
end

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

# struct EMACross <: Indicator
#     fast::EMA
#     slow::EMA

#     function EMACross(f, s)
#         f_period = f.period
#         s_period = s.period
#         f_period < s_period || throw(
#             ArgumentError(
#                 "fast period must be < slow period, got fast period = $f_period & slow period = $s_period",
#             ),
#         )
#         return (f, s)
#     end
# end

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

# # Pipeline
# struct Pipeline{T<:Tuple}
#     steps::T
# end