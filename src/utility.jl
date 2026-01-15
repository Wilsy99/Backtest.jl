function _natural(n)
    return n isa Integer && n > 0 ? n : throw(ArgumentError("must be a positive integer"))
end
