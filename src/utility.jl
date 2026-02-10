function _positive_float(n::T) where {T<:Real}
    n > zero(T) || throw(ArgumentError("Value must be > 0, got $n"))
    return n
end

function _natural(n::Int)
    n > 0 || throw(ArgumentError("Value must be a positive integer, got $n"))
    return n
end

function _build_macro_components(context, args)
    exprs = []
    kwargs = []
    for arg in args
        if isa(arg, Expr) && arg.head == :(=)
            push!(kwargs, arg)
        else
            push!(exprs, arg)
        end
    end

    funcs = map(exprs) do ex
        transformed = _replace_symbols(context, ex)
        :(d -> $transformed)
    end

    return funcs, kwargs
end

function _replace_symbols(ctx, ex::Expr)
    return Expr(ex.head, map(x -> _replace_symbols(ctx, x), ex.args)...)
end

# Fallback for non-symbols (numbers, strings, etc.)
_replace_symbols(ctx, ex) = ex