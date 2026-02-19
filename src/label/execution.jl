"""
    AbstractExecutionBasis

Supertype for all execution basis types that determine which price is
used for trade entry or barrier exit.

The execution basis controls two aspects of trade mechanics:

1. **Index adjustment**: whether the execution occurs on the current
   bar or the next bar (`_get_idx_adj`).
2. **Price selection**: which OHLC field is used as the fill price
   (`_get_price`).

# Interface

Subtypes must be singleton structs. The dispatch-based helper functions
`_get_idx_adj`, `_get_price`, `_temporal_priority`, and
`_get_exposure_adj` provide the behaviour for each basis.

# Existing Subtypes

- [`CurrentOpen`](@ref): fill at the current bar's open.
- [`CurrentClose`](@ref): fill at the current bar's close.
- [`NextOpen`](@ref): fill at the next bar's open.
- [`NextClose`](@ref): fill at the next bar's close.
- [`Immediate`](@ref): fill at the barrier level itself (for
    price-level barriers) or the current bar's close (for non-price
    barriers like [`TimeBarrier`](@ref)).

# See also
- [`UpperBarrier`](@ref), [`LowerBarrier`](@ref): barriers that use
    execution basis for exit pricing.
- [`Label`](@ref): uses `entry_basis` to determine entry fill price.
"""
abstract type AbstractExecutionBasis end

"""
    CurrentOpen <: AbstractExecutionBasis

Fill at the current bar's opening price. Index adjustment is zero.

# See also
- [`NextOpen`](@ref): same price field, next bar.
- [`CurrentClose`](@ref): same bar, close price.
"""
struct CurrentOpen <: AbstractExecutionBasis end

"""
    CurrentClose <: AbstractExecutionBasis

Fill at the current bar's closing price. Index adjustment is zero.

# See also
- [`NextClose`](@ref): same price field, next bar.
- [`CurrentOpen`](@ref): same bar, open price.
"""
struct CurrentClose <: AbstractExecutionBasis end

"""
    NextOpen <: AbstractExecutionBasis

Fill at the next bar's opening price. Index adjustment is `+1`.

This is the default `entry_basis` for [`Label`](@ref), reflecting the
assumption that an event detected on bar `t` can only be acted on at
the open of bar `t+1`.

# See also
- [`CurrentOpen`](@ref): same price field, current bar.
- [`NextClose`](@ref): next bar, close price.
"""
struct NextOpen <: AbstractExecutionBasis end

"""
    NextClose <: AbstractExecutionBasis

Fill at the next bar's closing price. Index adjustment is `+1`.

# See also
- [`CurrentClose`](@ref): same price field, current bar.
- [`NextOpen`](@ref): next bar, open price.
"""
struct NextClose <: AbstractExecutionBasis end

"""
    Immediate <: AbstractExecutionBasis

Fill at the barrier level itself when the barrier is a price-level
barrier ([`UpperBarrier`](@ref), [`LowerBarrier`](@ref)), or at the
current bar's close for non-price barriers ([`TimeBarrier`](@ref),
[`ConditionBarrier`](@ref)). Index adjustment is zero.

This is the default `exit_basis` for price-level barriers, modelling
the assumption that a stop/take-profit order fills at exactly the
barrier level.

# See also
- [`NextOpen`](@ref): the default `exit_basis` for
    [`ConditionBarrier`](@ref).
"""
struct Immediate <: AbstractExecutionBasis end

"""
    _temporal_priority(basis::AbstractExecutionBasis) -> Int

Return an integer priority for barrier ordering warnings.

Lower values indicate earlier execution within a bar. When multiple
barriers trigger on the same bar, the first-listed barrier wins. This
function helps `_warn_barrier_ordering` detect cases where a
later-executing barrier is listed before an earlier-executing one.

Priority order: `Immediate`(1) < `CurrentOpen`(2) < `CurrentClose`(3)
< `NextOpen`(4) < `NextClose`(5).
"""
_temporal_priority(::Immediate) = 1
_temporal_priority(::CurrentOpen) = 2
_temporal_priority(::CurrentClose) = 3
_temporal_priority(::NextOpen) = 4
_temporal_priority(::NextClose) = 5

"""
    _get_idx_adj(basis::AbstractExecutionBasis) -> Int

Return the bar index offset for the given execution basis.

`Current*` and `Immediate` bases return `0` (execute on the trigger
bar). `Next*` bases return `1` (execute on the following bar).
"""
_get_idx_adj(::Union{CurrentOpen,CurrentClose,Immediate}) = 0
_get_idx_adj(::Union{NextOpen,NextClose}) = 1

"""
    _get_price(basis::AbstractExecutionBasis, level, idx::Int, args) -> AbstractFloat

Return the fill price for the given execution basis at bar `idx`.

- `CurrentOpen` / `NextOpen`: return `args.bars.open[idx]`.
- `CurrentClose` / `NextClose`: return `args.bars.close[idx]`.
- `Immediate` with a float `level`: return `level` directly (barrier
    fill at the exact barrier price).
- `Immediate` with a non-price `level` (`TimeType` or `Bool`): fall
    back to `args.bars.close[idx]`.
"""
@inline _get_price(::Union{CurrentOpen,NextOpen}, ::Any, idx, args) = args.bars.open[idx]
@inline _get_price(::Union{CurrentClose,NextClose}, ::Any, idx, args) = args.bars.close[idx]
@inline _get_price(::Immediate, level::AbstractFloat, ::Any, ::Any) = level
# TimeBarrier and ConditionBarrier levels are non-price values
@inline _get_price(::Immediate, ::Union{TimeType,Bool}, idx, args) = args.bars.close[idx]

"""
    _get_exposure_adj(basis::AbstractExecutionBasis) -> Int

Return the exposure offset for attribution weight calculation.

Open-based and Immediate entries are exposed from the entry bar
onward (offset `0`). Close-based entries are only exposed starting
from the next bar (offset `1`), since the close price is not
actionable until the bar completes.
"""
_get_exposure_adj(::Union{CurrentOpen,NextOpen,Immediate}) = 0
_get_exposure_adj(::Union{CurrentClose,NextClose}) = 1
