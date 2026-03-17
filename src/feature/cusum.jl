struct CUSUM{T<:AbstractFloat} <: AbstractFeature
    multiplier::T
    span::Int
    expected_value::T
    field::Symbol

    function CUSUM{T}(m, s, e, f) where {T<:AbstractFloat}
        return new{T}(_positive_float(T(m)), _natural(Int(s)), T(e), f)
    end
end

function CUSUM(multiplier::Real; span=100, expected_value=0.0, field::Symbol=:close)
    T = typeof(float(multiplier))
    return CUSUM{T}(multiplier, span, expected_value, field)
end

function compute(feat::CUSUM, d::NamedTuple)
    return compute(feat, d.bars)
end

function compute(feat::CUSUM, bars::PriceBars)
    return compute(feat, getproperty(bars, feat.field))
end

function compute(feat::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat}
    return _calculate_cusum(prices, feat.multiplier, feat.span, feat.expected_value)
end

function compute!(
    dest::AbstractVector{Int8}, feat::CUSUM, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(prices) ||
        throw(DimensionMismatch("dest length $(length(dest)) != prices length $(length(prices))"))
    fill!(dest, Int8(0))
    n = length(prices)
    warmup_idx = feat.span + 1
    if n <= warmup_idx
        return dest
    end
    _calculate_cusum!(dest, prices, feat.multiplier, feat.span, feat.expected_value)
    return dest
end

function _calculate_cusum(
    prices::AbstractVector{T}, multiplier::T, span::Int, expected_value::T
) where {T<:AbstractFloat}
    n = length(prices)
    warmup_idx = span + 1
    if n <= warmup_idx
        return _warn_and_return_zeros(n, warmup_idx)
    end
    cusum_values = zeros(Int8, n)
    _calculate_cusum!(cusum_values, prices, multiplier, span, expected_value)
    return cusum_values
end

function _calculate_cusum!(
    dest::AbstractVector{Int8}, prices::AbstractVector{T},
    multiplier::T, span::Int, expected_value::T
) where {T<:AbstractFloat}
    n = length(prices)
    warmup_idx = span + 1

    α = T(2.0) / (T(span) + one(T))
    β = one(T) - α
    expected = expected_value
    mult = multiplier

    sum_sq_ret = zero(T)
    prev_log = log(prices[1])

    @fastmath @inbounds for k in 2:warmup_idx
        curr_log = log(prices[k])
        sum_sq_ret += (curr_log - prev_log)^2
        prev_log = curr_log
    end

    ema_sq_mean = sum_sq_ret / T(warmup_idx - 1)
    s_pos = zero(T)
    s_neg = zero(T)

    @fastmath @inbounds for i in (warmup_idx + 1):n
        curr_log = log(prices[i])
        log_return = curr_log - prev_log
        prev_log = curr_log

        threshold = sqrt(max(T(1e-16), ema_sq_mean)) * mult

        s_pos = max(zero(T), s_pos + log_return - expected)
        s_neg = min(zero(T), s_neg + log_return + expected)

        if s_pos > threshold
            dest[i] = 1
            s_pos = zero(T)
        elseif s_neg < -threshold
            dest[i] = -1
            s_neg = zero(T)
        end

        ema_sq_mean = α * log_return^2 + β * ema_sq_mean
    end

    return nothing
end

@noinline function _warn_and_return_zeros(n, warmup_idx)
    @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
    return zeros(Int8, n)
end

(cusum::CUSUM)(data) = compute(cusum, data)
