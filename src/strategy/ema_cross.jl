function _calculate_ema_cross_sides(
    prices::AbstractVector{T},
    fast_ema::EMA,
    slow_ema::EMA,
    wait_for_cross::Bool,
    ::Val{true},
    ::Val{false},
) where {T<:AbstractFloat}
    n_prices = length(prices)
    ema_values = _calculate_emas(prices, [fast_ema.period, slow_ema.period])
    fast_vals, slow_vals = view(ema_values, :, 1), view(ema_values, :, 2)
    sides = zeros(Int8, n_prices)

    start_idx = slow_ema.period
    if n_prices < start_idx
        return sides
    end

    cond = i -> fast_vals[i] > slow_vals[i]

    if !wait_for_cross
        _fill_sides_generic!(sides, start_idx, cond)
        return sides
    end

    first_cross = _find_first_long_cross(fast_vals, slow_vals, start_idx)

    if first_cross != -1
        _fill_sides_generic!(sides, first_cross, cond)
    end

    return sides
end

@inline function _find_first_long_cross(fast, slow, start_idx)
    n = length(fast)
    has_been_below = @inbounds fast[start_idx] < slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        f_val = fast[i]
        s_val = slow[i]
        if has_been_below && f_val > s_val
            return i
        elseif f_val <= s_val
            has_been_below = true
        end
    end
    return -1
end

function _calculate_ema_cross_signals(
    fast_ema_vals::AbstractVector{T},
    slow_ema_vals::AbstractVector{T},
    ::Val{true},
    ::Val{false},
) where {T<:AbstractFloat}
    n = length(fast_ema_vals)
    signals = Vector{Int8}(undef, n)
    @inbounds signals[1] = 0

    @inbounds @simd for i in 2:n
        cross_up =
            (fast_ema_vals[i] > slow_ema_vals[i]) &&
            (fast_ema_vals[i - 1] <= slow_ema_vals[i - 1])

        signals[i] = ifelse(cross_up, Int8(1), Int8(0))
    end

    return signals
end