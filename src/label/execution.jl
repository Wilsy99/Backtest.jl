"""
    AbstractExecutionBasis

Abstract type representing when and how a trade entry or exit price is determined.

Subtypes control two behaviours:
- **Index adjustment** (`_get_idx_adj`): whether execution occurs on the current bar (`0`)
  or the next bar (`1`).
- **Price selection** (`_get_price`): which price field (open, close, or barrier level) is
  used for the execution price.

# Subtypes
- [`CurrentOpen`](@ref): execute at the current bar's open.
- [`CurrentClose`](@ref): execute at the current bar's close.
- [`NextOpen`](@ref): execute at the next bar's open.
- [`NextClose`](@ref): execute at the next bar's close.
- [`Immediate`](@ref): execute at the barrier level itself (for price barriers) or the
  current bar's close (for condition/time barriers).
"""
abstract type AbstractExecutionBasis end

"""
    CurrentOpen <: AbstractExecutionBasis

Execute at the current bar's opening price. Index adjustment: `0`.
"""
struct CurrentOpen <: AbstractExecutionBasis end

"""
    CurrentClose <: AbstractExecutionBasis

Execute at the current bar's closing price. Index adjustment: `0`.
"""
struct CurrentClose <: AbstractExecutionBasis end

"""
    NextOpen <: AbstractExecutionBasis

Execute at the next bar's opening price. Index adjustment: `1`.
"""
struct NextOpen <: AbstractExecutionBasis end

"""
    NextClose <: AbstractExecutionBasis

Execute at the next bar's closing price. Index adjustment: `1`.
"""
struct NextClose <: AbstractExecutionBasis end

"""
    Immediate <: AbstractExecutionBasis

Execute at the barrier level for price barriers (`LowerBarrier`, `UpperBarrier`), or at
the current bar's close for non-price barriers (`TimeBarrier`, `ConditionBarrier`).
Index adjustment: `0`.
"""
struct Immediate <: AbstractExecutionBasis end

"""
    _get_idx_adj(basis::AbstractExecutionBasis) -> Int

Return the bar index offset for the given execution basis.
Returns `0` for same-bar execution, `1` for next-bar execution.
"""
_get_idx_adj(::Union{CurrentOpen,CurrentClose,Immediate}) = 0
_get_idx_adj(::Union{NextOpen,NextClose}) = 1

"""
    _get_price(basis::AbstractExecutionBasis, level, idx::Int, args::NamedTuple)

Return the execution price for the given basis.

# Dispatch behaviour
- `CurrentOpen`, `NextOpen`: returns `args.bars.open[idx]`.
- `CurrentClose`, `NextClose`: returns `args.bars.close[idx]`.
- `Immediate` with `level::AbstractFloat`: returns `level` (the barrier price).
- `Immediate` with `level::Union{TimeType,Bool}`: returns `args.bars.close[idx]`
  (condition/time barriers have no meaningful price level).
"""
@inline _get_price(::Union{CurrentOpen,NextOpen}, ::Any, idx, args) = args.bars.open[idx]
@inline _get_price(::Union{CurrentClose,NextClose}, ::Any, idx, args) = args.bars.close[idx]
@inline _get_price(::Immediate, level::AbstractFloat, ::Any, ::Any) = level
@inline _get_price(::Immediate, ::Union{TimeType,Bool}, idx, args) = args.bars.close[idx]