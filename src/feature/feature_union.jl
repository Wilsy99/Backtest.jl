"""
    FeatureUnion{F<:Tuple} <: AbstractFeature

Fused feature combinator that computes multiple features in a single
pipeline step, reducing intermediate `NamedTuple` merge overhead.

Instead of chaining `EMA(10, 20) >> CUSUM(1.0)` (two pipeline stages,
two merges into the growing pipeline tuple), `FeatureUnion(EMA(10, 20),
CUSUM(1.0))` computes both features and merges their results in one
step.

# Type Parameters
- `F<:Tuple`: tuple of [`AbstractFeature`](@ref) instances.

# Constructors
    FeatureUnion(features::AbstractFeature...)

# Throws
- `ArgumentError`: if fewer than two features are provided.

# Examples
```jldoctest
julia> using Backtest

julia> fu = FeatureUnion(EMA(10, 20), CUSUM(1.0));

julia> fu isa AbstractFeature
true
```

# See also
- [`EMA`](@ref): exponential moving average feature.
- [`CUSUM`](@ref): cumulative sum filter feature.

# Extended help

## Performance

For `N` features the sequential pipeline performs `N` merges into an
ever-growing pipeline `NamedTuple`.  `FeatureUnion` performs one merge
of the small per-feature results, then a single merge into the pipeline
tuple — total pipeline merge overhead is constant regardless of `N`.

Because features are computed back-to-back on the same `prices` vector,
the data stays hot in L1/L2 cache for the second (and subsequent)
feature computations.

## Pipeline Usage

```julia
# Single pipeline step instead of two:
bars |> FeatureUnion(EMA(10, 20), CUSUM(1.0)) |> Crossover(...) |> ...

# Works with the >> operator:
job = bars >> FeatureUnion(EMA(10, 20), CUSUM(1.0)) >> side >> event >> label
```

## Callable Interface

`FeatureUnion` inherits the standard [`AbstractFeature`](@ref) callable
interface.  When called with [`PriceBars`](@ref) or a `NamedTuple`
from a previous pipeline stage, it computes all contained features on
`bars.close` and merges their results into the pipeline data.

## Pipeline Data Flow

### Input
- `bars::PriceBars` or a `NamedTuple` with at least `bars::PriceBars`.

### Output
Return a `NamedTuple` with `bars` plus all keys from every contained
feature's [`_feature_result`](@ref) (e.g., `:ema_10`, `:ema_20`,
`:cusum`).
"""
struct FeatureUnion{F<:Tuple} <: AbstractFeature
    features::F
    function FeatureUnion(features::AbstractFeature...)
        length(features) >= 2 ||
            throw(ArgumentError("FeatureUnion requires at least 2 features"))
        return new{typeof(features)}(features)
    end
end

"""
    _feature_result(fu::FeatureUnion{F}, prices) -> NamedTuple

`@generated` function that computes all contained features on the same
`prices` vector, then merges their individual result `NamedTuple`s in a
single `merge` call.

Each feature's [`_feature_result`](@ref) is called independently
(preserving the per-feature optimised kernels) and the results are
combined at the end.  The generated code is fully unrolled at compile
time for the concrete feature tuple type.
"""
@generated function _feature_result(
    fu::FeatureUnion{F}, prices::AbstractVector{T}
) where {F,T<:AbstractFloat}
    n = length(F.parameters)
    syms = [Symbol(:_r, i) for i in 1:n]
    stmts = [:($(syms[i]) = _feature_result(fu.features[$i], prices)) for i in 1:n]
    return quote
        $(stmts...)
        merge($(syms...))
    end
end
