# new feature.jl
struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

# only features functor returns named tuple and only allows named tuple or price bars as input
function (feats::Features)(d::NamedTuple)
    feats_results = compute(feats, d.bars)
    return merge(d, (features=feats_results,))
end

function (feats::Features)(bars::PriceBars)
    feats_results = compute(feats, bars)
    return (bars=bars, features=feats_results)
end

@generated function compute(
    feats::Features{T}, x::Union{PriceBars,NamedTuple}
) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(compute(feats.operations[$i], x)) for i in 1:n]
    return :(merge($(exprs...)))
end

function compute(op::Pair{Symbol,<:AbstractFeature}, x::Union{PriceBars,NamedTuple})
    feat = op.second
    result = compute(feat, x)
    return NamedTuple{(op.first,)}((result,))
end

function compute(feat::AbstractFeature, d::NamedTuple)
    return compute(feat, d.bars)
end

(feat::AbstractFeature)(d::NamedTuple) = compute(feat, d.bars)
(feat::AbstractFeature)(bars::PriceBars) = compute(feat, bars)
#Each feature script eg ema.jl defines its own compute functions in its script and only returns vector
#Example of new ema.jl

struct EMA <: AbstractFeature
    period::Int
    field::Symbol
    function EMA(period::Int; field::Symbol=:close)
        _natural(period)
        return new(period, field)
    end
end

(feat::EMA)(x::AbstractVector{T}) where {(T <: Real)} = compute(feat, x)

function compute(feat::EMA, bars::PriceBars)
    return compute(feat, getproperty(bars, feat.field))
end

function compute!(feat::EMA, dest::AbstractVector{T}, bars::PriceBars) where {T<:Real}
    return compute!(feat, dest, getproperty(bars, feat.field))
end

function compute(feat::EMA, x::AbstractVector{T}) where {T<:Real}
    len_x = length(x)
    dest = Vector{T}(undef, n)
    _compute_ema!(dest, x, feat.period, len_x)
    return dest
end

function compute!(feat::EMA, dest::AbstractVector{T}, x::AbstractVector{T}) where {T<:Real}
    len_dest = length(dest)
    len_x = length(x)

    len_dest == len_x || throw(
        DimensionMismatch("dest length $(length(dest)) != price data length $(length(x))"),
    )
    return _compute_ema!(dest, x, feat.period, len_x)
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
    α = T(2) / T(p + 1)
    β = one(T) - α
    _ema_kernel_unrolled!(dest, x, p, n, α, β)
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
    ema::AbstractVector{T}, x::AbstractVector{T}, p::Int, n::Int, α::T, β::T
) where {T<:Real}
    @fastmath @inbounds begin
        # Pre-compute powers for the 4-wide unrolled recurrence
        β2, β3, β4 = β^2, β^3, β^4
        c0, c1, c2, c3 = α, α * β, α * β2, α * β3
        prev = ema[p]
        i = p + 1
        while i <= n - 3
            p1, p2, p3, p4 = x[i], x[i + 1], x[i + 2], x[i + 3]
            ema[i] = c0 * p1 + β * prev
            ema[i + 1] = c0 * p2 + c1 * p1 + β2 * prev
            ema[i + 2] = c0 * p3 + c1 * p2 + c2 * p1 + β3 * prev
            ema[i + 3] = c0 * p4 + c1 * p3 + c2 * p2 + c3 * p1 + β4 * prev
            prev = ema[i + 3]
            i += 4
        end
        # Scalar tail for remaining elements
        while i <= n
            prev = α * x[i] + β * prev
            ema[i] = prev
            i += 1
        end
    end
end