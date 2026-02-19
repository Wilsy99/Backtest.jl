include("execution.jl")
include("barrier.jl")

# ── Output Buffers ──

"""
Thread-safe output buffer for barrier exit recording.
Each thread writes to a unique index `i`, so no synchronisation is needed.
"""
struct ExitBuffers{T<:AbstractFloat,TS}
    exit_indices::Vector{Int}
    exit_timestamps::Vector{TS}
    labels::Vector{Int8}
    rets::Vector{T}
    log_rets::Vector{T}
end

function ExitBuffers(n::Int, ::Type{T}, ::Type{TS}) where {T,TS}
    return ExitBuffers{T,TS}(
        zeros(Int, n), Vector{TS}(undef, n), fill(Int8(-99), n), zeros(T, n), zeros(T, n)
    )
end

# ── Label Structs ──

"""
Shared storage for `Label` and `Label!`. Both are identical except that
`Label` merges results into the input NamedTuple while `Label!` returns
only the `LabelResults`.
"""
struct _LabelCore{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple}
    barriers::B
    entry_basis::E
    drop_unfinished::Bool
    time_decay_start::Float64
    multi_thread::Bool
    barrier_args::NT
end

function _LabelCore(
    barriers::AbstractBarrier...;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    time_decay_start::Real=1.0,
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
)
    return _LabelCore(
        barriers,
        entry_basis,
        drop_unfinished,
        Float64(time_decay_start),
        multi_thread,
        barrier_args,
    )
end

struct Label{C<:_LabelCore} <: AbstractLabel
    core::C
end

struct Label!{C<:_LabelCore} <: AbstractLabel
    core::C
end

function Label(barriers::AbstractBarrier...; kwargs...)
    return Label(_LabelCore(barriers...; kwargs...))
end

function Label!(barriers::AbstractBarrier...; kwargs...)
    return Label!(_LabelCore(barriers...; kwargs...))
end

struct LabelResults{I<:Int,T<:AbstractFloat,TS}
    entry_idx::Vector{I}
    exit_idx::Vector{I}
    entry_ts::Vector{TS}
    exit_ts::Vector{TS}
    label::Vector{Int8}
    weight::Vector{T}
    ret::Vector{T}
    log_ret::Vector{T}
end

# ── Functors ──

@inline function _run_label(core::_LabelCore, d::NamedTuple)
    return calculate_label(
        d.event_indices,
        d.bars,
        core.barriers;
        entry_basis=core.entry_basis,
        drop_unfinished=core.drop_unfinished,
        time_decay_start=core.time_decay_start,
        multi_thread=core.multi_thread,
        barrier_args=merge(d, core.barrier_args),
    )
end

(lab::Label)(d::NamedTuple) = merge(d, (; labels=_run_label(lab.core, d)))
(lab::Label!)(d::NamedTuple) = _run_label(lab.core, d)

# ── Main Label Calculation ──

function calculate_label(
    event_indices::AbstractVector{Int},
    timestamps::AbstractVector,
    opens::AbstractVector{T},
    highs::AbstractVector{T},
    lows::AbstractVector{T},
    closes::AbstractVector{T},
    volumes::AbstractVector{T},
    barriers::Tuple;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    time_decay_start::Real=1.0,
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
) where {T<:AbstractFloat}
    price_bars = PriceBars(opens, highs, lows, closes, volumes, timestamps, TimeBar())
    return calculate_label(
        event_indices,
        price_bars,
        barriers;
        entry_basis,
        drop_unfinished,
        time_decay_start,
        multi_thread,
        barrier_args,
    )
end

function calculate_label(
    event_indices::AbstractVector{Int},
    price_bars::PriceBars,
    barriers::Tuple;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    time_decay_start::Real=1.0,
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
)
    _warn_barrier_ordering(barriers)

    # Sort for correct time-decay ordering; keep permutation to restore caller order
    if issorted(event_indices)
        sorted_events = event_indices
        sort_perm = nothing
    else
        sort_perm = sortperm(event_indices)
        sorted_events = event_indices[sort_perm]
    end

    T = eltype(price_bars.close)
    TS = eltype(price_bars.timestamp)
    n_events = length(sorted_events)
    n_prices = length(price_bars)

    full_args = merge(barrier_args, (; bars=price_bars))

    entry_indices = zeros(Int, n_events)
    entry_timestamps = fill(price_bars.timestamp[1], n_events)
    buf = ExitBuffers(n_events, T, TS)

    entry_adj = _get_idx_adj(entry_basis)

    _label_loop!(
        sorted_events,
        entry_indices,
        entry_timestamps,
        buf,
        barriers,
        price_bars,
        full_args,
        entry_basis,
        entry_adj,
        n_events,
        n_prices,
        T,
        multi_thread,
    )

    # Filter unfinished trades
    mask = drop_unfinished ? buf.labels .!= Int8(-99) : trues(n_events)

    entry_idx = entry_indices[mask]
    exit_idx = buf.exit_indices[mask]
    entry_ts = entry_timestamps[mask]
    exit_ts = buf.exit_timestamps[mask]
    labels = buf.labels[mask]
    rets = buf.rets[mask]
    log_rets = buf.log_rets[mask]

    # Weights applied in temporal (sorted) order for correct time decay
    label_classes = unique(labels)
    exposure_offset = _get_exposure_adj(entry_basis)

    weights = _attribution_weights(
        label_classes,
        length(entry_idx),
        n_prices,
        entry_idx,
        exit_idx,
        labels,
        price_bars.close,
        T(time_decay_start),
        exposure_offset,
    )

    # Restore caller's original ordering after weights are computed
    if sort_perm !== nothing
        reorder = sortperm(invperm(sort_perm)[mask])
        entry_idx = entry_idx[reorder]
        exit_idx = exit_idx[reorder]
        entry_ts = entry_ts[reorder]
        exit_ts = exit_ts[reorder]
        labels = labels[reorder]
        weights = weights[reorder]
        rets = rets[reorder]
        log_rets = log_rets[reorder]
    end

    return LabelResults(
        entry_idx, exit_idx, entry_ts, exit_ts, labels, weights, rets, log_rets
    )
end

# ── Event Loop ──

function _label_loop!(
    sorted_events,
    entry_indices,
    entry_timestamps,
    buf,
    barriers,
    price_bars,
    full_args,
    entry_basis,
    entry_adj,
    n_events,
    n_prices,
    ::Type{T},
    multi_thread::Bool,
) where {T}
    if multi_thread
        @inbounds Threads.@threads for i in 1:n_events
            _label_event!(
                i,
                sorted_events,
                entry_indices,
                entry_timestamps,
                buf,
                barriers,
                price_bars,
                full_args,
                entry_basis,
                entry_adj,
                n_prices,
                T,
            )
        end
    else
        @inbounds for i in 1:n_events
            _label_event!(
                i,
                sorted_events,
                entry_indices,
                entry_timestamps,
                buf,
                barriers,
                price_bars,
                full_args,
                entry_basis,
                entry_adj,
                n_prices,
                T,
            )
        end
    end
    return nothing
end

@inline function _label_event!(
    i,
    sorted_events,
    entry_indices,
    entry_timestamps,
    buf,
    barriers,
    price_bars,
    full_args,
    entry_basis,
    entry_adj,
    n_prices,
    ::Type{T},
) where {T}
    entry_idx = sorted_events[i] + entry_adj

    if entry_idx < 1 || entry_idx > n_prices
        return nothing
    end

    entry_indices[i] = entry_idx
    entry_timestamps[i] = price_bars.timestamp[entry_idx]

    entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)
    entry_ts = entry_timestamps[i]

    for j in (entry_idx + 1):n_prices
        loop_args = (; full_args..., idx=j, entry_price=entry_price, entry_ts=entry_ts)

        hit = _check_barriers!(
            i, j, barriers, loop_args, price_bars, entry_price, full_args, n_prices, buf
        )
        hit && break
    end
    return nothing
end

# ── Barrier Checks ──

function _warn_barrier_ordering(barriers::Tuple)
    for i in 1:(length(barriers) - 1)
        a = barriers[i]
        b = barriers[i + 1]
        if _temporal_priority(a.exit_basis) > _temporal_priority(b.exit_basis)
            _warning_message(a, b)
        end
    end
end

@noinline function _warning_message(barrier_a, barrier_b)
    @warn "Barrier $(typeof(barrier_a).name.name) with $(typeof(barrier_a.exit_basis).name.name) " *
        "exit basis is listed before $(typeof(barrier_b).name.name) with " *
        "$(typeof(barrier_b.exit_basis).name.name) exit basis. The first-listed " *
        "barrier takes priority when both trigger on the same bar."
    return nothing
end

@inline function _check_barriers!(
    i,
    j,
    barriers::Tuple,
    loop_args,
    price_bars,
    entry_price,
    full_args,
    n_prices,
    buf::ExitBuffers,
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
        buf,
    )
end

# Base case: no barriers remaining
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
    buf::ExitBuffers,
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
    buf::ExitBuffers,
)
    barrier = first(barriers)
    level = barrier_level(barrier, loop_args)

    if gap_hit(barrier, level, open_price)
        return _record_exit!(
            i, j, barrier, open_price, entry_price, full_args, n_prices, buf
        )
    elseif barrier_hit(
        barrier, level, price_bars.low[j], price_bars.high[j], price_bars.timestamp[j]
    )
        return _record_exit!(i, j, barrier, level, entry_price, full_args, n_prices, buf)
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
        buf,
    )
end

"""
Record a barrier exit into `buf`. Uses `full_args.bars` for timestamp lookup.
Returns `false` without recording if exit index exceeds available data
(e.g. NextOpen exit on the final bar).
"""
@inline function _record_exit!(
    i, j, barrier, level, entry_price, full_args, n_prices, buf::ExitBuffers
)
    exit_adj = _get_idx_adj(barrier.exit_basis)
    exit_idx = j + exit_adj
    exit_idx > n_prices && return false

    T = eltype(buf.rets)
    exit_price = _get_price(barrier.exit_basis, level, exit_idx, full_args)

    buf.exit_indices[i] = exit_idx
    buf.exit_timestamps[i] = full_args.bars.timestamp[exit_idx]
    buf.labels[i] = barrier.label

    raw_ret = (exit_price / entry_price) - one(T)
    buf.rets[i] = raw_ret
    buf.log_rets[i] = log1p(raw_ret)
    return true
end

# ── Weight Calculation ──

"""
Compute sample weights via uniqueness-weighted attribution returns,
linear time decay, and class-imbalance correction.
Weights are normalised so that `sum(weights) == n_labels`.
"""
@inline function _attribution_weights(
    label_classes::Vector{Int8},
    n_labels::Int,
    n_prices::Int,
    entry_indices::AbstractVector{Int},
    exit_indices::AbstractVector{Int},
    labels::AbstractVector{Int8},
    closes::AbstractVector{T},
    time_decay_start::T,
    exposure_offset::Int,
) where {T}
    weights = Vector{T}(undef, n_labels)
    n_labels == 0 && return weights

    n_label_classes = length(label_classes)

    # 1. Sweep-line cumulative attributed returns
    cum_attrib_rets = _cumulative_attributed_returns(
        n_prices, entry_indices, exit_indices, closes, exposure_offset, T
    )

    # 2. Linear time decay: ramps from time_decay_start → 1.0 across labels
    time_decay = time_decay_start
    time_decay_incr = n_labels > 1 ? (one(T) - time_decay_start) / T(n_labels - 1) : zero(T)

    classes_weights = zeros(T, n_label_classes)

    # ── Pass 1: Raw weight × decay, tallied per class ──
    @inbounds for i in 1:n_labels
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]
        label_number = findfirst(==(labels[i]), label_classes)

        start_lookup = entry_idx + exposure_offset
        weight =
            abs(cum_attrib_rets[exit_idx + 1] - cum_attrib_rets[start_lookup]) * time_decay

        weights[i] = weight
        classes_weights[label_number] += weight
        time_decay += time_decay_incr
    end

    # 3. Class imbalance correction
    total_decayed_weight = sum(classes_weights)
    target_class_weight = total_decayed_weight / n_label_classes

    class_multipliers = zeros(T, n_label_classes)
    for c in 1:n_label_classes
        class_multipliers[c] =
            classes_weights[c] > zero(T) ? target_class_weight / classes_weights[c] : one(T)
    end

    # ── Pass 2: Apply class balance & normalize so sum(weights) == n_labels ──
    sum_of_weights = zero(T)
    @inbounds for i in 1:n_labels
        label_number = findfirst(==(labels[i]), label_classes)
        weights[i] *= class_multipliers[label_number]
        sum_of_weights += weights[i]
    end

    if sum_of_weights > zero(T)
        norm_factor = T(n_labels) / sum_of_weights
        @inbounds for i in 1:n_labels
            weights[i] *= norm_factor
        end
    else
        fill!(weights, one(T))
    end

    return weights
end

@inline function _cumulative_attributed_returns(
    n_prices, entry_indices, exit_indices, closes, exposure_offset, ::Type{T}
) where {T}
    # +2 buffer: safely handles exit_idx + 1 decrement when exit_idx == n_prices
    concur_deltas = zeros(Int32, n_prices + 2)

    @inbounds for i in eachindex(entry_indices)
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]

        if entry_idx > 0 && exit_idx > 0
            start_idx = entry_idx + exposure_offset
            if start_idx <= n_prices
                concur_deltas[start_idx] += 1
                concur_deltas[exit_idx + 1] -= 1
            end
        end
    end

    # cum_attrib_rets[t+1] holds cumulative attributed return through bar t
    cum_attrib_rets = zeros(T, n_prices + 1)
    concur = 0
    current_cum_val = zero(T)

    @inbounds for t in 1:n_prices
        concur += concur_deltas[t]
        if t > 1
            bar_ret = log(closes[t] / closes[t - 1])
            if concur > 0
                current_cum_val += bar_ret / concur
            end
        end
        cum_attrib_rets[t + 1] = current_cum_val
    end

    return cum_attrib_rets
end