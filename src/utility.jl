function _positive_float(n::T) where {T<:Real}
    n > zero(T) || throw(ArgumentError("Value must be > 0, got $n"))
    return n
end

function _natural(n::Int)
    n > 0 || throw(ArgumentError("Value must be a positive integer, got $n"))
    return n
end

"""
Compact finished events to the front of each vector in-place.
Returns the count of kept elements.
"""
function _compact!(labels, vecs::Vararg{AbstractVector})
    n = 0
    @inbounds for i in eachindex(labels)
        labels[i] == Int8(-99) && continue
        n += 1
        if n != i
            labels[n] = labels[i]
            for v in vecs
                v[n] = v[i]
            end
        end
    end
    return n
end