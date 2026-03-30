function _positive_float(n::T) where {T<:Real}
    n > zero(T) || throw(ArgumentError("Value must be > 0, got $n"))
    return n
end

function _natural(n::Int)
    n > 0 || throw(ArgumentError("Value must be a positive integer, got $n"))
    return n
end

function _nonnegative_float(n::T) where {T<:Real}
    n >= zero(T) || throw(ArgumentError("Value must be >= 0, got $n"))
    return n
end

function _ternary(n::Int)
    n in (-1, 0, 1) || throw(ArgumentError("Value must be -1, 0, or 1, got $n"))
    return n
end

function _bipolar(n::Int)
    abs(n) == 1 || throw(ArgumentError("Value must be 1 or -1, got $n"))
    return n
end

