function _calculate_cusum!(prices::Vector{Float64}, indicator::CUSUM)
    n = length(prices)
    cusum_values = zeros(Int8, n)

    # 1. Define Warmup Window (e.g., first 100 returns)
    # We need at least 100 bars for stats, plus 1 for the first return.
    warmup_idx = 101
    if n <= warmup_idx
        @warn "Data length ($n) is less than recommended warmup ($warmup_idx). 
               CUSUM triggers are unreliable and set all values to zero."
        return cusum_values
    end

    log_prices = log.(prices)

    α = 2.0 / (indicator.span + 1.0)
    β = 1.0 - α

    # 2. Warmup: Calculate Variance on indices 2 to 101
    sum_sq_ret = 0.0
    @inbounds for k in 2:warmup_idx
        sum_sq_ret += (log_prices[k] - log_prices[k - 1])^2
    end

    ema_sq_mean = sum_sq_ret / (warmup_idx - 1)

    s_pos = 0.0
    s_neg = 0.0

    @inbounds for i in (warmup_idx + 1):n
        log_return = log_prices[i] - log_prices[i - 1]

        volatility = sqrt(max(1e-16, ema_sq_mean))
        threshold = volatility * indicator.multiplier

        s_pos = max(0.0, s_pos + log_return - indicator.expected_value)
        s_neg = min(0.0, s_neg + log_return + indicator.expected_value)

        ema_sq_mean = (α * log_return^2) + (β * ema_sq_mean)

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