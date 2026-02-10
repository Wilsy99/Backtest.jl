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
        res = condition(data)

        if res isa Bool
            @warn "Event condition returned a single Bool instead of a vector. " *
                "This usually means you forgot a dot (.) for broadcasting (e.g., use .!= instead of !=)."
        end

        mask .= e.logic.(mask, res)
    end

    return findall(mask)
end

struct EventContext end

macro Event(args...)
    funcs, kwargs = _build_macro_components(EventContext(), args)
    return esc(:(Event($(funcs...); $(kwargs...))))
end

function _replace_symbols(::EventContext, ex::QuoteNode)
    return Expr(:., :d, ex)
end