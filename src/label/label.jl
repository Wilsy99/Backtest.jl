include("execution.jl")
include("barrier.jl")
include("weights.jl")

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
[`compute_label`](@ref) with the settings stored here. The only
difference is how the result is returned: `Label` merges it into the
pipeline `NamedTuple`, while `Label!` returns the raw
[`LabelResults`](@ref).

# Fields
- `barriers::B`: tuple of [`AbstractBarrier`](@ref) instances.
- `entry_basis::E`: execution basis for trade entry pricing.
- `drop_unfinished::Bool`: whether to drop events whose barriers
    are not resolved by end of data.
- `multi_thread::Bool`: enable multi-threaded event loop.
- `barrier_args::NT`: additional keyword arguments forwarded to
    barrier level functions via `merge`.
"""
struct _LabelCore{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple}
    barriers::B
    entry_basis::E
    drop_unfinished::Bool
    multi_thread::Bool
    barrier_args::NT
end

function _LabelCore(
    barriers::AbstractBarrier...;
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
)
    return _LabelCore(
        barriers,
        entry_basis,
        drop_unfinished,
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
# result = bars >> Features(:ema_10 => EMA(10), :ema_50 => EMA(50)) >> Crossover(:ema_10, :ema_50) >> evt >> lab2
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
- [`compute_label`](@ref): the underlying computation function.
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
    LabelResults{I<:Int,T<:AbstractFloat}

Immutable container for triple-barrier labelling output.

Each field is a parallel vector indexed by event number. All vectors
have the same length (one entry per resolved event, or per event if
`drop_unfinished=false`).

# Fields
- `trade_idx_range::Vector{UnitRange{I}}`: bar index range from
    entry to exit for each trade (e.g. `3:7`).
- `side::Vector{Int8}`: entry-time side signal (`1` long, `-1`
    short, `0` neutral). Snapshotted from the `side` vector at the
    entry bar index.
- `label::Vector{Int8}`: barrier label (`1` upper, `-1` lower, `0`
    time/condition, `-99` unfinished).
- `bin::Vector{Int8}`: meta label `max(side * label, 0)`. Equals
    `1` when the trade direction agrees with the barrier outcome,
    `0` otherwise.
- `ret::Vector{T}`: arithmetic return `(exit_price / entry_price) - 1`.
- `log_ret::Vector{T}`: log return `log1p(ret)`.

# See also
- [`Label`](@ref), [`Label!`](@ref): functors that produce this.
- [`compute_label`](@ref): the computation function.
- [`compute_weights`](@ref): compute sample weights from label results.
"""
struct LabelResults{I<:Int,T<:AbstractFloat}
    trade_idx_range::Vector{UnitRange{I}}
    side::Vector{Int8}
    label::Vector{Int8}
    bin::Vector{Int8}
    ret::Vector{T}
    log_ret::Vector{T}
end

Base.length(r::LabelResults) = length(r.trade_idx_range)

# ── Functors ──

@inline function _run_label(core::_LabelCore, d::NamedTuple)
    return compute_label(
        d.event_indices,
        d.bars,
        core.barriers;
        side=d.side,
        entry_basis=core.entry_basis,
        drop_unfinished=core.drop_unfinished,
        multi_thread=core.multi_thread,
        barrier_args=merge(d, core.barrier_args),
    )
end

(lab::Label)(d::NamedTuple) = merge(d, (; labels=_run_label(lab.core, d)))
(lab::Label!)(d::NamedTuple) = _run_label(lab.core, d)

# ── Main Label Calculation ──

"""
    compute_label(event_indices, timestamps, opens, highs, lows, closes, volumes, barriers; kwargs...) -> LabelResults
    compute_label(event_indices, price_bars, barriers; kwargs...) -> LabelResults

Compute triple-barrier labels for a set of event indices.

For each event, walk forward through subsequent bars and check each
barrier in priority order. The first barrier hit determines the exit
bar, label, and return.

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
- `multi_thread::Bool = false`: enable multi-threaded event loop.
- `barrier_args::NamedTuple = (;)`: additional context forwarded to
    barrier level functions.

# Returns
- [`LabelResults`](@ref): labelling output with trade index ranges,
    side, labels, bin (meta label), and returns.

# See also
- [`Label`](@ref), [`Label!`](@ref): functor wrappers for pipeline use.
- [`compute_weights`](@ref): compute sample weights from label results.
"""
function compute_label(
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
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
) where {T<:AbstractFloat}
    price_bars = PriceBars(opens, highs, lows, closes, volumes, timestamps, TimeBar())
    return compute_label(
        event_indices,
        price_bars,
        barriers;
        side,
        entry_basis,
        drop_unfinished,
        multi_thread,
        barrier_args,
    )
end

function compute_label(
    event_indices::AbstractVector{Int},
    price_bars::PriceBars,
    barriers::Tuple;
    side::AbstractVector{Int8},
    entry_basis::AbstractExecutionBasis=NextOpen(),
    drop_unfinished::Bool=true,
    multi_thread::Bool=false,
    barrier_args::NamedTuple=(;),
)
    _warn_barrier_ordering(barriers)

    # Sort events; keep permutation to restore caller order
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
    sides = buf.sides[mask]
    labels = buf.labels[mask]
    bins = buf.bins[mask]
    rets = buf.rets[mask]
    log_rets = buf.log_rets[mask]

    # Restore caller's original ordering
    if sort_perm !== nothing
        reorder = sortperm(invperm(sort_perm)[mask])
        entry_idx = entry_idx[reorder]
        exit_idx = exit_idx[reorder]
        sides = sides[reorder]
        labels = labels[reorder]
        bins = bins[reorder]
        rets = rets[reorder]
        log_rets = log_rets[reorder]
    end

    trade_idx_range = [entry_idx[i]:exit_idx[i] for i in eachindex(entry_idx)]

    return LabelResults(
        trade_idx_range, sides, labels, bins, rets, log_rets,
    )
end

# ── Barrier Loop Context ──

"""
    BarrierArgs{NT<:NamedTuple,T<:AbstractFloat,TS}

Immutable barrier-loop context that avoids heap allocations in the
label event loop.

The pipeline data (`bars`, `side`, feature vectors, user-provided
`barrier_args`) lives in a `NamedTuple` in the `data` field.
A new instance is created each bar iteration with only the `idx`
field changing; being immutable, the compiler can stack-allocate it
when callers are inlined, achieving zero heap allocations per bar.

Transparent field access via `Base.getproperty` makes this a drop-in
replacement for the `NamedTuple` that barrier level functions expect:
`d.entry_price`, `d.bars`, `d.features.ema_20[d.idx]` all work unchanged.

# Fields
- `data::NT`: pipeline context (bars, side, barrier_args).
- `idx::Int`: current bar index (changes each inner-loop iteration).
- `entry_price::T`: fill price at trade entry (set once per event).
- `entry_ts::TS`: timestamp of the entry bar (set once per event).
- `entry_side::Int8`: side signal at entry (set once per event).
"""
struct BarrierArgs{NT<:NamedTuple,T<:AbstractFloat,TS}
    data::NT
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

A new [`BarrierArgs`](@ref) context is created each bar iteration
with only the `idx` field changing. Being immutable, the compiler
stack-allocates it (zero heap allocations per bar). The context
exposes the following fields to barrier level functions via
`getproperty`:
- `entry_price`: fill price at entry, determined by `entry_basis`.
- `entry_ts`: timestamp of the entry bar.
- `entry_side`: side signal (`Int8`) at the entry bar, snapshotted
    from `full_args.side` at the entry bar index.
- `idx`: current bar index (new value each iteration).
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

    for j in (entry_idx + 1):n_prices
        # Immutable struct — stack-allocated, zero heap allocations per bar
        loop_args = BarrierArgs(full_args, j, entry_price, entry_ts, entry_side)

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
