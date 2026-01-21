function _positive_float(n::Real)
    n > 0 || throw(ArgumentError("multiplier must be > 0, got $n"))
    return Float64(n)
end

function _natural(n::Integer)
    n > 0 || throw(ArgumentError("span must be a positive integer, got $n"))
    return Int(n)
end