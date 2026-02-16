function (feat::AbstractFeature)(bars::PriceBars)
    return merge((bars=bars,), _feature_result(feat, bars.close))
end

function (feat::AbstractFeature)(d::NamedTuple)
    return merge(d, _feature_result(feat, d.bars.close))
end

include("ema.jl")
include("cusum.jl")
