include("ema.jl")
include("cusum.jl")

function (ind::AbstractIndicator)(bars::PriceBars)
    return merge((bars=bars,), _indicator_result(ind, bars.close))
end

function (ind::AbstractIndicator)(d::NamedTuple)
    return merge(d, _indicator_result(ind, d.bars.close))
end
