include("ema.jl")
include("cusum.jl")
include("features.jl")

"""
    _extract_series(data, field::Symbol) -> AbstractVector

Extract the target series from `data` by field name.

When `data` has a `bars` property (pipeline `NamedTuple`), the field
is looked up on `data.bars`. Otherwise, it is looked up directly on
`data` — this allows passing a `PriceBars`, `DataFrame`, or any
object that has the named column.
"""
@inline function _extract_series(data, field::Symbol)
    return hasproperty(data, :bars) ? getproperty(data.bars, field) : getproperty(data, field)
end

"""
    _wrap_result(feat::AbstractFeature, vec) -> NamedTuple

Wrap a feature's result vector into a `NamedTuple` using the
feature's `_feature_names`.
"""
@inline function _wrap_result(feat::AbstractFeature, vec)
    names = _feature_names(feat)
    return NamedTuple{names}((vec,))
end

"""
    (feat::AbstractFeature)(bars::PriceBars) -> NamedTuple

Compute the feature on `bars` and return a `NamedTuple`
containing `bars` and the named feature results.

The target series is determined by `_feature_field(feat)` (default
`:close`).

# Pipeline Data Flow

## Input
- `bars::PriceBars`: the price data.

## Output
Return a `NamedTuple` with:
- `bars::PriceBars`: the original price data (passthrough).
- Feature-specific keys from [`_feature_result`](@ref) (e.g.,
    `:ema_10`, `:cusum`).
"""
function (feat::AbstractFeature)(bars::PriceBars)
    series = _extract_series(bars, _feature_field(feat))
    result = _feature_result(feat, series)
    return merge((bars=bars,), _wrap_result(feat, result))
end

"""
    (feat::AbstractFeature)(d::NamedTuple) -> NamedTuple

Compute the feature on the pipeline `NamedTuple` and merge the named
results into the existing data, preserving all upstream keys.

The target series is determined by `_feature_field(feat)` (default
`:close`).

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with at least:
- `bars::PriceBars`: the price data.

## Output
Return the input `NamedTuple` merged with feature-specific keys
from [`_feature_result`](@ref).
"""
function (feat::AbstractFeature)(d::NamedTuple)
    series = _extract_series(d, _feature_field(feat))
    result = _feature_result(feat, series)
    return merge(d, _wrap_result(feat, result))
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

"""
    compute(feat::AbstractFeature, bars::PriceBars)

Compute the feature on `bars`, extracting the target series via
`_feature_field(feat)` (e.g., `:close`, `:volume`).

Returns the raw result vector (same as the vector overload).

# Examples
```julia
compute(EMA(10), bars)                    # uses bars.close
compute(EMA(10; field=:volume), bars)     # uses bars.volume
```
"""
function compute(feat::AbstractFeature, bars::PriceBars)
    series = _extract_series(bars, _feature_field(feat))
    return compute(feat, series)
end

"""
    compute(feat::AbstractFeature, d::NamedTuple)

Compute the feature on a pipeline `NamedTuple`, extracting the target
series from `d.bars.<field>` via `_feature_field(feat)`.

Returns the raw result vector (same as the vector overload).

# Examples
```julia
data = (bars=bars, ema_10=vec)
compute(EMA(20), data)                    # uses data.bars.close
compute(EMA(20; field=:high), data)       # uses data.bars.high
```
"""
function compute(feat::AbstractFeature, d::NamedTuple)
    series = _extract_series(d, _feature_field(feat))
    return compute(feat, series)
end

"""
    _feature_field(feat::AbstractFeature) -> Symbol

Return the field name of the target series for `feat`. Defaults to
`:close`. Override in subtypes to compute features on other series
(e.g., `:volume`, `:high`).
"""
_feature_field(::AbstractFeature) = :close

"""
    _feature_result(feat::AbstractFeature, prices) -> Vector

Compute the feature and return the raw result vector for pipeline
composition. Default delegates to `compute(feat, prices)`. Override
only when the pipeline result differs from `compute`.
"""
_feature_result(feat::AbstractFeature, prices) = compute(feat, prices)