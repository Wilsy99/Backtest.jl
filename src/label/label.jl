include("barrier.jl")
inclide("execution.jl")

struct Label{B<:Tuple,E1<:ExecutionBasis,E2<:ExecutionBasis,NT<:NamedTuple}
    barriers::B
    entry_basis::E1
    exit_basis::E2
    drop_unfinished::Bool
    barrier_args::NT
end

function Label(
    barriers::AbstractBarrier...;
    entry_basis::ExecutionBasis=NextOpen(),
    exit_basis::ExecutionBasis=Immediate(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
)
    return Label(barriers, entry_basis, exit_basis, drop_unfinished, barrier_args)
end

struct LabelResults{D<:TimeType,T<:AbstractFloat}
    t₀::Vector{D}
    t₁::Vector{D}
    label::Vector{Int8}
    ret::Vector{T}
    log_ret::Vector{T}

    function LabelResults(
        t₀::Vector{D},
        t₁::Vector{D},
        labels::Vector{Int8},
        rets::Vector{T},
        log_rets::Vector{T};
        drop_unfinished::Bool=true,
    ) where {D<:TimeType,T<:AbstractFloat}
        if drop_unfinished
            mask = labels .!= Int8(-99)
            return new{D,T}(t₀[mask], t₁[mask], labels[mask], rets[mask], log_rets[mask])
        else
            return new{D,T}(t₀, t₁, labels, rets, log_rets)
        end
    end
end

function (lab::Label)(d::NamedTuple)
    results = calculate_label(
        d.event_indices,
        d.bars,
        lab.barriers;
        entry_basis=lab.entry_basis,
        exit_basis=lab.exit_basis,
        drop_unfinished=lab.drop_unfinished,
        barrier_args=lab.barrier_args,
    )

    return merge(d, (labels = results))
end

function calculate_label(
    event_indices::AbstractVector{Int},
    timestamps::Vector{<:TimeType},
    opens::AbstractVector{T},
    highs::AbstractVector{T},
    lows::AbstractVector{T},
    closes::AbstractVector{T},
    volumes::AbstractVector{T},
    barriers::Tuple;
    entry_basis::ExecutionBasis=NextOpen(),
    exit_basis::ExecutionBasis=Immediate(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
) where {T<:AbstractFloat}
    price_bars = PriceBars(opens, highs, lows, closes, volumes, timestamps, TimeBar())
    return calculate_label(
        event_indices,
        price_bars,
        barriers;
        entry_basis,
        exit_basis,
        drop_unfinished,
        barrier_args,
    )
end

function calculate_label(
    event_indices::AbstractVector{Int},
    price_bars::PriceBars,
    barriers::Tuple;
    entry_basis::ExecutionBasis=NextOpen(),
    exit_basis::ExecutionBasis=Immediate(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
)
    D = eltype(price_bars.timestamp)
    T = eltype(price_bars.close)

    n_events = length(event_indices)
    n_prices = length(price_bars)

    full_args = merge(barrier_args, (; bars=price_bars))

    entry_timestamps = Vector{D}(undef, n_events)
    exit_timestamps = Vector{D}(undef, n_events)
    labels = fill(Int8(-99), n_events)
    rets = Vector{T}(undef, n_events)
    log_rets = Vector{T}(undef, n_events)

    entry_adj = _get_idx_adj(entry_basis)
    exit_adj = _get_idx_adj(exit_basis)

    @inbounds for i in 1:n_events
        entry_idx = event_indices[i] + entry_adj

        if entry_idx < 1 || entry_idx > n_prices
            continue
        end

        entry_ts = price_bars.timestamp[entry_idx]
        entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)
        entry_timestamps[i] = entry_ts

        hit_occurred = false

        for j in (entry_idx + 1):n_prices
            for barrier in barriers
                level = barrier_level(barrier, j, entry_price, entry_ts, full_args)

                if barrier_hit(
                    barrier,
                    level,
                    price_bars.low[j],
                    price_bars.high[j],
                    price_bars.timestamp[j],
                )
                    exit_idx = j + exit_adj

                    if exit_idx > n_prices
                        hit_occurred = true
                        break
                    end

                    exit_price = _get_price(exit_basis, level, exit_idx, full_args)

                    exit_timestamps[i] = price_bars.timestamp[exit_idx]
                    labels[i] = barrier.label
                    raw_ret = (exit_price / entry_price) - one(T)
                    rets[i] = raw_ret
                    log_rets[i] = log1p(raw_ret)

                    hit_occurred = true
                    break
                end
            end

            if hit_occurred
                break
            end
        end
    end

    return LabelResults(
        entry_timestamps, exit_timestamps, labels, rets, log_rets; drop_unfinished
    )
end