struct EMA{Periods} <: AbstractIndicator
    multi_thread::Bool
    function EMA{Periods}(; multi_thread::Bool=false) where {Periods}
        isempty(Periods) && throw(ArgumentError("At least one period is required"))
        allunique(Periods) || throw(ArgumentError("Periods must be unique, got $Periods"))
        foreach(_natural, Periods)
        return new{Periods}(multi_thread)
    end
end

EMA(p::Int; multi_thread::Bool=false) = EMA{(p,)}(; multi_thread)
EMA(ps::Vararg{Int}; multi_thread::Bool=false) = EMA{ps}(; multi_thread)

function calculate_indicator(
    ind::EMA{Periods}, prices::AbstractVector{T}; multi_thread::Bool=ind.multi_thread
) where {Periods,T<:AbstractFloat}
    if length(Periods) == 1
        return _calculate_ema(prices, Periods[1])
    else
        return _calculate_emas(prices, collect(Periods), multi_thread)
    end
end

@generated function _indicator_result(
    ind::EMA{Periods}, prices::AbstractVector{T}
) where {Periods,T<:AbstractFloat}
    names = Tuple(Symbol(:ema_, p) for p in Periods)
    n = length(Periods)
    if n == 1
        quote
            vals = calculate_indicator(ind, prices)
            NamedTuple{$names}((vals,))
        end
    else
        quote
            vals = calculate_indicator(ind, prices)
            NamedTuple{$names}(NTuple{$n}(ntuple(i -> @view(vals[:, i]), Val(n))))
        end
    end
end

function _calculate_ema(prices::AbstractVector{T}, period::Int) where {T<:AbstractFloat}
    n_prices = length(prices)
    results = Vector{T}(undef, n_prices)
    _single_ema!(results, prices, period, n_prices)
    return results
end

function _calculate_emas(
    prices::AbstractVector{T}, periods::Vector{Int}, multi_thread::Bool=false
) where {T<:AbstractFloat}
    n_prices = length(prices)
    n_emas = length(periods)

    results = Matrix{T}(undef, n_prices, n_emas)

    if multi_thread
        @threads for j in 1:n_emas
            @views _single_ema!(results[:, j], prices, periods[j], n_prices)
        end
    else
        for j in 1:n_emas
            @views _single_ema!(results[:, j], prices, periods[j], n_prices)
        end
    end

    return results
end

function _single_ema!(
    dest::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int
) where {T<:AbstractFloat}
    if p > n
        fill!(dest, T(NaN))
        return nothing
    end

    fill!(view(dest, 1:(p - 1)), T(NaN))

    dest[p] = _sma_seed(prices, p)

    α = T(2) / T(p + 1)
    β = one(T) - α

    _ema_kernel_unrolled!(dest, prices, p, n, α, β)

    return nothing
end

@inline function _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    s = zero(T)
    @inbounds @simd for i in 1:p
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
