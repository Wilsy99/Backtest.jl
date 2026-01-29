function calculate_cusum(
    prices::AbstractVector{T}, multiplier::T, span::Int, expected_value::T
) where {T<:AbstractFloat}
    n = length(prices)
    cusum_values = zeros(Int8, n)

    warmup_idx = 101
    if n <= warmup_idx
        @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
        return cusum_values
    end

    α = T(2.0) / (T(span) + one(T))
    β = one(T) - α
    expected = expected_value
    mult = multiplier

    sum_sq_ret = zero(T)
    prev_log = log(prices[1])

    @inbounds for k in 2:warmup_idx
        curr_log = log(prices[k])
        sum_sq_ret += (curr_log - prev_log)^2
        prev_log = curr_log
    end

    ema_sq_mean = sum_sq_ret / T(warmup_idx - 1)
    s_pos = zero(T)
    s_neg = zero(T)

    @inbounds for i in (warmup_idx + 1):n
        curr_log = log(prices[i])
        log_return = curr_log - prev_log
        prev_log = curr_log

        threshold = sqrt(max(T(1e-16), ema_sq_mean)) * mult

        s_pos = max(zero(T), s_pos + log_return - expected)
        s_neg = min(zero(T), s_neg + log_return + expected)

        ema_sq_mean = α * log_return^2 + β * ema_sq_mean

        if s_pos > threshold
            cusum_values[i] = 1
            s_pos = zero(T)
        elseif s_neg < -threshold
            cusum_values[i] = -1
            s_neg = zero(T)
        end
    end

    return cusum_values
end