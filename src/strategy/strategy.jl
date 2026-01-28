abstract type Strategy end

struct EMACross{Long,Short} <: Strategy
    fast_ema::EMA
    slow_ema::EMA

    function EMACross{L,S}(f, s) where {L,S}
        f_period = f.period
        s_period = s.period
        f_period < s_period || throw(
            ArgumentError(
                "fast_ema period must be < slow_ema period, got fast period = $f_period & slow period = $s_period",
            ),
        )
        return new{L::Bool,S::Bool}(f, s)
    end
end

function EMACross(fast, slow; long=true, short=false)
    return EMACross{long,short}(fast, slow)
end

function calculate_sides(
    strategy::EMACross{Long,Short}, prices::AbstractVector{T}; wait_for_cross::Bool=true
) where {T<:AbstractFloat,Long,Short}
    return _calculate_ema_cross_sides(
        prices, strategy.fast_ema, strategy.slow_ema, wait_for_cross, Val(Long), Val(Short)
    )
end

@inline function _fill_sides_generic!(
    sides::AbstractVector{Int8}, from_idx::Int, condition::F
) where {F<:Function}
    @inbounds @simd for i in from_idx:length(sides)
        sides[i] = ifelse(condition(i), Int8(1), Int8(0))
    end
end

function calculate_signals(sides::AbstractVector{T}) where {T<:Integer}
    n_sides = length(sides)

    if n_sides == 0
        return Int8[]
    elseif n_sides == 1
        return Int8[0]
    end

    signals = Vector{Int8}(undef, n_sides)

    @inbounds signals[1] = 0

    @inbounds @simd for i in 2:n_sides
        signals[i] = sides[i] - sides[i - 1]
    end

    return signals
end

function calculate_signals(
    strategy::EMACross{Long,Short},
    fast_ema_vals::AbstractVector{T},
    slow_ema_vals::AbstractVector{T},
) where {T<:AbstractFloat,Long,Short}
    return _calculate_ema_cross_signals(fast_ema_vals, slow_ema_vals, Val(Long), Val(Short))
end

function calculate_indicators(
    strategy::EMACross{Long,Short}, prices::AbstractVector{T}
) where {T<:AbstractFloat,Long,Short}
    return calculate_indicators(prices, strategy.fast_ema, strategy.slow_ema)
end