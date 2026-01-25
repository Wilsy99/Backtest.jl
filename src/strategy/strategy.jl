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

function calculate_strategy_sides(
    prices::AbstractVector{T}, strategy::EMACross{Long,Short}
) where {T<:AbstractFloat,Long,Short}
    return _calculate_ema_cross_sides(
        prices, strategy.fast_ema, strategy.slow_ema, Val(Long), Val(Short)
    )
end

@inline function _fill_sides_generic!(
    sides::AbstractVector{Int8}, from_idx::Int, condition::F
) where {F<:Function}
    @inbounds @simd for i in from_idx:length(sides)
        sides[i] = ifelse(condition(i), Int8(1), Int8(0))
    end
end