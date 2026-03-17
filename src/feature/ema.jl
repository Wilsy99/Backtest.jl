struct EMA <: AbstractFeature
    period::Int
    field::Symbol
    function EMA(period::Int; field::Symbol=:close)
        _natural(period)
        return new(period, field)
    end
end

function compute(feat::EMA, d::NamedTuple)
    return compute(feat, d.bars)
end

function compute(feat::EMA, bars::PriceBars)
    return compute(feat, getproperty(bars, feat.field))
end

function compute(feat::EMA, prices::AbstractVector{T}) where {T<:AbstractFloat}
    return _calculate_ema(prices, feat.period)
end

function compute!(
    dest::AbstractVector{T}, feat::EMA, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(prices) || throw(
        DimensionMismatch("dest length $(length(dest)) != prices length $(length(prices))"),
    )
    _single_ema!(dest, prices, feat.period, length(prices))
    return dest
end

function _calculate_ema(prices::AbstractVector{T}, period::Int) where {T<:AbstractFloat}
    n_prices = length(prices)
    results = Vector{T}(undef, n_prices)
    _single_ema!(results, prices, period, n_prices)
    return results
end

function _single_ema!(
    dest::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int
) where {T<:AbstractFloat}
    if p > n
        fill!(dest, T(NaN))
        return nothing
    end
    @views fill!(dest[1:(p - 1)], T(NaN))
    dest[p] = _sma_seed(prices, p)
    α = T(2) / T(p + 1)
    β = one(T) - α
    _ema_kernel_unrolled!(dest, prices, p, n, α, β)
    return nothing
end

@inline function _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    s = zero(T)
    @fastmath @inbounds @simd for i in 1:p
        s += prices[i]
    end
    return s / T(p)
end

@inline function _ema_kernel_unrolled!(
    ema::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int, α::T, β::T
) where {T<:AbstractFloat}
    β2, β3, β4 = β^2, β^3, β^4
    c0, c1, c2, c3 = α, α * β, α * β2, α * β3
    @inbounds prev = ema[p]
    i = p + 1
    @fastmath @inbounds while i <= n - 3
        p1, p2, p3, p4 = prices[i], prices[i + 1], prices[i + 2], prices[i + 3]
        ema[i] = c0 * p1 + β * prev
        ema[i + 1] = c0 * p2 + c1 * p1 + β2 * prev
        ema[i + 2] = c0 * p3 + c1 * p2 + c2 * p1 + β3 * prev
        ema[i + 3] = c0 * p4 + c1 * p3 + c2 * p2 + c3 * p1 + β4 * prev
        prev = ema[i + 3]
        i += 4
    end
    @fastmath @inbounds while i <= n
        prev = α * prices[i] + β * prev
        ema[i] = prev
        i += 1
    end
end

(ema::EMA)(data) = compute(ema, data)
