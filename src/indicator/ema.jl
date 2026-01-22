function calculate_emas(
    prices::AbstractVector{T}, periods::Vector{Int}
) where {T<:AbstractFloat}
    n_rows = length(prices)
    n_emas = length(periods)
    results = Vector{Vector{T}}(undef, n_emas)

    @threads for j in 1:n_emas
        results[j] = _single_ema(prices, periods[j], n_rows)
    end

    return results
end

function calculate_ema(prices::AbstractVector{T}, period::Int) where {T<:AbstractFloat}
    return _single_ema(prices, period, length(prices))
end

function _single_ema(prices::AbstractVector{T}, p::Int, n::Int) where {T<:AbstractFloat}
    if p > n
        return fill(T(NaN), n)
    end

    ema = Vector{T}(undef, n)
    fill!(view(ema, 1:(p - 1)), T(NaN))
    ema[p] = _sma_seed(prices, p)

    α = T(2) / (p + 1)
    β = one(T) - α
    _ema_kernel_unrolled!(ema, prices, p, n, α, β)

    return ema
end

@inline function _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    s = zero(T)
    @inbounds @simd for i in 1:p
        s += prices[i]
    end
    return s / p
end

@inline function _ema_kernel_unrolled!(
    ema::Vector{T}, prices::AbstractVector{T}, p::Int, n::Int, α::T, β::T
) where {T<:AbstractFloat}
    β2, β3, β4 = β^2, β^3, β^4
    c0, c1, c2, c3 = α, α * β, α * β2, α * β3

    @inbounds prev = ema[p]
    i = p + 1

    # Unroll by 4 to reduce loop overhead and enable ILP
    @inbounds while i <= n - 3
        p1, p2, p3, p4 = prices[i], prices[i + 1], prices[i + 2], prices[i + 3]

        ema[i] = c0 * p1 + β * prev
        ema[i + 1] = c0 * p2 + c1 * p1 + β2 * prev
        ema[i + 2] = c0 * p3 + c1 * p2 + c2 * p1 + β3 * prev
        ema[i + 3] = c0 * p4 + c1 * p3 + c2 * p2 + c3 * p1 + β4 * prev

        prev = ema[i + 3]
        i += 4
    end

    @inbounds while i <= n
        prev = α * prices[i] + β * prev
        ema[i] = prev
        i += 1
    end
end