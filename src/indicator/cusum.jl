function calculate_cusum(
    prices::AbstractVector{<:AbstractFloat}, indicator::CUSUM
)::Vector{Int8}
    n = length(prices)
    cusum_values = zeros(Int8, n)

    warmup_idx = 101
    if n <= warmup_idx
        @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
        return cusum_values
    end

    α = 2.0 / (indicator.span + 1)
    β = 1.0 - α

    sum_sq_ret = 0.0
    prev_log = log(prices[1])
    @inbounds for k in 2:warmup_idx
        curr_log = log(prices[k])
        sum_sq_ret += (curr_log - prev_log)^2
        prev_log = curr_log
    end

    ema_sq_mean = sum_sq_ret / (warmup_idx - 1)
    expected = indicator.expected_value
    mult = indicator.multiplier

    s_pos = 0.0
    s_neg = 0.0

    @inbounds for i in (warmup_idx + 1):n
        curr_log = log(prices[i])
        log_return = curr_log - prev_log
        prev_log = curr_log

        threshold = sqrt(max(1e-16, ema_sq_mean)) * mult

        s_pos = max(0.0, s_pos + log_return - expected)
        s_neg = min(0.0, s_neg + log_return + expected)

        ema_sq_mean = α * log_return^2 + β * ema_sq_mean

        if s_pos > threshold
            cusum_values[i] = 1
            s_pos = 0.0
        elseif s_neg < -threshold
            cusum_values[i] = -1
            s_neg = 0.0
        end
    end

    return cusum_values
end