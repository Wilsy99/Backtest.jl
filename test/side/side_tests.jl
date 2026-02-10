include("crossover.jl")

function (s::AbstractSide)(d::NamedTuple)
    return merge(d, _side_result(s, d))
end

@inline function _fill_sides_generic!(
    sides::AbstractVector{Int8}, from_idx::Int, condition_func::F
) where {F<:Function}
    @inbounds @simd for i in from_idx:length(sides)
        sides[i] = condition_func(i)
    end
end
