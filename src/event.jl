struct Event{T<:Tuple} <: AbstractEvent
    conditions::T
    logic::Function # Stores bitwise operator (& / |)
end

function Event(cond_funcs::Function...; match::Symbol=:all)
    op = match === :any ? (|) : (&)
    return Event(cond_funcs, op)
end

function (e::Event)(bars::PriceBars)
    n = length(bars.close)
    indices = _resolve_indices(e, bars, n)
    return (; bars=bars, event_indices=indices)
end

function (e::Event)(d::NamedTuple)
    n = length(d.bars.close)
    indices = _resolve_indices(e, d, n)
    return merge(d, (; event_indices=indices))
end

function _resolve_indices(e::Event, data, n::Int)
    is_and_mode = e.logic === (&)
    mask = is_and_mode ? trues(n) : falses(n)

    for condition in e.conditions
        mask .= e.logic.(mask, condition(data))
    end

    return findall(mask)
end

macro Event(args...)
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
        transformed = _replace_symbols(ex)
        :(d -> $transformed)
    end

    return esc(:(Event($(funcs...); $(kwargs...))))
end

const _BROADCAST_OPS = Set([:!=, :(==), :<, :>, :<=, :>=, :≠, :≤, :≥])

function _replace_symbols(ex)
    if isa(ex, QuoteNode)
        # Found :symbol -> Convert to d.symbol
        return Expr(:., :d, ex)
    elseif isa(ex, Expr)
        # Recursively process sub-expressions (args of functions)
        new_args = map(_replace_symbols, ex.args)
        # Auto-broadcast comparison operators so :side != 0 becomes d.side .!= 0
        if ex.head === :call && length(new_args) >= 2 && _is_broadcast_op(new_args[1])
            return Expr(:., new_args[1], Expr(:tuple, new_args[2:end]...))
        end
        return Expr(ex.head, new_args...)
    else
        return ex
    end
end

_is_broadcast_op(s::Symbol) = s in _BROADCAST_OPS
_is_broadcast_op(::Any) = false