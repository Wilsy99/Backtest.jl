"""
    EMA <: AbstractFeature

Exponential moving average feature parameterised by a single period.

Compute EMA values using the recursive formula
`EMA[t] = α * price[t] + (1 - α) * EMA[t-1]` where
`α = 2 / (period + 1)`. The first `period - 1` values are `NaN`
(warmup). The value at index `period` is the simple moving average
seed.

# Fields
- `period::Int`: the EMA period. Must be a positive integer.

# Constructors
    EMA(period::Int)

# Throws
- `ArgumentError`: if period is non-positive.

# Examples
```jldoctest
julia> using Backtest

julia> ema = EMA(10);

julia> ema isa AbstractFeature
true
```

# See also
- [`CUSUM`](@ref): cumulative sum feature for structural breaks.
- [`compute`](@ref): the dispatch point for all features.

# Extended help

## Callable Interface

`EMA` instances are callable. When called with [`PriceBars`](@ref)
or a `NamedTuple` from a previous pipeline stage, they compute the
EMA on `bars.close` and merge the result into the pipeline data:

```julia
bars = get_data("AAPL")
result = EMA(10)(bars)
# result is a NamedTuple with fields :bars, :ema_10
```

The field names follow the pattern `:ema_<period>`.

## Pipeline Composition

Use `>>` to compose into a pipeline:

```julia
job = bars >> EMA(10) >> evt >> lab
result = job()
```

## Algorithm

The EMA is seeded with the Simple Moving Average (SMA) of the first
`period` values. Subsequent values use the recurrence:

    EMA[i] = α * price[i] + (1 - α) * EMA[i-1]

where `α = 2 / (period + 1)`.

The kernel (`_ema_kernel_unrolled!`) processes 4 elements per
iteration to improve instruction-level parallelism on modern CPUs.
A scalar tail loop handles the remainder.
"""
struct EMA <: AbstractFeature
    period::Int
    field::Symbol
    function EMA(period::Int; field::Symbol=:close)
        _natural(period)
        return new(period, field)
    end
end

_feature_field(feat::EMA) = feat.field

"""
    compute(feat::EMA, prices::AbstractVector{T}) where {T<:AbstractFloat} -> Vector{T}

Compute EMA values for `prices` at the period specified in `feat`.

Return a `Vector{T}` of length `length(prices)`. The element type
of the output matches the input.

# Arguments
- `feat::EMA`: the EMA feature instance.
- `prices::AbstractVector{T}`: price series. Must have at least
    `feat.period` elements for meaningful output.

# Returns
- `Vector{T}`: first `period - 1` entries are `NaN`.

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = compute(EMA(3), prices);

julia> ema[3] ≈ 11.0
true

julia> all(isnan, ema[1:2])
true
```

# See also
- [`EMA`](@ref): constructor and type documentation.

# Extended help

## Algorithm

The EMA is seeded with the Simple Moving Average (SMA) of the first
`period` values. Subsequent values use the recurrence:

    EMA[i] = α * price[i] + (1 - α) * EMA[i-1]

where `α = 2 / (period + 1)`.

The kernel (`_ema_kernel_unrolled!`) processes 4 elements per
iteration to improve instruction-level parallelism on modern CPUs.
A scalar tail loop handles the remainder.
"""
function compute(
    feat::EMA, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    return _compute_ema(prices, feat.period)
end

"""
    compute!(dest::AbstractVector{T}, feat::EMA, prices::AbstractVector{T}) where {T<:AbstractFloat} -> dest

Compute a single-period EMA in-place, writing results into the
pre-allocated vector `dest`. This avoids allocation for
performance-critical paths such as Monte Carlo simulations or
high-frequency backtests.

# Arguments
- `dest::AbstractVector{T}`: output vector. Must have the same
    length as `prices`.
- `feat::EMA`: the EMA feature instance.
- `prices::AbstractVector{T}`: the input price series.

# Returns
- `dest`: the mutated output vector (returned for convenience).

# Throws
- `DimensionMismatch`: if `length(dest) != length(prices)`.

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> dest = similar(prices);

julia> compute!(dest, EMA(3), prices);

julia> dest[3] ≈ 11.0
true
```

# See also
- [`compute`](@ref): allocating version.
- [`EMA`](@ref): constructor and type documentation.
"""
function compute!(
    dest::AbstractVector{T}, feat::EMA, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(prices) ||
        throw(DimensionMismatch("dest length $(length(dest)) != prices length $(length(prices))"))
    _single_ema!(dest, prices, feat.period, length(prices))
    return dest
end

"""
    _feature_names(feat::EMA) -> Tuple{Symbol}

Return the named keys for this feature's pipeline output.
"""
_feature_names(feat::EMA) = (Symbol(:ema_, feat.period),)

"""
    _compute_ema(prices::AbstractVector{T}, period::Int) -> Vector{T}

Allocate a result vector and compute a single EMA of `period` over
`prices`.
"""
function _compute_ema(prices::AbstractVector{T}, period::Int) where {T<:AbstractFloat}
    n_prices = length(prices)
    results = Vector{T}(undef, n_prices)
    _single_ema!(results, prices, period, n_prices)
    return results
end

"""
    _single_ema!(dest, prices, p, n) -> Nothing

Compute a single EMA of period `p` over `prices[1:n]`, writing
results into `dest`. Fill `dest[1:p-1]` with `NaN` (warmup), set
`dest[p]` to the SMA seed, then delegate to the unrolled kernel.

When `p > n`, fill the entire output with `NaN`.
"""
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

"""Return the simple moving average of `prices[1:p]`."""
@inline function _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    s = zero(T)
    @fastmath @inbounds @simd for i in 1:p
        s += prices[i]
    end
    return s / T(p)
end

"""
    _ema_kernel_unrolled!(ema, prices, p, n, α, β) -> Nothing

Fill `ema[p+1:n]` with EMA values using 4-wide loop unrolling for
instruction-level parallelism.

Mutate `ema` in-place. Assume `ema[p]` is already set to the SMA
seed. This function is the hot path — it must remain zero-allocation
and type-stable.

`α` is the smoothing factor `2/(period+1)` and `β = 1 - α`.
"""
@inline function _ema_kernel_unrolled!(
    ema::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int, α::T, β::T
) where {T<:AbstractFloat}
    # Pre-compute powers for the 4-wide unrolled recurrence
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
    # Scalar tail for remaining elements
    @fastmath @inbounds while i <= n
        prev = α * prices[i] + β * prev
        ema[i] = prev
        i += 1
    end
end