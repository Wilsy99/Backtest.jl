"""
    Features{T<:Tuple}

Fused feature aggregator that computes multiple named features in a
single pipeline step, merging results flat into the pipeline
`NamedTuple`.

Each feature is specified as a `Symbol => AbstractFeature` pair,
giving the user explicit control over the output field names.

# Type Parameters
- `T<:Tuple`: tuple of `Pair{Symbol, <:AbstractFeature}` instances.

# Constructors
    Features(ops::Pair{Symbol, <:AbstractFeature}...)

# Examples
```jldoctest
julia> using Backtest

julia> f = Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0));

julia> f isa Features
true
```

# See also
- [`EMA`](@ref): exponential moving average feature.
- [`CUSUM`](@ref): cumulative sum filter feature.
- [`compute`](@ref): the dispatch point for all features.

# Extended help

## Performance

Because features are computed back-to-back on the same `prices`
vector, the data stays hot in L1/L2 cache for the second (and
subsequent) feature computations. A single `merge` call combines
all results into the pipeline — total merge overhead is constant
regardless of the number of features.

## Pipeline Usage

```julia
# Single pipeline step:
bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20),
                 :cusum => CUSUM(1.0)) |> Crossover(:ema_10, :ema_20)

# Works with the >> operator:
job = bars >> Features(:ema_10 => EMA(10), :cusum => CUSUM(1.0)) >> side >> event >> label
```

## Callable Interface

`Features` is callable with three input forms:

- `PriceBars`: compute features on bar data, return
  `(bars=bars, ema_10=..., cusum=...)`.
- `NamedTuple` (pipeline): compute features and merge flat into
  the pipeline data.
- `AbstractVector{<:AbstractFloat}`: compute features on a raw
  price vector, return the features `NamedTuple` directly.

## Pipeline Data Flow

### Input
- `bars::PriceBars`, a `NamedTuple` with at least `bars::PriceBars`,
  or an `AbstractVector{<:AbstractFloat}`.

### Output
Return a `NamedTuple` with `bars` plus flat feature keys (e.g.,
`(bars=..., ema_10=Vector{Float64}, cusum=Vector{Int8})`).
"""
struct Features{T<:Tuple}
    operations::T

    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        length(ops) >= 1 ||
            throw(ArgumentError("Features requires at least 1 feature"))
        return new{typeof(ops)}(ops)
    end
end

"""
    (feats::Features)(bars::PriceBars) -> NamedTuple

Compute all features on `bars` and return a `NamedTuple` with
`bars` and flat feature keys.

# Pipeline Data Flow

## Input
- `bars::PriceBars`: the price data.

## Output
Return a `NamedTuple` with:
- `bars::PriceBars`: the original price data (passthrough).
- Feature-specific keys from the user-supplied symbols (e.g.,
    `:ema_10`, `:cusum`).
"""
function (feats::Features)(bars::PriceBars)
    feats_results = _compute_features(feats, bars)
    return merge((bars=bars,), feats_results)
end

"""
    (feats::Features)(d::NamedTuple) -> NamedTuple

Compute all features on the pipeline data and merge the flat
feature results into the existing `NamedTuple`, preserving all
upstream keys.

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with at least:
- `bars::PriceBars`: the price data.

## Output
Return the input `NamedTuple` merged with flat feature keys.
"""
function (feats::Features)(d::NamedTuple)
    feats_results = _compute_features(feats, d)
    return merge(d, feats_results)
end

"""
    (feats::Features)(prices::AbstractVector{T}) where {T<:AbstractFloat} -> NamedTuple

Compute all features on a raw price vector and return the features
`NamedTuple` directly (no `bars` wrapping).

# Arguments
- `prices::AbstractVector{T}`: the price series.

# Returns
- `NamedTuple`: feature vectors keyed by the user-supplied symbols.
"""
function (feats::Features)(prices::AbstractVector{T}) where {T<:AbstractFloat}
    return _compute_features(feats, prices)
end

# ── Compute Engine ──

"""
    _compute_features(feats::Features{T}, data) -> NamedTuple

`@generated` function that unrolls all feature pair computations
at compile time.

For each `Pair{Symbol, <:AbstractFeature}` in the operations tuple,
extract the target series (via [`_feature_field`](@ref) and
[`_extract_series`](@ref) for structured data, or using the vector
directly), compute the feature result, and wrap it into a
`NamedTuple` keyed by the user-supplied symbol. All per-feature
results are merged in a single call.
"""
@generated function _compute_features(
    feats::Features{T}, data
) where {T<:Tuple}
    n = fieldcount(T)
    syms = [Symbol(:_r, i) for i in 1:n]
    stmts = [:($(syms[i]) = _compute_single_feature(
        feats.operations[$i], data)) for i in 1:n]
    return quote
        $(stmts...)
        merge($(syms...))
    end
end

"""
    _compute_single_feature(op::Pair{Symbol, <:AbstractFeature}, data) -> NamedTuple

Compute a single feature from a `Symbol => AbstractFeature` pair.

Extract the target series from `data` (using [`_feature_field`](@ref)
for structured data, or using the vector directly), compute the
feature, and return a single-key `NamedTuple`.

# Arguments
- `op::Pair{Symbol, <:AbstractFeature}`: the name-feature pair.
- `data`: either `PriceBars`, a pipeline `NamedTuple`, or
    `AbstractVector{<:AbstractFloat}`.

# Returns
- `NamedTuple{(name,)}((result,))`: the computed feature vector
  keyed by the user-supplied symbol.
"""
function _compute_single_feature(
    op::Pair{Symbol,F},
    data::PriceBars,
) where {F<:AbstractFeature}
    name = op.first
    feature = op.second
    series = _extract_series(data, _feature_field(feature))
    result = _feature_result(feature, series)
    return NamedTuple{(name,)}((result,))
end

function _compute_single_feature(
    op::Pair{Symbol,F},
    data::NamedTuple,
) where {F<:AbstractFeature}
    name = op.first
    feature = op.second
    series = _extract_series(data, _feature_field(feature))
    result = _feature_result(feature, series)
    return NamedTuple{(name,)}((result,))
end

function _compute_single_feature(
    op::Pair{Symbol,F},
    prices::AbstractVector{T},
) where {F<:AbstractFeature,T<:AbstractFloat}
    name = op.first
    feature = op.second
    result = _feature_result(feature, prices)
    return NamedTuple{(name,)}((result,))
end

# ── Pipeline operator (>>) support ──
# Features is not an AbstractFeature subtype, so it needs its own
# >> methods to integrate with the pipeline composition system.

>>(f::PipeOrFunc, g::Features) = g ∘ f
>>(f::Features, g::PipeOrFunc) = g ∘ f
>>(f::Features, g::Features) = g ∘ f
>>(data::Any, pipe::Features) = Job(data, pipe)
>>(j::Job, next_step::Features) = Job(j.data, next_step ∘ j.pipeline)
