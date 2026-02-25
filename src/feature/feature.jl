include("ema.jl")
include("cusum.jl")
include("feature_union.jl")

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
    return merge((bars=bars,), _feature_result(feat, series))
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
    return merge(d, _feature_result(feat, series))
end

"""
    _feature_field(feat::AbstractFeature) -> Symbol

Return the field name of the target series for `feat`. Defaults to
`:close`. Override in subtypes to compute features on other series
(e.g., `:volume`, `:high`).
"""
_feature_field(::AbstractFeature) = :close