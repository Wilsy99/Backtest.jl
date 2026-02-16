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

struct LabelResults{I<:Int,T<:AbstractFloat}
    entry_idx::Vector{I}
    exit_idx::Vector{I}
    label::Vector{Int8}
    weight::Vector{T}
    ret::Vector{T}
    log_ret::Vector{T}
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

    T = eltype(price_bars.close)
    n_events = length(event_indices)
    n_prices = length(price_bars)

    full_args = merge(barrier_args, (; bars=price_bars))

    entry_indices = zeros(Int, n_events)
    exit_indices = zeros(Int, n_events)
    labels = fill(Int8(-99), n_events)
    rets = Vector{T}(undef, n_events)
    log_rets = Vector{T}(undef, n_events)

    entry_adj = _get_idx_adj(entry_basis)

    @inbounds Base.Threads.@threads for i in 1:n_events
        entry_idx = event_indices[i] + entry_adj

        if entry_idx < 1 || entry_idx > n_prices
            continue
        end

        entry_indices[i] = entry_idx
        entry_ts = price_bars.timestamp[entry_idx]
        entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)

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
                exit_indices,
                labels,
                rets,
                log_rets,
            )
            if hit
                break
            end
        end
    end

    # Filter unfinished trades BEFORE calculating weights
    if drop_unfinished
        mask = labels .!= Int8(-99)
        final_entry_indices = entry_indices[mask]
        final_exit_indices = exit_indices[mask]
        final_labels = labels[mask]
        final_rets = rets[mask]
        final_log_rets = log_rets[mask]
    else
        final_entry_indices = entry_indices
        final_exit_indices = exit_indices
        final_labels = labels
        final_rets = rets
        final_log_rets = log_rets
    end

    weights = _normalised_weights(
        length(final_entry_indices),
        n_prices,
        final_entry_indices,
        final_exit_indices,
        final_rets,
        T,
    )

    return LabelResults(
        final_entry_indices,
        final_exit_indices,
        final_labels,
        weights,
        final_rets,
        final_log_rets,
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

@inline function _check_and_process_barriers!(
    i,
    j,
    barriers::Tuple,
    loop_args,
    price_bars,
    entry_price,
    full_args,
    n_prices,
    exit_indices,
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
        exit_indices,
        labels,
        rets,
        log_rets,
    )
end

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
    exit_indices,
    labels,
    rets,
    log_rets,
)
    return false
end

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
    exit_indices,
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
            exit_indices,
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
            exit_indices,
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
        exit_indices,
        labels,
        rets,
        log_rets,
    )
end

@inline function _record_exit!(
    i,
    j,
    barrier,
    level,
    entry_price,
    full_args,
    n_prices,
    exit_indices,
    labels,
    rets,
    log_rets,
)
    exit_adj = _get_idx_adj(barrier.exit_basis)
    exit_idx = j + exit_adj

    exit_idx > n_prices && return false

    T = eltype(rets)
    exit_price = _get_price(barrier.exit_basis, level, exit_idx, full_args)

    exit_indices[i] = exit_idx
    labels[i] = barrier.label

    raw_ret = (exit_price / entry_price) - one(T)
    rets[i] = raw_ret
    log_rets[i] = log1p(raw_ret)

    return true
end

# ── Weight Calculation ──

@inline function _normalised_weights(
    n_labels, n_prices, entry_indices, exit_indices, rets, ::Type{T}
)
    weights = Vector{T}(undef, n_labels)

    if n_labels == 0
        return weights
    end

    cum_inv_concurs = _cumulative_inverse_concurrency(
        n_prices, entry_indices, exit_indices, T
    )

    sum_of_weights = zero(T)
    @inbounds for i in eachindex(entry_indices)
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]
        ret = rets[i]

        cum_inv_concur = cum_inv_concurs[exit_idx + 1] - cum_inv_concurs[entry_idx]
        duration = (exit_idx - entry_idx) + 1

        weight = (cum_inv_concur / duration) * abs(ret)
        sum_of_weights += weight
        weights[i] = weight
    end

    if sum_of_weights > 0
        weights .*= (n_labels / sum_of_weights)
    else
        fill!(weights, one(T))
    end

    return weights
end

@inline function _cumulative_inverse_concurrency(
    n_prices, entry_indices, exit_indices, ::Type{T}
) where {T}
    concur_deltas = zeros(Int32, n_prices + 1)

    @inbounds for i in eachindex(entry_indices)
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]

        if entry_idx > 0 && exit_idx > 0
            concur_deltas[entry_idx] += 1
            if exit_idx < n_prices
                concur_deltas[exit_idx + 1] -= 1
            end
        end
    end

    cum_inv_concurs = Vector{T}(undef, n_prices + 1)
    cum_inv_concurs[1] = zero(T)

    concur = 0
    cum_inv_concur = zero(T)

    @inbounds for i in 1:n_prices
        concur += concur_deltas[i]

        if concur > 0
            cum_inv_concur += one(T) / concur
        end

        cum_inv_concurs[i + 1] = cum_inv_concur
    end

    return cum_inv_concurs
end