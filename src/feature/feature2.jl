# ── Features (replaces features.jl + feature.jl) ────────────────────────────

struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

function (feats::Features)(d::NamedTuple)
    feats_results = feats(d.bars)
    return merge(d, (features=feats_results,))
end

@generated function (feats::Features{T})(bars::PriceBars) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(feats.operations[$i](bars)) for i in 1:n]
    return :(merge($(exprs...)))
end

function (op::Pair{Symbol,<:AbstractFeature})(bars::PriceBars)
    name = op.first
    feat = op.second
    result = feat(bars)
    return NamedTuple{(name,)}((result,))
end

compute(feats::Features, x::Union{NamedTuple,PriceBars}) = feats(x)
compute(feat::AbstractFeature, x::Union{NamedTuple,PriceBars}) = feat(x)

# ── Pipeline operator support for Features ──
>>(f::Features, g::PipeOrFunc) = g ∘ f
>>(f::PipeOrFunc, g::Features) = g ∘ f
>>(f::Features, g::Features) = g ∘ f
>>(data::Any, pipe::Features) = Job(data, pipe)
>>(j::Job, next_step::Features) = Job(j.data, next_step ∘ j.pipeline)

# ── EMA (replaces ema.jl) ───────────────────────────────────────────────────

struct EMA <: AbstractFeature
    period::Int
    field::Symbol
    function EMA(period::Int; field::Symbol=:close)
        _natural(period)
        return new(period, field)
    end
end

function (feat::EMA)(bars::PriceBars)
    series = getproperty(bars, feat.field)
    return feat(series)
end

function (feat::EMA)(x::AbstractVector{T}) where {T<:Real}
    n = length(x)
    dest = Vector{T}(undef, n)
    _compute_ema!(dest, x, feat.period, n)
    return dest
end

compute(feat::EMA, x::AbstractVector{T}) where {T<:Real} = feat(x)

function compute!(
    dest::AbstractVector{T}, feat::EMA, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(prices) || throw(
        DimensionMismatch("dest length $(length(dest)) != prices length $(length(prices))"),
    )
    _compute_ema!(dest, prices, feat.period, length(prices))
    return dest
end

function _compute_ema!(
    dest::AbstractVector{T}, x::AbstractVector{T}, p::Int, n::Int
) where {T<:Real}
    if p > n
        fill!(dest, T(NaN))
        return nothing
    end
    @views fill!(dest[1:(p - 1)], T(NaN))
    dest[p] = _sma_seed(x, p)
    alpha = T(2) / T(p + 1)
    beta = one(T) - alpha
    _ema_kernel_unrolled!(dest, x, p, n, alpha, beta)
    return nothing
end

@inline function _sma_seed(x::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    @fastmath @inbounds begin
        s = zero(T)
        @simd for i in 1:p
            s += x[i]
        end
        return s / T(p)
    end
end

@inline function _ema_kernel_unrolled!(
    ema::AbstractVector{T}, x::AbstractVector{T}, p::Int, n::Int, alpha::T, beta::T
) where {T<:Real}
    @fastmath @inbounds begin
        beta2, beta3, beta4 = beta^2, beta^3, beta^4
        c0, c1, c2, c3 = alpha, alpha * beta, alpha * beta2, alpha * beta3
        prev = ema[p]
        i = p + 1
        while i <= n - 3
            p1, p2, p3, p4 = x[i], x[i + 1], x[i + 2], x[i + 3]
            ema[i] = c0 * p1 + beta * prev
            ema[i + 1] = c0 * p2 + c1 * p1 + beta2 * prev
            ema[i + 2] = c0 * p3 + c1 * p2 + c2 * p1 + beta3 * prev
            ema[i + 3] = c0 * p4 + c1 * p3 + c2 * p2 + c3 * p1 + beta4 * prev
            prev = ema[i + 3]
            i += 4
        end
        while i <= n
            prev = alpha * x[i] + beta * prev
            ema[i] = prev
            i += 1
        end
    end
end

# ── CUSUM (replaces cusum.jl) ───────────────────────────────────────────────

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

function (feat::CUSUM)(bars::PriceBars)
    series = getproperty(bars, feat.field)
    return feat(series)
end

function (feat::CUSUM)(x::AbstractVector{T}) where {T<:Real}
    n = length(x)
    warmup_idx = feat.span + 1
    if n <= warmup_idx
        return _warn_and_return_zeros(n, warmup_idx)
    end
    dest = zeros(Int8, n)
    _compute_cusum!(feat, dest, x, warmup_idx)
    return dest
end

compute(feat::CUSUM, x::AbstractVector{T}) where {T<:Real} = feat(x)

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
    _compute_cusum!(feat, dest, prices, warmup_idx)
    return dest
end

function _compute_cusum!(
    feat::CUSUM, dest::AbstractVector{Int8}, x::AbstractVector{T}, warmup_idx::Int
) where {T<:Real}
    n = length(x)
    @fastmath @inbounds begin
        alpha = T(2.0) / (T(feat.span) + one(T))
        beta = one(T) - alpha

        sum_sq_ret = zero(T)
        prev_log = log(x[1])

        for k in 2:warmup_idx
            curr_log = log(x[k])
            sum_sq_ret += (curr_log - prev_log)^2
            prev_log = curr_log
        end

        ema_sq_mean = sum_sq_ret / T(warmup_idx - 1)
        s_pos = zero(T)
        s_neg = zero(T)

        for i in (warmup_idx + 1):n
            curr_log = log(x[i])
            log_return = curr_log - prev_log
            prev_log = curr_log

            threshold = sqrt(max(T(1e-16), ema_sq_mean)) * feat.multiplier

            s_pos = max(zero(T), s_pos + log_return - feat.expected_value)
            s_neg = min(zero(T), s_neg + log_return + feat.expected_value)

            if s_pos > threshold
                dest[i] = 1
                s_pos = zero(T)
            elseif s_neg < -threshold
                dest[i] = -1
                s_neg = zero(T)
            end

            ema_sq_mean = alpha * log_return^2 + beta * ema_sq_mean
        end
        return nothing
    end
end

@noinline function _warn_and_return_zeros(n, warmup_idx)
    @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
    return zeros(Int8, n)
end
