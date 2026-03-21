# ── Feature Wrappers ──────────────────────────────────────────────────────────
#
# Thin adapters that let users pass plain functions or pre-computed vectors
# into the Features pipeline without subtyping AbstractFeature.

"""
    FunctionFeature{F} <: AbstractFeature

Wraps an arbitrary callable `f(bars) -> Vector` as an [`AbstractFeature`](@ref).

Constructed automatically by [`Features`](@ref) when a `Function` is passed
as the second element of a `Symbol => value` pair — not intended for direct use.

# Examples
```julia
Features(:my_rsi => bars -> my_rsi(bars.close, 14))
```
"""
struct FunctionFeature{F} <: AbstractFeature
    f::F
end

(feat::FunctionFeature)(bars) = feat.f(bars)

"""
    StaticFeature{V<:AbstractVector} <: AbstractFeature

Wraps a pre-computed vector as an [`AbstractFeature`](@ref), returning
it unchanged regardless of input.

Constructed automatically by [`Features`](@ref) when an `AbstractVector`
is passed as the second element of a `Symbol => value` pair — not intended
for direct use.

# Examples
```julia
vix = load_vix_data()
Features(:vix => vix, :ema_10 => EMA(10))
```
"""
struct StaticFeature{V<:AbstractVector} <: AbstractFeature
    values::V
end

(feat::StaticFeature)(::Any) = feat.values

# ── wrap_feature: dispatch-based conversion ──────────────────────────────────

"""
    wrap_feature(x) -> AbstractFeature

Convert `x` into an [`AbstractFeature`](@ref) via dispatch.

- `AbstractFeature` → returned as-is.
- `Function` → wrapped in [`FunctionFeature`](@ref).
- `AbstractVector` → wrapped in [`StaticFeature`](@ref).

Users can extend this with additional methods to plug in custom types.
"""
wrap_feature(feat::AbstractFeature) = feat
wrap_feature(f::Function) = FunctionFeature(f)
wrap_feature(v::AbstractVector) = StaticFeature(v)
