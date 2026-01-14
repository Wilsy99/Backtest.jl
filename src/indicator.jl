struct EMA
    period::Int
end

function calculate_ema!(df::DataFrame, indicators::EMA...)
    closes = df.close isa Vector{Float64} ? df.close : Float64.(df.close)
    n_rows = length(closes)
    n_inds = length(indicators)
    results = Vector{Vector{Float64}}(undef, n_inds)

    @threads for j in 1:n_inds
        p = indicators[j].period

        if p > n_rows
            results[j] = fill(NaN, n_rows)
            continue
        end
        ema_vec = Vector{Float64}(undef, n_rows)
        results[j] = ema_vec

        fill!(view(ema_vec, 1:(p - 1)), NaN)
        ema_vec[p] = _calculate_sma_seed(closes, p)

        alpha = 2.0 / (p + 1)
        decay = 1.0 - alpha
        _ema_engine_unrolled!(ema_vec, closes, p, n_rows, alpha, decay)
    end

    for (j, ind) in enumerate(indicators)
        df[!, "ema_$(ind.period)"] = results[j]
    end
    return df
end

@inline function _calculate_sma_seed(closes, p)
    s = 0.0
    @inbounds @simd for i in 1:p
        s += closes[i]
    end
    return s / p
end

@inline function _ema_engine_unrolled!(ema_vec, closes, p, n_rows, alpha, decay)
    decay2 = decay * decay
    decay3 = decay2 * decay
    decay4 = decay3 * decay

    c0, c1, c2, c3 = alpha, alpha * decay, alpha * decay2, alpha * decay3

    @inbounds prev = ema_vec[p]
    i = p + 1

    @inbounds while i <= n_rows - 3
        p1, p2, p3, p4 = closes[i], closes[i + 1], closes[i + 2], closes[i + 3]

        term1 = (p1 * c0)
        term2 = (p2 * c0) + (p1 * c1)
        term3 = (p3 * c0) + (p2 * c1) + (p1 * c2)
        term4 = (p4 * c0) + (p3 * c1) + (p2 * c2) + (p1 * c3)

        ema_vec[i] = term1 + (prev * decay)
        ema_vec[i + 1] = term2 + (prev * decay2)
        ema_vec[i + 2] = term3 + (prev * decay3)
        ema_vec[i + 3] = term4 + (prev * decay4)

        prev = ema_vec[i + 3]
        i += 4
    end

    @inbounds while i <= n_rows
        prev = (closes[i] * alpha) + (prev * decay)
        ema_vec[i] = prev
        i += 1
    end
end