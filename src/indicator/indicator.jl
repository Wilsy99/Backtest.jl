abstract type Indicator end

struct EMA <: Indicator
    period::Int
    EMA(period) = new(_natural(period))
end

struct CUSUM{T<:AbstractFloat} <: Indicator
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

function calculate_indicators(
    prices::AbstractVector{T}, indicators::EMA
) where {T<:AbstractFloat}
    n = length(prices)

    results = Vector{T}(undef, n)

    _single_ema!(results, prices, indicators.period, n)

    return results
end

function calculate_indicators(
    prices::AbstractVector{T}, indicators::EMA...
) where {T<:AbstractFloat}
    periods = Int[ind.period for ind in indicators]

    results = _calculate_emas(prices, periods)

    names = Tuple(Symbol("ema_", ind.period) for ind in indicators)

    return NamedTuple{names}(Tuple(eachcol(results)))
end

function calculate_indicators(
    prices::AbstractVector{T}, indicator::CUSUM
) where {T<:AbstractFloat}
    return _calculate_cusum(prices, indicator)
end