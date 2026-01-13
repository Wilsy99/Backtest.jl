abstract type Strategy end
struct EMACross <: Strategy
    fast_ema::Int
    slow_ema::Int
end

function calculate_indicators!(df::DataFrame, indicators::EMA...)
    closes = Float64.(df.close)
    n_rows = length(closes)

    smoothers = map(ind -> 2.0 / (ind.period + 1), indicators)
    results = map(_ -> zeros(Float64, n_rows), indicators)

    _calculate_ema_logic!(closes, results, smoothers)

    for (i, ind) in enumerate(indicators)
        df[!, "ema_$(ind.period)"] = results[i]
    end

    return df
end

function _calculate_ema_logic!(closes::Vector{Float64}, results::Tuple, smoothers::Tuple)
    n_rows = length(closes)
    n_indicators = length(results)

    @inbounds for i in 1:n_rows
        close = closes[i]
        for j in 1:n_indicators
            alpha = smoothers[j]

            if i == 1
                results[j][i] = close
            else
                results[j][i] = ema_kernel(close, results[j][i - 1], alpha)
            end
        end
    end
end

@inline function ema_kernel(x::Float64, prev::Float64, alpha::Float64)
    return (x * alpha) + (prev * (1.0 - alpha))
end
