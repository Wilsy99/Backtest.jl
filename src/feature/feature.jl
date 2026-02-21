include("ema.jl")
include("cusum.jl")
include("feature_union.jl")

"""
    (feat::AbstractFeature)(bars::PriceBars) -> NamedTuple

Compute the feature on `bars.close` and return a `NamedTuple`
containing `bars` and the named feature results.

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
    return merge((bars=bars,), _feature_result(feat, bars.close))
end

"""
    (feat::AbstractFeature)(d::NamedTuple) -> NamedTuple

Compute the feature on `d.bars.close` and merge the named results
into the existing pipeline `NamedTuple`, preserving all upstream
keys.

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with at least:
- `bars::PriceBars`: the price data.

## Output
Return the input `NamedTuple` merged with feature-specific keys
from [`_feature_result`](@ref).
"""
function (feat::AbstractFeature)(d::NamedTuple)
    return merge(d, _feature_result(feat, d.bars.close))
end