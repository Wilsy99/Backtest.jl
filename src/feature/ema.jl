"""
    EMA <: AbstractFeature

Exponential moving average feature parameterised by a single period.

Compute EMA values using the recursive formula
`EMA[t] = α * x[t] + (1 - α) * EMA[t-1]` where
`α = 2 / (period + 1)`. The first `period - 1` values are `NaN`
(warmup). The value at index `period` is the simple moving average
seed.

# Fields
- `period::Int`: the EMA lookback window. Must be a positive integer.
- `field::Symbol`: the [`PriceBars`](@ref) field to compute on
    (default `:close`).

# Constructors
    EMA(period::Int; field::Symbol=:close)

# Throws
- `ArgumentError`: if `period` is non-positive.

# Examples
```jldoctest
julia> using Backtest

julia> ema = EMA(10);

julia> ema isa AbstractFeature
true
```

# See also
- [`CUSUM`](@ref): cumulative sum feature for structural breaks.
- [`Features`](@ref): named collection for pipeline composition.
- [`compute`](@ref): standalone computation function.
- [`compute!`](@ref): in-place computation function.

# Extended help

## Callable Interface

`EMA` instances are callable. When called with [`PriceBars`](@ref),
they extract the target field and return the raw EMA vector:

```julia
bars = get_data("AAPL")
ema_vals = EMA(10)(bars)  # Vector{Float64}
```

To compose into a pipeline, wrap in [`Features`](@ref):

```julia
job = bars >> Features(:ema_10 => EMA(10)) >> event >> label
result = job()
result.features.ema_10  # access the EMA vector
```

## Algorithm

The EMA is seeded with the Simple Moving Average (SMA) of the first
`period` values. Subsequent values use the recurrence:

    EMA[i] = α * x[i] + (1 - α) * EMA[i-1]

where `α = 2 / (period + 1)`.

The kernel ([`_ema_kernel_unrolled!`]) processes 4 elements per
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

function (feat::EMA)(bars::PriceBars)
    series = getproperty(bars, feat.field)
    return feat(series)
end

"""
    compute(feat::EMA, x::AbstractVector{T}) where {T<:Real} -> Vector{T}

Compute EMA values for `x` at the period specified in `feat`.

Return a `Vector{T}` of length `length(x)`. The element type of
the output matches the input. The first `period - 1` entries are
`NaN` (warmup).

# Arguments
- `feat::EMA`: the EMA feature instance.
- `x::AbstractVector{T}`: input series (prices, volume, or any
    numeric sequence).

# Returns
- `Vector{T}`: EMA values. First `period - 1` entries are `NaN`.

# Examples
```jldoctest
julia> using Backtest

julia> x = Float64[10, 11, 12, 13, 14, 15];

julia> ema = compute(EMA(3), x);

julia> ema[3] ≈ 11.0
true

julia> all(isnan, ema[1:2])
true
```

# See also
- [`EMA`](@ref): constructor and type documentation.
- [`compute!`](@ref): in-place version.

# Extended help

## Algorithm

The EMA is seeded with the Simple Moving Average (SMA) of the first
`period` values. Subsequent values use the recurrence:

    EMA[i] = α * x[i] + (1 - α) * EMA[i-1]

where `α = 2 / (period + 1)`.
"""
function compute(feat::EMA, x::AbstractVector{T}) where {T<:Real}
    return feat(x)
end

function (feat::EMA)(x::AbstractVector{T}) where {T<:Real}
    n = length(x)
    dest = Vector{T}(undef, n)
    _compute_ema!(dest, x, feat.period, n)
    return dest
end

"""
    compute!(dest::AbstractVector{T}, feat::EMA, x::AbstractVector{T}) where {T<:AbstractFloat} -> dest

Compute EMA in-place, writing results into the pre-allocated
vector `dest`.

# Arguments
- `dest::AbstractVector{T}`: output vector, same length as `x`.
- `feat::EMA`: the EMA feature instance.
- `x::AbstractVector{T}`: input series (prices, volume, or any
    numeric sequence).

# Returns
- `dest`: the mutated output vector (returned for convenience).

# Throws
- `DimensionMismatch`: if `length(dest) != length(x)`.

# Examples
```jldoctest
julia> using Backtest

julia> x = Float64[10, 11, 12, 13, 14, 15];

julia> dest = similar(x);

julia> compute!(dest, EMA(3), x);

julia> dest[3] ≈ 11.0
true
```

# See also
- [`compute`](@ref): allocating version.
- [`EMA`](@ref): constructor and type documentation.
"""
function compute!(
    dest::AbstractVector{T}, feat::EMA, x::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(x) || throw(
        DimensionMismatch("dest length $(length(dest)) != x length $(length(x))"),
    )
    _compute_ema!(dest, x, feat.period, length(x))
    return dest
end

"""
    _compute_ema!(dest, x, p, n) -> Nothing

Compute a single EMA of period `p` over `x[1:n]`, writing results
into `dest`. Fill `dest[1:p-1]` with `NaN` (warmup), set `dest[p]`
to the SMA seed, then delegate to the unrolled kernel.

When `p > n`, fill the entire output with `NaN`.
"""
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

"""Return the simple moving average of `x[1:p]`."""
@inline function _sma_seed(x::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    @fastmath @inbounds begin
        s = zero(T)
        @simd for i in 1:p
            s += x[i]
        end
        return s / T(p)
    end
end

"""
    _ema_kernel_unrolled!(ema, x, p, n, alpha, beta) -> Nothing

Fill `ema[p+1:n]` with EMA values using 4-wide loop unrolling for
instruction-level parallelism.

Mutate `ema` in-place. Assume `ema[p]` is already set to the SMA
seed. This function is the hot path — it must remain
zero-allocation and type-stable.

`alpha` is the smoothing factor `2/(period+1)` and `beta = 1 - alpha`.
"""
@inline function _ema_kernel_unrolled!(
    ema::AbstractVector{T}, x::AbstractVector{T}, p::Int, n::Int, alpha::T, beta::T
) where {T<:Real}
    @fastmath @inbounds begin
        # Powers for 4-wide unrolled recurrence
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
