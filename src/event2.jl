struct Event{F}
    func::F
    warmup::Int
end
Event(func) = Event(func, 0)

#(d, i) -> d.features.ema_10[i] > d.features.cusum[i]

function (event::Event)(d::NamedTuple)
    event_indices = int[]
    @inbounds for i in eachindex(d.bars)
        if event.func(d, i)
            push!(event_indices, i)
        end
    end
    return merge(d, (; event=event_indices))
end

macro Event(ex)
    max_lag = Ref(0)
    body = _rewrite_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Event((d, i) -> $body, $warmup)))
end