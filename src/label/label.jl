include("execution.jl")
include("barrier.jl")

struct Label{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple} <: AbstractLabel
    barriers::B
    entry_basis::E
    drop_unfinished::Bool
    barrier_args::NT
end

function Label(
    barriers::AbstractBarrier...;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
)
    return Label(barriers, entry_basis, drop_unfinished, barrier_args)
end

struct Label!{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple} <: AbstractLabel
    barriers::B
    entry_basis::E
    drop_unfinished::Bool
    barrier_args::NT
end

function Label!(
    barriers::AbstractBarrier...;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
)
    return Label!(barriers, entry_basis, drop_unfinished, barrier_args)
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
        drop_unfinished=lab.drop_unfinished,
        barrier_args=merge(d, lab.barrier_args),
    )

    return merge(d, (; labels=results))
end

function (lab::Label!)(d::NamedTuple)
    return calculate_label(
        d.event_indices,
        d.bars,
        lab.barriers;
        entry_basis=lab.entry_basis,
        drop_unfinished=lab.drop_unfinished,
        barrier_args=merge(d, lab.barrier_args),
    )
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
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
) where {T<:AbstractFloat}
    price_bars = PriceBars(opens, highs, lows, closes, volumes, timestamps, TimeBar())
    return calculate_label(
        event_indices, price_bars, barriers; entry_basis, drop_unfinished, barrier_args
    )
end

function calculate_label(
    event_indices::AbstractVector{Int},
    price_bars::PriceBars,
    barriers::Tuple;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    barrier_args::NamedTuple=(;),
)
    _warn_barrier_ordering(barriers)

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

    @inbounds @threads for i in 1:n_events
        entry_idx = event_indices[i] + entry_adj

        if entry_idx < 1 || entry_idx > n_prices
            continue
        end

        entry_ts = price_bars.timestamp[entry_idx]
        entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)
        entry_timestamps[i] = entry_ts

        for j in (entry_idx + 1):n_prices
            loop_args = (; full_args..., idx=j, entry_price=entry_price, entry_ts=entry_ts)

            hit = _check_and_process_barriers!(
                i,
                j,
                barriers,
                loop_args,
                price_bars,
                entry_price,
                full_args,
                n_prices,
                exit_timestamps,
                labels,
                rets,
                log_rets,
            )

            if hit
                break
            end
        end
    end

    return LabelResults(
        entry_timestamps, exit_timestamps, labels, rets, log_rets; drop_unfinished
    )
end

function _warn_barrier_ordering(barriers::Tuple)
    for i in 1:(length(barriers) - 1)
        a = barriers[i]
        b = barriers[i + 1]
        if _temporal_priority(a.exit_basis) > _temporal_priority(b.exit_basis)
            @warn "Barrier $(typeof(a).name.name) with $(typeof(a.exit_basis).name.name) " *
                "exit basis is listed before $(typeof(b).name.name) with " *
                "$(typeof(b.exit_basis).name.name) exit basis. The first-listed " *
                "barrier takes priority when both trigger on the same bar."
        end
    end
end

# ── Barrier checking: recursive tuple unrolling ──

# Entry point — computes open_price once
@inline function _check_and_process_barriers!(
    i,
    j,
    barriers::Tuple,
    loop_args,
    price_bars,
    entry_price,
    full_args,
    n_prices,
    exit_timestamps,
    labels,
    rets,
    log_rets,
)
    open_price = price_bars.open[j]
    return _check_barrier_recursive!(
        i,
        j,
        barriers,
        open_price,
        loop_args,
        price_bars,
        entry_price,
        full_args,
        n_prices,
        exit_timestamps,
        labels,
        rets,
        log_rets,
    )
end

# Base case — no barriers left
@inline function _check_barrier_recursive!(
    i,
    j,
    ::Tuple{},
    open_price,
    loop_args,
    price_bars,
    entry_price,
    full_args,
    n_prices,
    exit_timestamps,
    labels,
    rets,
    log_rets,
)
    return false
end

# Recursive case — check first barrier, then recurse on tail
@inline function _check_barrier_recursive!(
    i,
    j,
    barriers::Tuple,
    open_price,
    loop_args,
    price_bars,
    entry_price,
    full_args,
    n_prices,
    exit_timestamps,
    labels,
    rets,
    log_rets,
)
    barrier = first(barriers)
    level = barrier_level(barrier, loop_args)

    if gap_hit(barrier, level, open_price)
        _record_exit!(
            i,
            j,
            barrier,
            open_price,
            entry_price,
            full_args,
            n_prices,
            exit_timestamps,
            labels,
            rets,
            log_rets,
        )
        return true
    elseif barrier_hit(
        barrier, level, price_bars.low[j], price_bars.high[j], price_bars.timestamp[j]
    )
        _record_exit!(
            i,
            j,
            barrier,
            level,
            entry_price,
            full_args,
            n_prices,
            exit_timestamps,
            labels,
            rets,
            log_rets,
        )
        return true
    end

    return _check_barrier_recursive!(
        i,
        j,
        Base.tail(barriers),
        open_price,
        loop_args,
        price_bars,
        entry_price,
        full_args,
        n_prices,
        exit_timestamps,
        labels,
        rets,
        log_rets,
    )
end

# ── Exit recording ──

@inline function _record_exit!(
    i,
    j,
    barrier,
    level,
    entry_price,
    full_args,
    n_prices,
    exit_timestamps,
    labels,
    rets,
    log_rets,
)
    exit_adj = _get_idx_adj(barrier.exit_basis)
    exit_idx = j + exit_adj

    exit_idx > n_prices && return false

    T = eltype(rets)
    exit_price = _get_price(barrier.exit_basis, level, exit_idx, full_args)

    exit_timestamps[i] = full_args.bars.timestamp[exit_idx]
    labels[i] = barrier.label

    raw_ret = (exit_price / entry_price) - one(T)
    rets[i] = raw_ret
    log_rets[i] = log1p(raw_ret)

    return true
end