include("ema.jl")
include("cusum.jl")

# ── Features: named feature collection ──────────────────────────────────────

"""
    Features{T<:Tuple}

Named feature collection that computes multiple features in a single
pipeline step and nests results under a `:features` key.

Replace individual feature calls with explicit
`Symbol => AbstractFeature` pairs:

```julia
bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1))
```

Results are nested under a `:features` key in the pipeline
`NamedTuple`, giving downstream stages a clean namespace for feature
vectors. Feature names are user-supplied via the `Pair` syntax —
no automatic naming.

# Type Parameters
- `T<:Tuple`: tuple of `Pair{Symbol, <:AbstractFeature}` instances.

# Fields
- `operations::T`: tuple of `Symbol => AbstractFeature` pairs
    defining feature names and their computations.

# Constructors
    Features(ops::Pair{Symbol, <:AbstractFeature}...)

# Examples
```jldoctest
julia> using Backtest

julia> f = Features(:ema_10 => EMA(10), :ema_20 => EMA(20));

julia> f isa Features
true
```

# See also
- [`EMA`](@ref): exponential moving average feature.
- [`CUSUM`](@ref): cumulative sum filter feature.
- [`compute`](@ref): standalone computation function.

# Extended help

## Performance

All features are computed back-to-back on the same price data via
a `@generated` function that unrolls the pair tuple at compile time.
The data stays hot in L1/L2 cache for subsequent feature
computations. A single `merge()` of per-feature results replaces
`N` sequential merges into the growing pipeline `NamedTuple`.

## Pipeline Data Flow

### Input
- `bars::PriceBars`: raw price data (direct call).
- `NamedTuple` with at least `bars::PriceBars` (pipeline call).

### Output
- **PriceBars input**: `(bars=bars, features=(name1=vec1, ...))`.
- **NamedTuple input**: input merged with
    `(features=(name1=vec1, ...),)`.

## Callable Interface

`Features` instances are callable:

```julia
bars = get_data("AAPL")
result = bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20))
result.features.ema_10  # access the EMA(10) result
```
"""
struct Features{T<:Tuple}
    operations::T
    function Features(ops::Pair{Symbol,<:AbstractFeature}...)
        return new{typeof(ops)}(ops)
    end
end

"""
    (feats::Features)(d::NamedTuple) -> NamedTuple
    (feats::Features)(bars::PriceBars) -> NamedTuple

Compute all features and return pipeline-ready results.

When called with a `NamedTuple`, compute features from `d.bars` and
merge `(features=(...),)` into the input. When called with
[`PriceBars`](@ref), return `(bars=bars, features=(...))`.

# Pipeline Data Flow

## Input
- `NamedTuple` with at least `bars::PriceBars`.
- `PriceBars` directly.

## Output
- `(bars=bars, features=(name1=vec1, name2=vec2, ...))`.
"""
function (feats::Features)(d::NamedTuple)
    feats_results = feats(d.bars)
    return merge(d, feats_results)
end

"""
    (feats::Features{T})(bars::PriceBars) where {T<:Tuple} -> NamedTuple

`@generated` function that unrolls the `Features` pair tuple at
compile time, calling each feature's `Pair` functor independently
and merging results in a single `merge()` call.

The generated code is fully unrolled for the concrete pair tuple
type, eliminating all runtime dispatch.
"""
@generated function (feats::Features{T})(bars::PriceBars) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(feats.operations[$i](bars)) for i in 1:n]
    return :((bars=bars, features=merge($(exprs...))))
end

function (op::Pair{Symbol,<:AbstractFeature})(bars::PriceBars)
    name = op.first
    feat = op.second
    result = feat(bars)
    return NamedTuple{(name,)}((result,))
end

# ── compute wrappers ────────────────────────────────────────────────────────

"""
    compute(feats::Features, x::Union{NamedTuple,PriceBars}) -> NamedTuple
    compute(feat::AbstractFeature, x::Union{NamedTuple,PriceBars})

Delegate to the callable interface of [`Features`](@ref) or an
[`AbstractFeature`](@ref) subtype.
"""
compute(feats::Features, x::Union{NamedTuple,PriceBars}) = feats(x)
compute(feat::AbstractFeature, x::Union{NamedTuple,PriceBars}) = feat(x)

# ── Pipeline operator support for Features ──────────────────────────────────
# Features is not a subtype of AbstractFeature, so it needs its own >>
# overloads to integrate with the pipeline operator defined in types.jl.

>>(f::Features, g::PipeOrFunc) = g ∘ f
>>(f::PipeOrFunc, g::Features) = g ∘ f
>>(f::Features, g::Features) = g ∘ f
>>(data::Any, pipe::Features) = Job(data, pipe)
>>(j::Job, next_step::Features) = Job(j.data, next_step ∘ j.pipeline)
