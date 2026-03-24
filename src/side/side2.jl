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

    rest_val = _check_side(Base.tail(directions), d, i)

    return ifelse(is_match, dir(), rest_val)
end