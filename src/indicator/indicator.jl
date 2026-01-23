abstract type Indicator end

struct EMA <: Indicator
    period::Int
    EMA(period) = new(_natural(period))
end

struct CUSUM{T<:AbstractFloat} <: Indicator
    multiplier::T
    span::Int
    expected_value::T

    CUSUM{T}(m, s, e) where {T} = new{T}(T(m), Int(s), T(e))
end

function CUSUM(multiplier::Real; span=100, expected_value=0.0)
    m_val = _positive_float(multiplier)
    s_val = _natural(span)
    T = typeof(float(m_val))
    return CUSUM{T}(m_val, s_val, expected_value)
end

function calculate_indicators(prices::AbstractVector{T}, ema::EMA) where {T<:AbstractFloat}
    return _calculate_ema(prices, ema.period)
end

function calculate_indicators(
    prices::AbstractVector{T}, indicators::EMA...
) where {T<:AbstractFloat}
    periods = Int[ind.period for ind in indicators]
    results = _calculate_emas(prices, periods)
    names = Tuple(Symbol("ema_", ind.period) for ind in indicators)
    return NamedTuple{names}(Tuple(results))
end

function calculate_indicators(
    prices::AbstractVector{T}, indicator::CUSUM
) where {T<:AbstractFloat}
    return _calculate_cusum(prices, indicator)
end