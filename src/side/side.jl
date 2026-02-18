include("crossover.jl")

"""
    (s::AbstractSide)(d::NamedTuple) -> NamedTuple

Compute side signals and merge them into the pipeline `NamedTuple`.

Delegate to `_side_result(s, d)` to obtain a `(side=...,)` tuple,
then merge it into `d`, preserving all upstream keys.

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with keys required by the specific side
implementation (e.g., fast and slow series for [`Crossover`](@ref)).

## Output
Return the input `NamedTuple` merged with:
- `side::Vector{Int8}`: side signals from the side detector.
"""
function (s::AbstractSide)(d::NamedTuple)
    return merge(d, _side_result(s, d))
end

"""
    _fill_sides_generic!(sides, from_idx, condition_func) -> Nothing

Fill `sides[from_idx:end]` by applying `condition_func(i)` at each
index. Use `@inbounds @simd` for vectorised execution.

Mutate `sides` in-place. This is the hot-path kernel for all side
detectors — it must remain zero-allocation and type-stable.
"""
@inline function _fill_sides_generic!(
    sides::AbstractVector{Int8}, from_idx::Int, condition_func::F
) where {F}
    @inbounds @simd for i in from_idx:length(sides)
        sides[i] = condition_func(i)
    end
end
