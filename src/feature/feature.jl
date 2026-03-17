include("ema.jl")
include("cusum.jl")

struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

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

# ── Pipeline operator support for Features ──
>>(f::Features, g::PipeOrFunc) = g ∘ f
>>(f::PipeOrFunc, g::Features) = g ∘ f
>>(f::Features, g::Features) = g ∘ f
>>(data::Any, pipe::Features) = Job(data, pipe)
>>(j::Job, next_step::Features) = Job(j.data, next_step ∘ j.pipeline)
