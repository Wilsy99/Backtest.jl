# new feature.jl
struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

# only features functor returns named tuple and only allows named tuple or price bars as input
function (feats::Features)(d::NamedTuple)
    feats_results = compute(feats, d.bars)
    return merge(d, (features=feats_results,))
end

function (feats::Features)(bars::PriceBars)
    feats_results = compute(feats, bars)
    return (bars=bars, features=feats_results)
end

@generated function compute(
    feats::Features{T}, x::Union{PriceBars,NamedTuple}
) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(compute(feats.operations[$i], x)) for i in 1:n]
    return :(merge($(exprs...)))
end

function compute(op::Pair{Symbol,<:AbstractFeature}, x::Union{PriceBars,NamedTuple})
    feat = op.second
    result = compute(feat, x)
    return NamedTuple{(op.first,)}((result,))
end

#Each feature script eg ema.jl defines its own compute functions in its script and only returns vector
function compute(feat::EMA, d::NamedTuple)
    return compute(feat, d.bars)
end

function compute(feat::EMA, bars::PriceBars)
    return compute(feat, getproperty(bars, feat.field))
end

function compute(feat::EMA, x::AbstractVector{T}) where {(T <: Real)}
    return _compute_ema(x, feat.period)
end

#each feature functor only returns vector and is just a wrapper
(ema::EMA)(data) = compute(ema, data)
(cusum::CUSUM)(data) = CUSUM(data)
