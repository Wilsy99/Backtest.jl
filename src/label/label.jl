include("execution.jl")
include("barrier.jl")

# ── Label configuration ──

"""
    Label{B,E,NT} <: AbstractLabel

Configures the triple-barrier labelling method. Acts as a functor in the pipeline,
consuming a `NamedTuple` with `:event_indices` and `:bars` fields and appending
a `:labels` field containing [`LabelResults`](@ref).

Each barrier carries its own [`AbstractExecutionBasis`](@ref) for exit pricing, while
`entry_basis` controls how the entry price is determined.

# Fields
- `barriers::B`: tuple of [`AbstractBarrier`](@ref) subtypes, evaluated in order.
- `entry_basis::E`: execution basis for entry price determination.
- `drop_unfinished::Bool`: if `true`, events where no barrier was hit are excluded.
- `barrier_args::NT`: additional named arguments passed through to barrier functions.

# Pipeline usage
```julia
label = Label(
    LowerBarrier(a -> a.entry_price * 0.95, Int8(-1)),
    UpperBarrier(a -> a.entry_price * 1.10, Int8(1)),
    TimeBarrier(a -> a.entry_ts + Day(10), Int8(0));
    entry_basis=NextOpen(),
)

bars |> inds |> side |> event |> label
```

# Barrier arguments
The `barrier_args` keyword injects extra data into barrier functions for data not
available on the pipeline `NamedTuple`. In most cases this is unnecessary — indicator
results from upstream pipeline stages are automatically available via the merged
`NamedTuple`.
"""
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

# ── Label results ──

"""
    LabelResults{D,T}

Container for the output of [`calculate_label`](@ref).

# Fields
- `t₀::Vector{D}`: entry timestamps.
- `t₁::Vector{D}`: exit timestamps.
- `label::Vector{Int8}`: barrier labels (e.g. `-1`, `0`, `1`).
- `ret::Vector{T}`: simple returns `(exit_price / entry_price) - 1`.
- `log_ret::Vector{T}`: log returns `log1p(ret)`.

If `drop_unfinished=true` (default), events with label `-99` (no barrier hit) are
filtered out during construction.
"""

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
            n = _compact!(labels, t₀, t₁, rets, log_rets)
            resize!(t₀, n)
            resize!(t₁, n)
            resize!(labels, n)
            resize!(rets, n)
            resize!(log_rets, n)
        end

        return new{D,T}(t₀, t₁, labels, rets, log_rets)
    end
end
# ── Pipeline functor ──

"""
    (lab::Label)(d::NamedTuple) -> NamedTuple

Apply the label configuration to pipeline data. Expects `d` to contain at minimum
`:event_indices` (from an [`Event`](@ref)) and `:bars` (a [`PriceBars`](@ref)).

All fields on `d` (including indicator results like `:ema_10`, `:atr`, etc.) are
automatically available to barrier functions via the `args` `NamedTuple`.

Returns `d` merged with `(; labels=LabelResults(...))`.
"""
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

# ── Core calculation (raw vectors) ──

"""
    calculate_label(event_indices, timestamps, opens, highs, lows, closes, volumes,
                    barriers; kwargs...) -> LabelResults

Convenience method that constructs a [`PriceBars`](@ref) from raw vectors and
delegates to the primary [`calculate_label`](@ref) method.
"""

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

# ── Core calculation (PriceBars) ──

"""
    calculate_label(event_indices, price_bars, barriers; kwargs...) -> LabelResults

Compute barrier labels for each event.

For each event index, the algorithm:
1. Determines the entry bar and price using `entry_basis`.
2. Scans forward bar-by-bar, checking each barrier in order.
3. For price barriers, checks gap-at-open first, then intrabar high/low.
4. On the first barrier hit, records the exit using the barrier's own `exit_basis`.

# Arguments
- `event_indices::AbstractVector{Int}`: bar indices where events occurred.
- `price_bars::PriceBars`: OHLCV price data.
- `barriers::Tuple`: tuple of [`AbstractBarrier`](@ref) subtypes.

# Keyword arguments
- `entry_basis::AbstractExecutionBasis=NextOpen()`: determines entry price and bar.
- `drop_unfinished::Bool=true`: exclude events where no barrier was triggered.
- `barrier_args::NamedTuple=(;)`: additional data available to barrier functions.

# Returns
A [`LabelResults`](@ref) containing entry/exit timestamps, labels, and returns.
"""
struct LoopArgs{NT<:NamedTuple,T<:AbstractFloat,D<:TimeType}
    base::NT
    idx::Int
    entry_price::T
    entry_ts::D
end

@inline function Base.getproperty(a::LoopArgs, s::Symbol)
    s === :idx && return getfield(a, :idx)
    s === :entry_price && return getfield(a, :entry_price)
    s === :entry_ts && return getfield(a, :entry_ts)
    return getproperty(getfield(a, :base), s)
end

function calculate_label(
    event_indices::AbstractVector{Int},
    price_bars::PriceBars,
    barriers::Tuple;
    entry_basis::AbstractExecutionBasis=NextOpen(),
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

    @inbounds @threads for i in 1:n_events
        entry_idx = event_indices[i] + entry_adj

        if entry_idx < 1 || entry_idx > n_prices
            continue
        end

        entry_ts = price_bars.timestamp[entry_idx]
        entry_price = _get_price(entry_basis, zero(T), entry_idx, full_args)
        entry_timestamps[i] = entry_ts

        for j in (entry_idx + 1):n_prices
            loop_args = LoopArgs(full_args, j, entry_price, entry_ts)
            barrier, level = _find_triggered_barrier(barriers, loop_args, price_bars, j)
            isnothing(barrier) && continue

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
            ) && break

            # exit index out of bounds — treat as unfinished
            break
        end
    end

    return LabelResults(
        entry_timestamps, exit_timestamps, labels, rets, log_rets; drop_unfinished
    )
end

# ── Helpers ──

"""
    _find_triggered_barrier(barriers, loop_args, price_bars, j)
        -> (barrier, level) | (nothing, nothing)

Scan barriers in order for the first trigger at bar index `j`.

For price barriers (`LowerBarrier`, `UpperBarrier`), gap detection at the open price
is checked before intrabar detection via high/low. When a gap is detected, the returned
level is the open price (reflecting realistic gap fill) rather than the barrier level.

For `TimeBarrier` and `ConditionBarrier`, only intrabar detection applies.
"""
@inline function _find_triggered_barrier(barriers, loop_args, price_bars, j)
    open_price = price_bars.open[j]

    for barrier in barriers
        level = barrier_level(barrier, loop_args)

        if gap_hit(barrier, level, open_price)
            return barrier, open_price
        end

        if barrier_hit(
            barrier, level, price_bars.low[j], price_bars.high[j], price_bars.timestamp[j]
        )
            return barrier, level
        end
    end

    return nothing, nothing
end

"""
    _record_exit!(i, j, barrier, level, entry_price, full_args, n_prices,
                  exit_timestamps, labels, rets, log_rets) -> Bool

Record the exit for event `i` triggered at bar `j`. Uses the barrier's own
`exit_basis` to determine the exit bar index and price.

Returns `true` if the exit was successfully recorded, `false` if the computed exit
index exceeds `n_prices` (the event remains unfinished with label `-99`).
"""
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