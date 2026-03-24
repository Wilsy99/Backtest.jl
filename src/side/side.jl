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

abstract type AbstractDirectionFunc end

struct Long{F} <: AbstractDirectionFunc
    func::F
end
(long::Long)() = Int8(1)

struct Short{F} <: AbstractDirectionFunc
    func::F
end
(short::Short)() = Int8(-1)

struct Side{T<:Tuple}
    directions::T
end
Side(args...) = Side(args)

function (side::Side)(d::NamedTuple)
    sides = Vector{Int8}(undef, length(d.bars))
    @inbounds @simd for i in eachindex(d.bars)
        sides[i] = _check_side(side.directions, d, i)
    end

    return sides
end

_check_side(::Tuple{}, d::NamedTuple, i::Int) = Int8(0)

#Recursive Case: Evaluates EVERYTHING to keep the pipeline flat.
@inline function _check_side(directions::Tuple, d::NamedTuple, i::Int)
    dir = first(directions)

    is_match = dir.func(d, i)

    rest_val = _check_side_branchless(Base.tail(directions), d, i)

    return ifelse(is_match, dir(), rest_val)
end