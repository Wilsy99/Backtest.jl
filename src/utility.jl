function _positive_float(n::T) where {T<:Real}
    n > zero(T) || throw(ArgumentError("Value must be > 0, got $n"))
    return n
end

function _natural(n::Int)
    n > 0 || throw(ArgumentError("Value must be a positive integer, got $n"))
    return n
end