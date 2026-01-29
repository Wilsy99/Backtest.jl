function (indicator::AbstractIndicator)(bars::PriceBars)
    return merge((bars=bars,), _calculate(indicator, bars))
end

function (indicator::AbstractIndicator)(d::NamedTuple)
    return merge(d, _calculate(indicator, d.bars))
end

function _calculate(indicator::EMA, bars::PriceBars)
    val = calculate_ema(bars.close, indicator.period)
    name = Symbol("ema_", indicator.period)
    return NamedTuple{(name,)}((val,))
end

function _calculate(indicator::EMAs, bars::PriceBars)
    vals = calculate_emas(bars.close, indicator.periods)
    names = Tuple(Symbol("ema_", p) for p in indicator.periods)
    return NamedTuple{names}(Tuple(eachcol(vals)))
end

function _calculate(indicator::CUSUM, bars::PriceBars)
    val = calculate_cusum(
        bars.close, indicator.multiplier, indicator.span, indicator.expected_value
    )
    name = :cusum
    return NamedTuple{(name,)}((val,))
end

# function calculate_indicators(
#     prices::AbstractVector{T}, indicators::EMA
# ) where {T<:AbstractFloat}
#     n = length(prices)

#     results = Vector{T}(undef, n)

#     _single_ema!(results, prices, indicators.period, n)

#     return results
# end

# function calculate_indicators(
#     prices::AbstractVector{T}, indicators::EMA...
# ) where {T<:AbstractFloat}
#     periods = Int[ind.period for ind in indicators]

#     results = _calculate_emas(prices, periods)

#     names = Tuple(Symbol("ema_", ind.period) for ind in indicators)

#     return NamedTuple{names}(Tuple(eachcol(results)))
# end

# function calculate_indicators(
#     prices::AbstractVector{T}, indicator::CUSUM
# ) where {T<:AbstractFloat}
#     return _calculate_cusum(prices, indicator)
# end