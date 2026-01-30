function (ind::AbstractIndicator)(bars::PriceBars)
    ind_tup = calculate_indicator(ind, bars.close)
    return merge((bars=bars,), ind_tup)
end

function (ind::AbstractIndicator)(d::NamedTuple)
    ind_tup = calculate_indicator(ind, d.bars.close)
    return merge(d, ind_tup)
end

@generated function calculate_indicator(
    ::EMA{Periods}, prices::AbstractVector{T}
) where {Periods,T<:AbstractFloat}
    if length(Periods) == 1
        p = Periods[1]
        name = (Symbol(:ema_, p),)
        quote
            ema_vals = calculate_ema(prices, $p)
            return NamedTuple{$name}((ema_vals,))
        end
    else
        names = Tuple(Symbol(:ema_, p) for p in Periods)
        n = length(Periods)
        quote
            ema_vals = calculate_emas(prices, collect($Periods))
            NamedTuple{$names}(NTuple{$n,Vector{$T}}(Tuple(eachcol(ema_vals))))
        end
    end
end

function calculate_indicator(ind::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat}
    mult = ind.multiplier
    span = ind.span
    exp_val = ind.expected_value

    cusum_vals = calculate_cusum(prices, mult, span, exp_val)

    name = :cusum

    return NamedTuple{(name,)}((cusum_vals,))
end