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

Compute the feature on a raw price vector and return a `NamedTuple`
with the named feature result.

# Arguments
- `prices::AbstractVector{T}`: the price series.

# Returns
- `NamedTuple`: a single-key `NamedTuple` with the feature result
  keyed by [`_feature_names`](@ref) (e.g., `(ema_10=...,)`).

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> result = EMA(3)(prices);

julia> haskey(result, :ema_3)
true
```
"""
function (feat::AbstractFeature)(
    prices::AbstractVector{T}
) where {T<:AbstractFloat}
    result = _feature_result(feat, prices)
    return _wrap_result(feat, result)
end

"""
    _feature_field(feat::AbstractFeature) -> Symbol

Return the field name of the target series for `feat`. Defaults to
`:close`. Override in subtypes to compute features on other series
(e.g., `:volume`, `:high`).
"""
_feature_field(::AbstractFeature) = :close