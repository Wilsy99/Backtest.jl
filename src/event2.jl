struct Event{F}
    func::F
end

#(d, i) -> d.features.ema_10[i] > d.features.cusum[i]

function (event::Event)(d::NamedTuple)
    event_indices = Vector{Int}(undef, 1)
    @inbounds for i in eachindex(d.bars)
        ifelse(event.func(d, i), push!(event_indices, i), continue)
    end
    return event_indices
end

macro Event(ex)
    max_lag = Ref(0)
    body = _rewrite_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Event((d, i) -> $body, $warmup)))
end