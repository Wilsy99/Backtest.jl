include("ema.jl")
include("cusum.jl")

# ── PrecomputedFeature: wrapper for user-supplied vectors ──────────────────

"""
    PrecomputedFeature{V<:AbstractVector} <: AbstractFeature

Wrapper for pre-computed feature vectors or vectors returned by
external indicator functions. Stores the data and returns it
unchanged when called.

Constructed automatically by [`Features`](@ref) when a value in a
`Symbol => AbstractVector` pair is not an `AbstractFeature` —
not intended for direct use.

# Examples
```julia
# All three produce vectors that get wrapped in PrecomputedFeature:
@Features sma_10 = SMA(10, data.close)     # external library call
@Features atr = calc_atr(bars)              # custom function
@Features rsi = pre_computed_rsi            # existing vector
```
"""
struct PrecomputedFeature{V<:AbstractVector} <: AbstractFeature
    data::V
end

(f::PrecomputedFeature)(::PriceBars) = f.data
(f::PrecomputedFeature)(::AbstractVector) = f.data
(f::PrecomputedFeature)(::NamedTuple) = f.data

# ── FeatureResults: typed container for computed features ──────────────────

"""
    FeatureResults{T<:NamedTuple}

Typed container wrapping the `NamedTuple` of computed feature vectors.
Stored under the `:features` key of the pipeline `NamedTuple`,
accessed transparently via `d.features.ema_10`.

Supports `getproperty`, `haskey`, `keys`, `merge`, and `getindex`
so it behaves like a `NamedTuple` in downstream code while giving
the type system a concrete nominal type to dispatch on.

Constructed automatically by [`Features`](@ref) — not intended for
direct use.
"""
struct FeatureResults{T<:NamedTuple}
    data::T
end

Base.getproperty(fr::FeatureResults, s::Symbol) =
    s === :data ? getfield(fr, :data) : getproperty(getfield(fr, :data), s)
Base.haskey(fr::FeatureResults, s::Symbol) = haskey(getfield(fr, :data), s)
Base.keys(fr::FeatureResults) = keys(getfield(fr, :data))
Base.getindex(fr::FeatureResults, s::Symbol) = getfield(fr, :data)[s]
Base.merge(a::FeatureResults, b::FeatureResults) =
    FeatureResults(merge(getfield(a, :data), getfield(b, :data)))
Base.merge(a::FeatureResults, b::NamedTuple) =
    FeatureResults(merge(getfield(a, :data), b))
Base.merge(a::NamedTuple, b::FeatureResults) =
    FeatureResults(merge(a, getfield(b, :data)))
Base.getindex(fr::FeatureResults, mask::AbstractVector{Bool}) =
    FeatureResults(map(v -> v[mask], getfield(fr, :data)))
Base.view(fr::FeatureResults, mask::AbstractVector{Bool}) =
    FeatureResults(map(v -> view(v, mask), getfield(fr, :data)))
Base.hasproperty(fr::FeatureResults, s::Symbol) = haskey(fr, s)
Base.propertynames(fr::FeatureResults) = keys(fr)
Base.length(fr::FeatureResults) = length(getfield(fr, :data))

# ── Feature: type-stable named wrapper ──────────────────────────────────────

"""
    Feature{Name, F<:AbstractFeature}

Type-stable wrapper that pairs a compile-time `Symbol` name with an
[`AbstractFeature`](@ref) instance. The name is a type parameter,
so `NamedTuple{(Name,)}` constructions are fully inferrable.

Constructed automatically by [`Features`](@ref) from
`Symbol => AbstractFeature` pairs — not intended for direct use.
"""
struct Feature{Name, F<:AbstractFeature}
    feat::F
    function Feature{Name}(feat::F) where {Name, F<:AbstractFeature}
        return new{Name, F}(feat)
    end
end

function (op::Feature{Name})(bars::PriceBars) where {Name}
    result = op.feat(bars)
    return NamedTuple{(Name,)}((result,))
end

# ── Features: named feature collection ──────────────────────────────────────

"""
    Features{T<:Tuple}

Named feature collection that computes multiple features in a single
pipeline step and nests results under a `:features` key.

Replace individual feature calls with explicit
`Symbol => AbstractFeature` pairs, or supply pre-computed vectors
and external indicator results directly:

```julia
# Built-in features
bars |> Features(:ema_10 => EMA(10), :ema_20 => EMA(20), :cusum => CUSUM(1))

# External / custom features (vectors passed directly)
@Features sma_10 = SMA(10, bars.close) atr = calc_atr(bars) rsi = pre_computed_rsi
```

Any value that is not an `AbstractFeature` is wrapped in a
[`PrecomputedFeature`](@ref) automatically.

Results are nested under a `:features` key in the pipeline
`NamedTuple`, giving downstream stages a clean namespace for feature
vectors. Feature names are user-supplied via the `Pair` syntax —
no automatic naming.

# Type Parameters
- `T<:Tuple`: tuple of `Feature{Name, F}` instances.

# Fields
- `operations::T`: tuple of `Feature` instances
    defining feature names and their computations.

# Constructors
    Features(ops::Pair{Symbol, <:AbstractFeature}...)
    Features(ops::Pair{Symbol}...)

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

All features are computed back-to-back on the same input data via
a `@generated` function that unrolls the tuple at compile time.
Because feature names are type parameters on [`Feature`](@ref),
the `NamedTuple` construction in each per-feature call is fully
type-stable — the compiler knows every return type at compile time.
The data stays hot in L1/L2 cache for subsequent feature
computations. A single `merge()` of per-feature results replaces
`N` sequential merges into the growing pipeline `NamedTuple`.

## Pipeline Data Flow

### Input
- `bars::PriceBars`: raw price data (direct call).
- `NamedTuple` with at least `bars::PriceBars` (pipeline call).

### Output
- **PriceBars input**: `(bars=bars, features=FeatureResults(...))`.
- **NamedTuple input**: input merged with
    `(features=FeatureResults(...),)`.

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
        wrapped = map(p -> Feature{p.first}(p.second), ops)
        return new{typeof(wrapped)}(wrapped)
    end
    function Features(ops::Pair{Symbol}...)
        wrapped = map(ops) do p
            val = p.second
            feat = val isa AbstractFeature ? val : PrecomputedFeature(val)
            Feature{p.first}(feat)
        end
        return new{typeof(wrapped)}(wrapped)
    end
    function Features(ops::Feature...)
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
- `(bars=bars, features=FeatureResults(...))`.
"""
function (feats::Features)(d::NamedTuple)
    feats_results = feats(d.bars)
    return _merge_features(d, feats_results)
end

@generated function _merge_features(d::NamedTuple{K}, feats_results) where {K}
    if :features in K
        :(merge(d, (features=merge(d.features, feats_results.features),)))
    else
        :(merge(d, feats_results))
    end
end

"""
    (feats::Features{T})(bars::PriceBars) where {T<:Tuple} -> NamedTuple

`@generated` function that unrolls the `Features` tuple at compile
time, calling each `Feature{Name, F}` functor independently and
merging results in a single `merge()` call.

Because each `Feature` carries its name as a type parameter, every
per-feature call is type-stable and the generated code is fully
unrolled for the concrete tuple type, eliminating all runtime
dispatch.
"""
@generated function (feats::Features{T})(bars::PriceBars) where {T<:Tuple}
    n = fieldcount(T)
    exprs = [:(feats.operations[$i](bars)) for i in 1:n]
    return :((bars=bars, features=FeatureResults(merge($(exprs...)))))
end

# ── @Features macro ─────────────────────────────────────────────────────────

"""
    @Features name = Feature(...) [name2 = Feature2(...) ...]

Construct a [`Features`](@ref) collection using assignment syntax.

Each argument is a `name = expr` expression. The left-hand side
becomes the `Symbol` key. The right-hand side can be an
[`AbstractFeature`](@ref) instance or any expression that evaluates
to an `AbstractVector` (external indicator calls, pre-computed
vectors, etc.). Non-`AbstractFeature` values are automatically
wrapped in [`PrecomputedFeature`](@ref).

All four syntactic forms are accepted:

    @Features ema_10 = EMA(10)           # preferred (built-in)
    @Features ema_10 .= EMA(10)          # broadcast-assign style
    @Features :ema_10 = EMA(10)          # quoted symbol
    @Features :ema_10 => EMA(10)         # pair syntax

Custom / external features:

    @Features sma_10 = SMA(10, data.close) atr = calc_atr(bars) rsi = pre_calced_rsi

# Examples
```jldoctest
julia> using Backtest

julia> f = @Features ema_10 = EMA(10) ema_20 = EMA(20);

julia> f isa Features
true
```

Equivalent to:
```julia
Features(:ema_10 => EMA(10), :ema_20 => EMA(20))
```

# See also
- [`Features`](@ref): the underlying type.
- [`PrecomputedFeature`](@ref): wrapper for external vectors.
- [`@Event`](@ref): similar DSL macro for event construction.
"""
macro Features(args...)
    feature_exprs = Expr[]
    for arg in args
        sym, feat = _parse_feature_arg(arg)
        push!(feature_exprs, :(_wrap_feature(Val($(QuoteNode(sym))), $(esc(feat)))))
    end
    return :(Features($(feature_exprs...)))
end

"""
    _wrap_feature(::Val{Name}, value) -> Feature{Name}

Wrap a value into a `Feature{Name}`. If the value is already an
`AbstractFeature`, wrap directly. Otherwise (e.g. an
`AbstractVector`), wrap in a [`PrecomputedFeature`](@ref) first.
"""
_wrap_feature(::Val{Name}, feat::AbstractFeature) where {Name} = Feature{Name}(feat)
_wrap_feature(::Val{Name}, data::AbstractVector) where {Name} = Feature{Name}(PrecomputedFeature(data))

"""
    _parse_feature_arg(arg) -> (name::Symbol, feat)

Extract a `(Symbol, feature_expr)` pair from a single `@Features`
argument. Accept four forms:

- `name = Feat(...)` — assignment (`head === :(=)`)
- `name .= Feat(...)` — broadcast-assign (`head === :.=`)
- `:name = Feat(...)` — quoted symbol on LHS (`args[1]` is a
    `QuoteNode`)
- `:name => Feat(...)` — pair literal (`head === :call`,
    `args[1] === :(=>)`)
"""
function _parse_feature_arg(arg)
    if arg isa Expr && (arg.head === :(=) || arg.head === :.=)
        lhs = arg.args[1]
        feat = arg.args[2]
        # Unwrap QuoteNode for :name = Feat(...) form
        sym = lhs isa QuoteNode ? lhs.value : lhs
        sym isa Symbol || throw(ArgumentError(
            "@Features: left-hand side must be a name, got: $lhs"
        ))
        return (sym, feat)
    elseif arg isa Expr && arg.head === :call && arg.args[1] === :(=>)
        lhs = arg.args[2]
        feat = arg.args[3]
        # :name => Feat(...) parses with lhs as QuoteNode
        sym = lhs isa QuoteNode ? lhs.value : lhs
        sym isa Symbol || throw(ArgumentError(
            "@Features: left-hand side of => must be a :symbol, got: $lhs"
        ))
        return (sym, feat)
    else
        throw(ArgumentError(
            "@Features expects `name = Feature(...)` syntax, got: $arg"
        ))
    end
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
