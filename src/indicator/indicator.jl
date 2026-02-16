# ── Abstract indicator callable interface ──

"""
    (ind::AbstractIndicator)(bars::PriceBars) -> NamedTuple
    (ind::AbstractIndicator)(d::NamedTuple) -> NamedTuple

Call an indicator as a pipeline stage.

When called with [`PriceBars`](@ref), compute the indicator on
`bars.close` and return `(bars=bars, <indicator_keys>...)`. When
called with a `NamedTuple` from a previous pipeline stage, compute
the indicator on `d.bars.close` and merge the result into `d`.

# Pipeline Data Flow

## Input
- `bars::PriceBars`: price data (first form).
- `d::NamedTuple`: must contain `bars::PriceBars` (second form).

## Output
Return the input merged with indicator-specific keys (e.g.,
`:ema_10`, `:ema_50` for [`EMA`](@ref), `:cusum` for
[`CUSUM`](@ref)). All upstream keys are preserved.
"""
function (ind::AbstractIndicator)(bars::PriceBars)
    return merge((bars=bars,), _indicator_result(ind, bars.close))
end

function (ind::AbstractIndicator)(d::NamedTuple)
    return merge(d, _indicator_result(ind, d.bars.close))
end

include("ema.jl")
include("cusum.jl")