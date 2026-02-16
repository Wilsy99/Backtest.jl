"""
    EMA{Periods} <: AbstractFeature

Exponential moving average feature parameterised by one or more
periods.

Compute EMA values using the recursive formula
`EMA[t] = α * price[t] + (1 - α) * EMA[t-1]` where
`α = 2 / (period + 1)`. The first `period - 1` values are `NaN`
(warmup). The value at index `period` is the simple moving average
seed.

# Type Parameters
- `Periods::Tuple{Vararg{Int}}`: the EMA periods. Must be unique
    positive integers.

# Fields
- `multi_thread::Bool`: enable multi-threaded computation for
    multi-period EMAs.

# Constructors
    EMA(period::Int; multi_thread=false)
    EMA(periods::Vararg{Int}; multi_thread=false)

# Throws
- `ArgumentError`: if any period is non-positive, periods are empty,
    or periods are not unique.

# Examples
```jldoctest
julia> using Backtest

julia> ema = EMA(10);

julia> ema isa AbstractFeature
true

julia> EMA(10, 50) isa AbstractFeature
true
```

# See also
- [`CUSUM`](@ref): cumulative sum feature for structural breaks.
- [`calculate_feature`](@ref): the dispatch point for all features.

# Extended help

## Callable Interface

`EMA` instances are callable. When called with [`PriceBars`](@ref)
or a `NamedTuple` from a previous pipeline stage, they compute the
EMA on `bars.close` and merge the result into the pipeline data:

```julia
bars = get_data("AAPL")
result = EMA(10, 50)(bars)
# result is a NamedTuple with fields :bars, :ema_10, :ema_50
```

The field names follow the pattern `:ema_<period>`.

## Pipeline Composition

Use `>>` to compose into a pipeline:

```julia
job = bars >> EMA(10, 50) >> evt >> lab
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

## Multi-threading

When `EMA` is constructed with `multi_thread=true` and has multiple
periods, each period's computation runs on a separate thread via
`Threads.@threads`. Single-period computation is always
single-threaded.
"""
struct EMA{Periods} <: AbstractFeature
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

"""
    calculate_feature(feat::EMA{Periods}, prices::AbstractVector{T}) where {Periods, T<:AbstractFloat} -> Union{Vector{T}, Matrix{T}}

Compute EMA values for `prices` at the periods specified in `feat`.

Return a `Vector{T}` when `Periods` contains a single period, or a
`Matrix{T}` of size `(length(prices), length(Periods))` for multiple
periods. The element type of the output matches the input.

# Arguments
- `feat::EMA{Periods}`: the EMA feature instance.
- `prices::AbstractVector{T}`: price series. Must have at least
    `maximum(Periods)` elements for meaningful output.

# Returns
- `Vector{T}`: when `length(Periods) == 1`. First `period - 1`
    entries are `NaN`.
- `Matrix{T}`: when `length(Periods) > 1`. Column `j` corresponds
    to `Periods[j]`.

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_feature(EMA(3), prices);

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

## Multi-threading

When `EMA` is constructed with `multi_thread=true` and has multiple
periods, each period's computation runs on a separate thread via
`Threads.@threads`. Single-period computation is always
single-threaded.
"""
function calculate_feature(
    feat::EMA{Periods}, prices::AbstractVector{T}
) where {Periods,T<:AbstractFloat}
    if length(Periods) == 1
        return _calculate_ema(prices, Periods[1])
    else
        return _calculate_emas(prices, Periods, feat.multi_thread)
    end
end

"""
    _feature_result(feat::EMA{Periods}, prices) -> NamedTuple

`@generated` function that return a `NamedTuple` with keys derived
from the period values (e.g., `(:ema_10, :ema_50)`). Single-period
EMAs return vectors as values; multi-period EMAs return column views
into the result matrix.

This is the bridge between [`calculate_feature`](@ref) (which returns
raw arrays) and the callable/pipeline interface (which needs named
fields for downstream access).
"""
@generated function _feature_result(
    feat::EMA{Periods}, prices::AbstractVector{T}
) where {Periods,T<:AbstractFloat}
    names = Tuple(Symbol(:ema_, p) for p in Periods)
    n = length(Periods)
    if n == 1
        quote
            vals = calculate_feature(feat, prices)
            NamedTuple{$names}((vals,))
        end
    else
        col_exprs = [:(vals[:, $i]) for i in 1:n]
        quote
            vals = calculate_feature(feat, prices)
            @views NamedTuple{$names}(($(col_exprs...),))
        end
    end
end

"""
    _calculate_ema(prices::AbstractVector{T}, period::Int) -> Vector{T}

Allocate a result vector and compute a single EMA of `period` over
`prices`.
"""
function _calculate_ema(prices::AbstractVector{T}, period::Int) where {T<:AbstractFloat}
    n_prices = length(prices)
    results = Vector{T}(undef, n_prices)
    _single_ema!(results, prices, period, n_prices)
    return results
end

"""
    _calculate_emas(prices::AbstractVector{T}, periods, multi_thread::Bool) -> Matrix{T}

Allocate a result matrix and compute EMAs for all `periods`. Column
`j` holds the EMA for `periods[j]`. Dispatch to multi-threaded path
when `multi_thread` is `true`.
"""
function _calculate_emas(
    prices::AbstractVector{T}, periods, multi_thread::Bool=false
) where {T<:AbstractFloat}
    n_prices = length(prices)
    n_emas = length(periods)
    results = Matrix{T}(undef, n_prices, n_emas)
    @views if multi_thread
        @threads for j in 1:n_emas
            _single_ema!(results[:, j], prices, periods[j], n_prices)
        end
    else
        for j in 1:n_emas
            _single_ema!(results[:, j], prices, periods[j], n_prices)
        end
    end
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
    @inbounds @simd for i in 1:p
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
    @inbounds while i <= n - 3
        p1, p2, p3, p4 = prices[i], prices[i + 1], prices[i + 2], prices[i + 3]
        ema[i] = c0 * p1 + β * prev
        ema[i + 1] = c0 * p2 + c1 * p1 + β2 * prev
        ema[i + 2] = c0 * p3 + c1 * p2 + c2 * p1 + β3 * prev
        ema[i + 3] = c0 * p4 + c1 * p3 + c2 * p2 + c3 * p1 + β4 * prev
        prev = ema[i + 3]
        i += 4
    end
    # Scalar tail for remaining elements
    @inbounds while i <= n
        prev = α * prices[i] + β * prev
        ema[i] = prev
        i += 1
    end
end