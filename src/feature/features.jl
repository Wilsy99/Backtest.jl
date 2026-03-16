"""
    Features{T<:Tuple}

Named feature collection that computes multiple features in a single pipeline
step and nests results under a `:features` key.

Replace individual feature chaining (`bars |> EMA(10) |> EMA(20)`) with
explicit `Symbol => AbstractFeature` pairs:

```julia
bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1))
```

Results are nested under a `:features` key in the pipeline `NamedTuple`,
giving downstream stages a clean namespace for feature vectors.

# Type Parameters
- `T<:Tuple`: tuple of `Pair{Symbol, <:AbstractFeature}` instances.

# Fields
- `operations::T`: tuple of `Symbol => AbstractFeature` pairs defining
    feature names and their computations.

# Constructors
    Features(ops::Pair{Symbol, <:AbstractFeature}...)

# Examples
```jldoctest
julia> using Backtest

julia> f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20));

julia> f isa Features
true
```

# See also
- [`EMA`](@ref): exponential moving average feature.
- [`CUSUM`](@ref): cumulative sum filter feature.
- [`compute`](@ref): standalone computation function.

# Extended help

## Performance

All features are computed back-to-back on the same `prices` vector via a
`@generated` function that unrolls the pair tuple at compile time. The data
stays hot in L1/L2 cache for subsequent feature computations. A single
`merge()` of per-feature results replaces `N` sequential merges into the
growing pipeline `NamedTuple`.

## Pipeline Data Flow

### Input
- `bars::PriceBars`: raw price data (direct call).
- `NamedTuple` with at least `bars::PriceBars` (pipeline call).
- `AbstractVector{T}` where `T<:AbstractFloat` (vector call).

### Output
- **PriceBars input**: `(bars=bars, features=(name1=vec1, name2=vec2, ...))`.
- **NamedTuple input**: input merged with
    `(features=(name1=vec1, name2=vec2, ...),)`.
- **AbstractVector input**: `(name1=vec1, name2=vec2, ...)` (the features
    `NamedTuple` directly, no `:bars` or `:features` wrapper).

## Callable Interface

`Features` instances are callable:

```julia
bars = get_data("AAPL")
result = bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20))
result.features.ema_10  # access the EMA(10) result
```
"""
struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

"""
    (feats::Features)(d::NamedTuple) -> NamedTuple

Compute all features on the pipeline data and merge the results under a
`:features` key.

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with at least `bars::PriceBars`.

## Output
Return the input merged with `(features=(name1=vec1, ...),)`.
"""
function (feats::Features)(d::NamedTuple)
    feats_results = compute(feats, d.bars)
    return merge(d, (features=feats_results,))
end

"""
    (feats::Features)(bars::PriceBars) -> NamedTuple

Compute all features on `bars` and return a `NamedTuple` with `bars` and
nested `features`.

# Pipeline Data Flow

## Input
- `bars::PriceBars`: the price data.

## Output
Return `(bars=bars, features=(name1=vec1, ...))`.
"""
function (feats::Features)(bars::PriceBars)
    feats_results = compute(feats, bars)
    return (bars=bars, features=feats_results)
end

"""
    (feats::Features)(prices::AbstractVector{T}) where {T<:AbstractFloat} -> NamedTuple

Compute all features directly on a price vector and return the features
`NamedTuple` without any `:bars` or `:features` wrapper.

# Arguments
- `prices::AbstractVector{T}`: the input price series.

# Returns
- `NamedTuple`: feature results keyed by user-supplied symbols.
"""
function (feats::Features)(prices::AbstractVector{T}) where {T<:AbstractFloat}
    return compute(feats, prices)
end

"""
    compute(feats::Features{T}, prices) where {T<:Tuple} -> NamedTuple

`@generated` function that unrolls the `Features` pair tuple at compile time,
calling each feature's computation independently and merging results in a
single `merge()` call.

Each `Pair{Symbol, <:AbstractFeature}` in the tuple is evaluated by extracting
the target series (via `_feature_field`) and computing the feature result (via
`_feature_result`). The result vector is wrapped in a single-key `NamedTuple`
using the user-supplied symbol name.

The generated code is fully unrolled for the concrete pair tuple type,
eliminating all runtime dispatch and enabling the compiler to optimise each
feature computation independently.
"""
@generated function compute(feats::Features{T}, prices) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(compute(feats.operations[$i], prices)) for i in 1:n]
    return :(merge($(exprs...)))
end

"""
    compute(op::Pair{Symbol,<:AbstractFeature}, prices) -> NamedTuple

Compute a single named feature on `prices` and wrap the result in a
single-key `NamedTuple`.

# Arguments
- `op::Pair{Symbol, <:AbstractFeature}`: the name and feature to compute.
- `prices`: `PriceBars` or `AbstractVector{T}` input data.

# Returns
- `NamedTuple{(name,)}((result,))`: the feature result keyed by `name`.
"""
function compute(
    op::Pair{Symbol,<:AbstractFeature},
    prices::Union{PriceBars,AbstractVector{T}},
) where {T<:AbstractFloat}
    name = op.first
    feature = op.second

    series = if prices isa PriceBars
        _extract_series(prices, _feature_field(feature))
    else
        prices
    end

    result = _feature_result(feature, series)
    return NamedTuple{(name,)}((result,))
end

"""
    (feat::AbstractFeature)(prices::AbstractVector{T}) where {T<:AbstractFloat} -> NamedTuple

Compute the feature directly on a price vector and return a `NamedTuple`
with the named result.

# Arguments
- `prices::AbstractVector{T}`: the input price series.

# Returns
- `NamedTuple`: single-key result using `_feature_names(feat)`.
"""
function (feat::AbstractFeature)(prices::AbstractVector{T}) where {T<:AbstractFloat}
    result = _feature_result(feat, prices)
    return _wrap_result(feat, result)
end

# ── Pipeline operator support for Features ──
# Features is not a subtype of AbstractFeature, so it needs its own >>
# overloads to integrate with the pipeline operator defined in types.jl.

>>(f::Features, g::PipeOrFunc) = g ∘ f
>>(f::PipeOrFunc, g::Features) = g ∘ f
>>(f::Features, g::Features) = g ∘ f
>>(data::Any, pipe::Features) = Job(data, pipe)
>>(j::Job, next_step::Features) = Job(j.data, next_step ∘ j.pipeline)
