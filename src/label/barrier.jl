"""
    AbstractBarrier

Abstract type for all barrier types used in the triple-barrier labelling method.

Each barrier must define:
- `level_func`: a callable `args::NamedTuple -> level` that computes the barrier level.
- `label::Int8`: the label assigned when this barrier is hit.
- `exit_basis::AbstractExecutionBasis`: determines the exit price and index adjustment.

# Subtypes
- [`LowerBarrier`](@ref): triggers when the bar's low breaches a price level from above.
- [`UpperBarrier`](@ref): triggers when the bar's high breaches a price level from below.
- [`TimeBarrier`](@ref): triggers when the bar's timestamp reaches or exceeds a time level.
- [`ConditionBarrier`](@ref): triggers when an arbitrary boolean condition is met.

# Barrier evaluation order
Within each bar, barriers are evaluated in the order they appear in the `barriers` tuple.
Gap detection (open price vs level) is checked before intrabar detection (high/low vs level).
The first barrier triggered wins.
"""

"""
    LowerBarrier{F,E} <: AbstractBarrier

Triggers when the bar's low price is at or below the computed level, or when the
open price gaps below it. Typically used for stop-loss barriers.

# Fields
- `level_func::F`: callable `(args::NamedTuple) -> AbstractFloat` returning the barrier level.
- `label::Int8`: label assigned on trigger (conventionally `-1` for stop-loss).
- `exit_basis::E`: execution basis for the exit price. Defaults to [`Immediate`](@ref).

# Examples
```julia
# Fixed percentage stop loss
LowerBarrier(a -> a.entry_price * 0.95, Int8(-1))

# ATR-based stop loss exiting at next open
LowerBarrier(a -> a.entry_price - 2 * a.atr[a.idx], Int8(-1), NextOpen())

# EMA floor
LowerBarrier(a -> a.ema_20[a.idx], Int8(-1))
```
"""
struct LowerBarrier{F,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    UpperBarrier{F,E} <: AbstractBarrier

Triggers when the bar's high price is at or above the computed level, or when the
open price gaps above it. Typically used for take-profit barriers.

# Fields
- `level_func::F`: callable `(args::NamedTuple) -> AbstractFloat` returning the barrier level.
- `label::Int8`: label assigned on trigger (conventionally `1` for take-profit).
- `exit_basis::E`: execution basis for the exit price. Defaults to [`Immediate`](@ref).

# Examples
```julia
# Fixed percentage take profit
UpperBarrier(a -> a.entry_price * 1.10, Int8(1))

# ATR-based take profit
UpperBarrier(a -> a.entry_price + 3 * a.atr[a.idx], Int8(1))
```
"""
struct UpperBarrier{F,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    TimeBarrier{F,E} <: AbstractBarrier

Triggers when the bar's timestamp reaches or exceeds the computed time level.
Gaps do not apply to time barriers.

# Fields
- `level_func::F`: callable `(args::NamedTuple) -> TimeType` returning the expiry timestamp.
- `label::Int8`: label assigned on trigger (conventionally `0` for timeout).
- `exit_basis::E`: execution basis for the exit price. Defaults to [`Immediate`](@ref).

# Examples
```julia
# 10-day timeout
TimeBarrier(a -> a.entry_ts + Day(10), Int8(0))

# 5-day timeout exiting at next open
TimeBarrier(a -> a.entry_ts + Day(5), Int8(0), NextOpen())
```
"""
struct TimeBarrier{F,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    ConditionBarrier{F,E} <: AbstractBarrier

Triggers when an arbitrary boolean condition evaluates to `true`.
The `level_func` returns a `Bool` rather than a price or timestamp.
Gaps do not apply to condition barriers.

# Fields
- `level_func::F`: callable `(args::NamedTuple) -> Bool` returning the condition result.
- `label::Int8`: label assigned on trigger.
- `exit_basis::E`: execution basis for the exit price. Defaults to [`NextClose`](@ref).

# Examples
```julia
# EMA crossover exit
ConditionBarrier(a -> a.ema_10[a.idx] < a.ema_20[a.idx], Int8(-1))

# RSI overbought exit at next open
ConditionBarrier(a -> a.rsi[a.idx] > 70, Int8(1), NextOpen())
```
"""
struct ConditionBarrier{F,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

# ── Default constructors ──

LowerBarrier(f, label) = LowerBarrier(f, label, Immediate())
UpperBarrier(f, label) = UpperBarrier(f, label, Immediate())
TimeBarrier(f, label) = TimeBarrier(f, label, Immediate())
ConditionBarrier(f, label) = ConditionBarrier(f, label, NextClose())

# ── Barrier level computation ──

"""
    barrier_level(b::AbstractBarrier, args::NamedTuple)

Compute the barrier level by calling `b.level_func(args)`.

Returns:
- `AbstractFloat` for `LowerBarrier` / `UpperBarrier`.
- `TimeType` for `TimeBarrier`.
- `Bool` for `ConditionBarrier`.
"""
@inline barrier_level(b::AbstractBarrier, args::NamedTuple) = b.level_func(args)

# ── Gap detection ──

"""
    gap_hit(barrier::AbstractBarrier, level, open_price) -> Bool

Check whether the bar's opening price gapped through the barrier level.
Only applicable to price barriers (`LowerBarrier`, `UpperBarrier`).
Always returns `false` for `TimeBarrier` and `ConditionBarrier`.
"""
@inline gap_hit(::LowerBarrier, level, open_price) = open_price <= level
@inline gap_hit(::UpperBarrier, level, open_price) = open_price >= level
@inline gap_hit(::Union{TimeBarrier,ConditionBarrier}, ::Any, ::Any) = false

# ── Intrabar hit detection ──

"""
    barrier_hit(barrier::AbstractBarrier, level, low, high, ts) -> Bool

Check whether a barrier was triggered within the bar.

# Dispatch behaviour
- `LowerBarrier`: `low <= level`.
- `UpperBarrier`: `high >= level`.
- `TimeBarrier`: `ts >= level`.
- `ConditionBarrier`: returns `level` directly (which is already a `Bool`).
"""
@inline barrier_hit(::LowerBarrier, level, low, ::Any, ::Any) = low <= level
@inline barrier_hit(::UpperBarrier, level, ::Any, high, ::Any) = high >= level
@inline barrier_hit(::TimeBarrier, level::TimeType, ::Any, ::Any, ts::TimeType) =
    ts >= level
@inline barrier_hit(::ConditionBarrier, level, ::Any, ::Any, ::Any) = level