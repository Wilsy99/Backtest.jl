include("execution.jl")
include("barrier.jl")

# ── Output Buffers ──

"""
    ExitBuffers{T<:AbstractFloat,TS}

Thread-safe output buffer for recording barrier exit results.

Each event index `i` maps to a unique slot in each vector, so
concurrent writes from `Threads.@threads` do not require
synchronisation.

# Fields
- `exit_indices::Vector{Int}`: bar index where each event exited.
- `exit_timestamps::Vector{TS}`: timestamp of the exit bar.
- `sides::Vector{Int8}`: entry-time side signal for each event.
- `labels::Vector{Int8}`: barrier label for each event. Initialised
    to `Int8(-99)` as a sentinel for unfinished trades.
- `bins::Vector{Int8}`: meta label `max(side * label, 0)` for each
    event. Set when a barrier is hit.
- `rets::Vector{T}`: raw arithmetic return `(exit_price / entry_price) - 1`.
- `log_rets::Vector{T}`: log return `log1p(ret)`.
"""
struct ExitBuffers{T<:AbstractFloat,TS}
    exit_indices::Vector{Int}
    exit_timestamps::Vector{TS}
    sides::Vector{Int8}
    labels::Vector{Int8}
    bins::Vector{Int8}
    rets::Vector{T}
    log_rets::Vector{T}
end

function ExitBuffers(n::Int, ::Type{T}, ::Type{TS}) where {T,TS}
    return ExitBuffers{T,TS}(
        zeros(Int, n), Vector{TS}(undef, n), zeros(Int8, n), fill(Int8(-99), n),
        zeros(Int8, n), zeros(T, n), zeros(T, n)
    )
end

# ── Label Structs ──

"""
    _LabelCore{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple}

Shared storage for [`Label`](@ref) and [`Label!`](@ref) functors.

Both functor types delegate to `_run_label` which calls
[`calculate_label`](@ref) with the settings stored here. The only
difference is how the result is returned: `Label` merges it into the
pipeline `NamedTuple`, while `Label!` returns the raw
[`LabelResults`](@ref).

# Fields
- `barriers::B`: tuple of [`AbstractBarrier`](@ref) instances.
- `entry_basis::E`: execution basis for trade entry pricing.
- `drop_unfinished::Bool`: whether to drop events whose barriers
    are not resolved by end of data.
- `time_decay_start::T`: starting value for linear time decay
    in weight calculation. Ramps from this value to `1.0` across
    events in temporal order.
- `multi_thread::Bool`: enable multi-threaded event loop.
- `barrier_args::NT`: additional keyword arguments forwarded to
    barrier level functions via `merge`.
"""
struct _LabelCore{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple,T<:Real}
    barriers::B
    entry_basis::E
    drop_unfinished::Bool
    time_decay_start::T
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
        float(time_decay_start),
        multi_thread,
        barrier_args,
    )
end

"""
    Label{C<:_LabelCore} <: AbstractLabel

Triple-barrier labelling functor that merges results into the pipeline
`NamedTuple`.

When called on a pipeline `NamedTuple` containing `event_indices` and
`bars`, compute labels for each event and return the input merged with
`(; labels=LabelResults(...))`.

# Constructors
    Label(barriers::AbstractBarrier...; kwargs...)

# Keywords
- `entry_basis::AbstractExecutionBasis = NextOpen()`: execution basis
    for trade entry pricing.
- `drop_unfinished::Bool = true`: drop events whose barriers are not
    resolved by end of data.
- `time_decay_start::Real = 1.0`: starting value for linear time
    decay (`1.0` disables decay).
- `multi_thread::Bool = false`: enable multi-threaded event loop.
- `barrier_args::NamedTuple = (;)`: additional arguments forwarded to
    barrier level functions.

# Barrier Context Fields

Inside barrier level functions, the following scalar fields are
available (snapshotted at entry time, constant across the holding
period):
- `entry_price`: fill price at entry.
- `entry_ts`: timestamp of the entry bar.
- `entry_side`: side signal (`Int8`) at the entry bar. Equals the
    `side` vector value at the entry bar index. A side detector
    (e.g. [`Crossover`](@ref)) must be upstream in the pipeline.
    Use this to condition barrier levels on trade direction.

# Examples
```julia
using Backtest, Dates

lab = Label(
    UpperBarrier(d -> d.entry_price * 1.05),
    LowerBarrier(d -> d.entry_price * 0.95),
    TimeBarrier(d -> d.entry_ts + Day(20)),
)

# Side-dependent barrier using entry_side:
lab2 = Label(
    @UpperBarrier(:entry_side == 1 ? :entry_price * 1.05 : :entry_price * 1.10),
    @LowerBarrier(:entry_side == 1 ? :entry_price * 0.95 : :entry_price * 0.90),
    @TimeBarrier(:entry_ts + Day(20)),
)

# In a pipeline:
# result = bars >> EMA(10, 50) >> Crossover(:ema_10, :ema_50) >> evt >> lab2
```

# Pipeline Data Flow

## Input
Expects a `NamedTuple` with at least:
- `event_indices::Vector{Int}`: bar indices from an upstream
    [`Event`](@ref).
- `bars::PriceBars`: the price data.
- `side::Vector{Int8}`: side signals from an upstream side detector
    (e.g. [`Crossover`](@ref)).

## Output
Return the input merged with:
- `labels::LabelResults`: the labelling results.

# See also
- [`Label!`](@ref): variant that returns only `LabelResults`.
- [`calculate_label`](@ref): the underlying computation function.
- [`LabelResults`](@ref): the output container.
"""
struct Label{C<:_LabelCore} <: AbstractLabel
    core::C
end

"""
    Label!{C<:_LabelCore} <: AbstractLabel

Triple-barrier labelling functor that returns only the
[`LabelResults`](@ref) without merging into the pipeline.

Identical to [`Label`](@ref) in computation, but returns the raw
`LabelResults` struct instead of merging it into the input
`NamedTuple`. Useful when the upstream pipeline data is not needed
downstream.

# Constructors
    Label!(barriers::AbstractBarrier...; kwargs...)

Keywords are identical to [`Label`](@ref).

# See also
- [`Label`](@ref): variant that merges results into the pipeline.
"""
struct Label!{C<:_LabelCore} <: AbstractLabel
    core::C
end

function Label(barriers::AbstractBarrier...; kwargs...)
    return Label(_LabelCore(barriers...; kwargs...))
end

function Label!(barriers::AbstractBarrier...; kwargs...)
    return Label!(_LabelCore(barriers...; kwargs...))
end

"""
    LabelResults{I<:Int,T<:AbstractFloat,TS}

Immutable container for triple-barrier labelling output.

Each field is a parallel vector indexed by event number. All vectors
have the same length (one entry per resolved event, or per event if
`drop_unfinished=false`).

# Fields
- `entry_idx::Vector{I}`: bar index of trade entry.
- `exit_idx::Vector{I}`: bar index of barrier exit.
- `entry_ts::Vector{TS}`: timestamp of the entry bar.
- `exit_ts::Vector{TS}`: timestamp of the exit bar.
- `side::Vector{Int8}`: entry-time side signal (`1` long, `-1`
    short, `0` neutral). Snapshotted from the `side` vector at the
    entry bar index.
- `label::Vector{Int8}`: barrier label (`1` upper, `-1` lower, `0`
    time/condition, `-99` unfinished).
- `bin::Vector{Int8}`: meta label `max(side * label, 0)`. Equals
    `1` when the trade direction agrees with the barrier outcome,
    `0` otherwise.
- `weight::Vector{T}`: sample weight incorporating attribution,
    time decay, and class-imbalance correction.
- `ret::Vector{T}`: arithmetic return `(exit_price / entry_price) - 1`.
- `log_ret::Vector{T}`: log return `log1p(ret)`.

# See also
- [`Label`](@ref), [`Label!`](@ref): functors that produce this.
- [`calculate_label`](@ref): the computation function.
"""
struct LabelResults{I<:Int,T<:AbstractFloat,TS}
    entry_idx::Vector{I}
    exit_idx::Vector{I}
    entry_ts::Vector{TS}
    exit_ts::Vector{TS}
    side::Vector{Int8}
    label::Vector{Int8}
    bin::Vector{Int8}
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
        side=d.side,
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

"""
    calculate_label(event_indices, timestamps, opens, highs, lows, closes, volumes, barriers; kwargs...) -> LabelResults
    calculate_label(event_indices, price_bars, barriers; kwargs...) -> LabelResults

Compute triple-barrier labels for a set of event indices.

For each event, walk forward through subsequent bars and check each
barrier in priority order. The first barrier hit determines the exit
bar, label, and return. Events are processed in temporal order for
correct time-decay weighting, then restored to the caller's original
ordering.

# Arguments
- `event_indices::AbstractVector{Int}`: bar indices where events were
    detected.
- `price_bars::PriceBars`: OHLCV price data with timestamps.
- `barriers::Tuple`: tuple of [`AbstractBarrier`](@ref) instances,
    checked in order of priority.

# Keywords
- `side::AbstractVector{Int8}`: side signals (required). One entry
    per bar (`1` long, `-1` short, `0` neutral).
- `entry_basis::AbstractExecutionBasis = NextOpen()`: determines the
    entry fill price and index offset.
- `drop_unfinished::Bool = true`: drop events whose barriers are not
    resolved by end of data.
- `time_decay_start::Real = 1.0`: starting value for linear time
    decay in weight calculation. `1.0` disables decay.
- `multi_thread::Bool = false`: enable multi-threaded event loop.
- `barrier_args::NamedTuple = (;)`: additional context forwarded to
    barrier level functions.

# Returns
- [`LabelResults`](@ref): labelling output with entry/exit indices,
    timestamps, side, labels, bin (meta label), weights, and returns.

# See also
- [`Label`](@ref), [`Label!`](@ref): functor wrappers for pipeline use.
"""
function calculate_label(
    event_indices::AbstractVector{Int},
    timestamps::AbstractVector,
    opens::AbstractVector{T},
    highs::AbstractVector{T},
    lows::AbstractVector{T},
    closes::AbstractVector{T},
    volumes::AbstractVector{T},
    barriers::Tuple;
    side::AbstractVector{Int8},
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
        side,
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
    side::AbstractVector{Int8},
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

    full_args = merge(barrier_args, (; bars=price_bars, side=side))

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

    # Filter unfinished trades (sentinel label -99)
    mask = drop_unfinished ? buf.labels .!= Int8(-99) : trues(n_events)

    entry_idx = entry_indices[mask]
    exit_idx = buf.exit_indices[mask]
    entry_ts = entry_timestamps[mask]
    exit_ts = buf.exit_timestamps[mask]
    sides = buf.sides[mask]
    labels = buf.labels[mask]
    bins = buf.bins[mask]
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
        sides = sides[reorder]
        labels = labels[reorder]
        bins = bins[reorder]
        weights = weights[reorder]
        rets = rets[reorder]
        log_rets = log_rets[reorder]
    end

    return LabelResults(
        entry_idx, exit_idx, entry_ts, exit_ts, sides, labels, bins, weights, rets,
        log_rets,
    )
end

# ── Barrier Loop Context ──

"""
    BarrierArgs{NT<:NamedTuple,T<:AbstractFloat,TS}

Mutable barrier-loop context that eliminates per-bar `NamedTuple`
allocation in the label event loop.

The static pipeline data (`bars`, `side`, feature vectors, user-provided
`barrier_args`) lives in an immutable `NamedTuple` in the `data` field.
The per-bar index `idx` and per-event entry scalars are stored as
mutable fields and updated in-place.

Transparent field access via `Base.getproperty` makes this a drop-in
replacement for the `NamedTuple` that barrier level functions expect:
`d.entry_price`, `d.bars`, `d.ema_20[d.idx]` all work unchanged.

# Fields
- `data::NT`: immutable pipeline context (bars, side, barrier_args).
- `idx::Int`: current bar index (mutated each inner-loop iteration).
- `entry_price::T`: fill price at trade entry (set once per event).
- `entry_ts::TS`: timestamp of the entry bar (set once per event).
- `entry_side::Int8`: side signal at entry (set once per event).
"""
mutable struct BarrierArgs{NT<:NamedTuple,T<:AbstractFloat,TS}
    const data::NT
    idx::Int
    entry_price::T
    entry_ts::TS
    entry_side::Int8
end

@inline function Base.getproperty(ba::BarrierArgs, s::Symbol)
    if s === :idx
        return getfield(ba, :idx)
    elseif s === :entry_price
        return getfield(ba, :entry_price)
    elseif s === :entry_ts
        return getfield(ba, :entry_ts)
    elseif s === :entry_side
        return getfield(ba, :entry_side)
    else
        return getproperty(getfield(ba, :data), s)
    end
end

# ── Event Loop ──

"""
    _label_loop!(sorted_events, entry_indices, entry_timestamps, buf, barriers, price_bars, full_args, entry_basis, entry_adj, n_events, n_prices, ::Type{T}, multi_thread) -> Nothing

Iterate over all events and dispatch to `_label_event!`.

When `multi_thread=true`, uses `Threads.@threads` for parallel
processing. Each event writes to a unique index so no synchronisation
is needed.
"""
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

"""
    _label_event!(i, sorted_events, entry_indices, entry_timestamps, buf, barriers, price_bars, full_args, entry_basis, entry_adj, n_prices, ::Type{T}) -> Nothing

Process a single event at position `i` in the sorted event list.

Compute the entry index (event index + entry adjustment), skip if
out of bounds, then walk forward through bars checking barriers until
one triggers or data ends.

A [`BarrierArgs`](@ref) context is allocated once per event and its
`idx` field is mutated each bar iteration, eliminating per-bar
`NamedTuple` allocation. The context exposes the following fields to
barrier level functions via `getproperty`:
- `entry_price`: fill price at entry, determined by `entry_basis`.
- `entry_ts`: timestamp of the entry bar.
- `entry_side`: side signal (`Int8`) at the entry bar, snapshotted
    from `full_args.side` at the entry bar index.
- `idx`: current bar index (mutated each iteration).
- All fields from `full_args` (`bars`, `side`, feature vectors, etc.).
"""
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

    # Skip events that fall outside the price data
    if entry_idx < 1 || entry_idx > n_prices
        return nothing
    end

    entry_indices[i] = entry_idx
    entry_timestamps[i] = price_bars.timestamp[entry_idx]

    entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)
    entry_ts = entry_timestamps[i]
    # Snapshot the side signal at entry so barrier functions can branch on trade direction
    entry_side = full_args.side[entry_idx]

    # Build barrier context once per event — mutate idx per bar (zero per-bar allocation)
    loop_args = BarrierArgs(full_args, entry_idx, entry_price, entry_ts, entry_side)

    for j in (entry_idx + 1):n_prices
        loop_args.idx = j

        hit = _check_barriers!(
            i, j, barriers, loop_args, price_bars, entry_price, entry_side, full_args, n_prices, buf
        )
        hit && break
    end
    return nothing
end

# ── Barrier Checks ──

"""
    _warn_barrier_ordering(barriers::Tuple) -> Nothing

Emit a warning when barriers are listed in non-optimal priority order.

Barriers are checked in tuple order; the first to trigger wins. If a
barrier with a later temporal priority (e.g., `NextOpen`) is listed
before one with an earlier priority (e.g., `Immediate`), the
user may get unexpected results.
"""
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

"""
    _check_barriers!(i, j, barriers, loop_args, price_bars, entry_price, entry_side, full_args, n_prices, buf) -> Bool

Check all barriers for the current bar `j` of event `i`.

Delegate to `_check_barrier_recursive!` which walks the barrier tuple
via recursive dispatch. Return `true` if any barrier triggered (and
the exit was recorded), `false` otherwise.
"""
@inline function _check_barriers!(
    i,
    j,
    barriers::Tuple,
    loop_args,
    price_bars,
    entry_price,
    entry_side,
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
        entry_side,
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
    entry_side,
    full_args,
    n_prices,
    buf::ExitBuffers,
)
    return false
end

"""
    _check_barrier_recursive!(i, j, barriers, open_price, loop_args, price_bars, entry_price, entry_side, full_args, n_prices, buf) -> Bool

Recursively check barriers via tuple unrolling.

For the first barrier in the tuple: check gap-through first (open
price vs level), then intra-bar hit (low/high/timestamp vs level).
If neither triggers, recurse on `Base.tail(barriers)`. This pattern
enables the compiler to fully unroll the barrier tuple at compile
time.
"""
@inline function _check_barrier_recursive!(
    i,
    j,
    barriers::Tuple,
    open_price,
    loop_args,
    price_bars,
    entry_price,
    entry_side,
    full_args,
    n_prices,
    buf::ExitBuffers,
)
    barrier = first(barriers)
    level = barrier_level(barrier, loop_args)

    # Gap check: did the bar open past the barrier?
    if gap_hit(barrier, level, open_price)
        return _record_exit!(
            i, j, barrier, open_price, entry_price, entry_side, full_args, n_prices, buf
        )
    # Intra-bar check: did the trading range touch the barrier?
    elseif barrier_hit(
        barrier, level, price_bars.low[j], price_bars.high[j], price_bars.timestamp[j]
    )
        return _record_exit!(
            i, j, barrier, level, entry_price, entry_side, full_args, n_prices, buf
        )
    end

    return _check_barrier_recursive!(
        i,
        j,
        Base.tail(barriers),
        open_price,
        loop_args,
        price_bars,
        entry_price,
        entry_side,
        full_args,
        n_prices,
        buf,
    )
end

"""
    _record_exit!(i, j, barrier, level, entry_price, entry_side, full_args, n_prices, buf) -> Bool

Record a barrier exit into `buf` at event slot `i`.

Compute the exit index from the barrier's `exit_basis` adjustment.
Return `false` without recording if the exit index exceeds available
data (e.g., `NextOpen` exit on the final bar). Otherwise record the
exit index, timestamp, side, label, bin, and returns, then return `true`.
"""
@inline function _record_exit!(
    i, j, barrier, level, entry_price, entry_side, full_args, n_prices, buf::ExitBuffers
)
    exit_adj = _get_idx_adj(barrier.exit_basis)
    exit_idx = j + exit_adj
    # Cannot exit beyond available data
    exit_idx > n_prices && return false

    T = eltype(buf.rets)
    exit_price = _get_price(barrier.exit_basis, level, exit_idx, full_args)

    buf.exit_indices[i] = exit_idx
    buf.exit_timestamps[i] = full_args.bars.timestamp[exit_idx]
    buf.sides[i] = entry_side
    buf.labels[i] = barrier.label
    buf.bins[i] = max(entry_side * barrier.label, Int8(0))

    raw_ret = (exit_price / entry_price) - one(T)
    buf.rets[i] = raw_ret
    buf.log_rets[i] = log1p(raw_ret)
    return true
end

# ── Weight Calculation ──

"""
    _attribution_weights(label_classes, n_labels, n_prices, entry_indices, exit_indices, labels, closes, time_decay_start, exposure_offset) -> Vector{T}

Compute sample weights via uniqueness-weighted attribution returns,
linear time decay, and class-imbalance correction.

The algorithm has three passes:
1. **Sweep-line attributed returns**: compute per-bar log returns
   weighted by `1/concurrency` where concurrency is the number of
   overlapping trades. Accumulated via `_cumulative_attributed_returns`.
2. **Time decay**: multiply each event's attribution weight by a
   linear ramp from `time_decay_start` to `1.0` across events in
   temporal order.
3. **Class-imbalance correction**: rebalance so each label class
   contributes equally to total weight, then normalise so
   `sum(weights) == n_labels`.
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

"""
    _cumulative_attributed_returns(n_prices, entry_indices, exit_indices, closes, exposure_offset, ::Type{T}) -> Vector{T}

Compute a prefix-sum array of uniqueness-weighted log returns.

Use a sweep-line approach: increment a concurrency counter at each
entry and decrement at each exit. Each bar's log return is divided by
the number of concurrent trades to produce "attributed" returns. The
result is a cumulative sum array of length `n_prices + 1` where
`cum[t+1] - cum[s]` gives the total attributed return over bars
`s` through `t`.

The `+2` buffer on `concur_deltas` prevents out-of-bounds when
`exit_idx == n_prices`.
"""
@inline function _cumulative_attributed_returns(
    n_prices, entry_indices, exit_indices, closes, exposure_offset, ::Type{T}
) where {T}
    # +2 buffer: safely handles exit_idx + 1 decrement when exit_idx == n_prices
    # Int32 halves memory vs Int since this is sized to n_prices; concurrency
    # counts (overlapping trades per bar) won't approach the ~2.1B Int32 limit.
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
