struct Event{F} <: AbstractEvent
    func::F
    warmup::Int
end
Event(func) = Event(func, 0)

function (event::Event)(d::NamedTuple)
    event_indices = Int[]
    @inbounds for i in eachindex(d.bars)
        if event.func(d, i)
            push!(event_indices, i)
        end
    end
    return merge(d, (; event_indices=event_indices))
end

macro Event(ex)
    max_lag = Ref(0)
    body = _rewrite_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Event((d, i) -> $body, $warmup)))
end