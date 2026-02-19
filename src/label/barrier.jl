"""
    LowerBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier

Barrier triggered when the bar's low price falls at or below the
barrier level, or when the bar opens below it (gap down).

Used to model stop-loss exits for long positions or take-profit exits
for short positions.

# Fields
- `level_func::F`: function `(args) -> price_level` computing the
    barrier threshold from the loop context.
- `label::Int8`: label assigned when this barrier triggers. Default
    `Int8(-1)`.
- `exit_basis::E`: execution basis for the exit fill price. Default
    [`Immediate`](@ref) (fill at the barrier level).

# Constructors
    LowerBarrier(f::Function; label=-1, exit_basis=Immediate())

# Examples
```julia
# Fixed 5% stop below entry
lb = LowerBarrier(d -> d.entry_price * 0.95)

# Custom label and exit basis
lb = LowerBarrier(d -> d.entry_price * 0.95; label=-2, exit_basis=NextOpen())
```

# See also
- [`UpperBarrier`](@ref): upper (take-profit) barrier.
- [`@LowerBarrier`](@ref): DSL macro for constructing `LowerBarrier`.
- [`barrier_level`](@ref), [`gap_hit`](@ref), [`barrier_hit`](@ref):
    the dispatch interface for barrier checking.
"""
struct LowerBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    UpperBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier

Barrier triggered when the bar's high price reaches or exceeds the
barrier level, or when the bar opens above it (gap up).

Used to model take-profit exits for long positions or stop-loss exits
for short positions.

# Fields
- `level_func::F`: function `(args) -> price_level` computing the
    barrier threshold from the loop context.
- `label::Int8`: label assigned when this barrier triggers. Default
    `Int8(1)`.
- `exit_basis::E`: execution basis for the exit fill price. Default
    [`Immediate`](@ref) (fill at the barrier level).

# Constructors
    UpperBarrier(f::Function; label=1, exit_basis=Immediate())

# Examples
```julia
# Fixed 5% take-profit above entry
ub = UpperBarrier(d -> d.entry_price * 1.05)
```

# See also
- [`LowerBarrier`](@ref): lower (stop-loss) barrier.
- [`@UpperBarrier`](@ref): DSL macro for constructing `UpperBarrier`.
"""
struct UpperBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    TimeBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier

Barrier triggered when the bar's timestamp reaches or exceeds a
computed deadline.

Used to enforce a maximum holding period. The level function must
return a `TimeType` (e.g., `DateTime`).

# Fields
- `level_func::F`: function `(args) -> TimeType` computing the
    expiry timestamp from the loop context.
- `label::Int8`: label assigned when this barrier triggers. Default
    `Int8(0)` (neutral / no-signal).
- `exit_basis::E`: execution basis for the exit fill price. Default
    [`Immediate`](@ref).

# Constructors
    TimeBarrier(f::Function; label=0, exit_basis=Immediate())

# Examples
```julia
using Dates
# Exit after 20 trading days
tb = TimeBarrier(d -> d.entry_ts + Day(20))
```

# See also
- [`@TimeBarrier`](@ref): DSL macro for constructing `TimeBarrier`.
- [`ConditionBarrier`](@ref): barrier based on arbitrary boolean
    conditions.
"""
struct TimeBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

"""
    ConditionBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier

Barrier triggered when an arbitrary boolean condition evaluates to
`true`.

The level function must return a `Bool`. Unlike price barriers, the
default `exit_basis` is [`NextOpen`](@ref), reflecting the assumption
that a condition observed at bar close can only be acted on at the
next bar's open.

# Fields
- `level_func::F`: function `(args) -> Bool` evaluating the exit
    condition from the loop context.
- `label::Int8`: label assigned when this barrier triggers. Default
    `Int8(0)`.
- `exit_basis::E`: execution basis for the exit fill price. Default
    [`NextOpen`](@ref).

# Constructors
    ConditionBarrier(f::Function; label=0, exit_basis=NextOpen())

# Examples
```julia
# Exit when short EMA crosses below long EMA
cb = ConditionBarrier(d -> d.ema_10[d.idx] < d.ema_50[d.idx])
```

# See also
- [`@ConditionBarrier`](@ref): DSL macro for constructing
    `ConditionBarrier`.
- [`TimeBarrier`](@ref): time-based exit.
"""
struct ConditionBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

LowerBarrier(f; label=-1, exit_basis=Immediate()) = LowerBarrier(f, label, exit_basis)
UpperBarrier(f; label=1, exit_basis=Immediate()) = UpperBarrier(f, label, exit_basis)
TimeBarrier(f; label=0, exit_basis=Immediate()) = TimeBarrier(f, label, exit_basis)

function ConditionBarrier(f; label=0, exit_basis=NextOpen())
    return ConditionBarrier(f, label, exit_basis)
end

# ── Barrier testing interface ──
#
# These three functions form the dispatch contract for barrier
# checking inside _check_barrier_recursive!.

"""
    barrier_level(b::AbstractBarrier, args) -> Any

Evaluate the barrier's level function with the current loop context.

Return type depends on barrier kind: a price (`AbstractFloat`) for
[`UpperBarrier`](@ref)/[`LowerBarrier`](@ref), a `DateTime` for
[`TimeBarrier`](@ref), or a `Bool` for [`ConditionBarrier`](@ref).
"""
@inline barrier_level(b::AbstractBarrier, args) = b.level_func(args)

"""
    gap_hit(barrier::AbstractBarrier, level, open_price) -> Bool

Check whether the bar opened past the barrier level (gap through).

Only meaningful for price barriers: `LowerBarrier` triggers when
`open_price <= level`; `UpperBarrier` triggers when
`open_price >= level`. Time and condition barriers always return
`false`.
"""
@inline gap_hit(::LowerBarrier, level, open_price) = open_price <= level
@inline gap_hit(::UpperBarrier, level, open_price) = open_price >= level
@inline gap_hit(::Union{TimeBarrier,ConditionBarrier}, ::Any, ::Any) = false

"""
    barrier_hit(barrier::AbstractBarrier, level, low, high, ts) -> Bool

Check whether the barrier was hit during the bar's trading range.

- `LowerBarrier`: hit when `low <= level`.
- `UpperBarrier`: hit when `high >= level`.
- `TimeBarrier`: hit when `ts >= level` (timestamp comparison).
- `ConditionBarrier`: hit when `level` is `true` (the level function
    itself returns the boolean condition result).
"""
@inline barrier_hit(::LowerBarrier, level, low, ::Any, ::Any) = low <= level
@inline barrier_hit(::UpperBarrier, level, ::Any, high, ::Any) = high >= level
@inline barrier_hit(::TimeBarrier, level::TimeType, ::Any, ::Any, ts::TimeType) =
    ts >= level
@inline barrier_hit(::ConditionBarrier, level, ::Any, ::Any, ::Any) = level

struct BarrierContext end

"""
    _build_barrier_expr(type::Symbol, default_label, args) -> Expr

Build an escaped constructor expression for a barrier macro.

Parse `args` via `_build_macro_components` to separate the level
expression from keyword arguments. If the user did not supply a
`label` keyword, inject the `default_label` for the barrier type.
"""
function _build_barrier_expr(type::Symbol, default_label, args)
    funcs, kwargs = _build_macro_components(BarrierContext(), args)
    has_label = any(kw -> kw.args[1] == :label, kwargs)
    if has_label
        return esc(:($type($(funcs[1]); $(kwargs...))))
    else
        return esc(:($type($(funcs[1]); label=$default_label, $(kwargs...))))
    end
end

"""
    @UpperBarrier expr [key=val ...]

Construct an [`UpperBarrier`](@ref) using a DSL expression with
automatic symbol rewriting.

Symbols prefixed with `:` are rewritten to access fields of the
barrier loop context `d`:
- `:entry_price`, `:entry_ts`, `:idx` → `d.field`
- `:open`, `:high`, `:low`, `:close`, `:volume`, `:timestamp` →
    `d.bars.field[d.idx]`
- All other symbols (e.g., `:ema_10`) → `d.symbol[d.idx]`

Default label is `Int8(1)`.

# Examples
```julia
ub = @UpperBarrier :entry_price * 1.05
ub = @UpperBarrier :entry_price + (:ema_10 - :ema_50) label=2
```

# See also
- [`UpperBarrier`](@ref): the underlying type.
- [`@LowerBarrier`](@ref): lower barrier macro.
"""
macro UpperBarrier(ex, args...)
    return _build_barrier_expr(:UpperBarrier, 1, (ex, args...))
end

"""
    @LowerBarrier expr [key=val ...]

Construct a [`LowerBarrier`](@ref) using a DSL expression with
automatic symbol rewriting.

Symbol rewriting rules are identical to [`@UpperBarrier`](@ref).
Default label is `Int8(-1)`.

# Examples
```julia
lb = @LowerBarrier :entry_price * 0.95
lb = @LowerBarrier 0.95 * :entry_price - 2.0
```

# See also
- [`LowerBarrier`](@ref): the underlying type.
- [`@UpperBarrier`](@ref): upper barrier macro.
"""
macro LowerBarrier(ex, args...)
    return _build_barrier_expr(:LowerBarrier, -1, (ex, args...))
end

"""
    @TimeBarrier expr [key=val ...]

Construct a [`TimeBarrier`](@ref) using a DSL expression with
automatic symbol rewriting.

Symbol rewriting rules are identical to [`@UpperBarrier`](@ref).
Default label is `Int8(0)`.

# Examples
```julia
using Dates
tb = @TimeBarrier :entry_ts + Day(20)
```

# See also
- [`TimeBarrier`](@ref): the underlying type.
"""
macro TimeBarrier(ex, args...)
    return _build_barrier_expr(:TimeBarrier, 0, (ex, args...))
end

"""
    @ConditionBarrier expr [key=val ...]

Construct a [`ConditionBarrier`](@ref) using a DSL expression with
automatic symbol rewriting.

Symbol rewriting rules are identical to [`@UpperBarrier`](@ref).
Default label is `Int8(0)`.

# Examples
```julia
cb = @ConditionBarrier :close <= :entry_price
cb = @ConditionBarrier :ema_10 < :ema_50 && :close <= :entry_price
```

# See also
- [`ConditionBarrier`](@ref): the underlying type.
"""
macro ConditionBarrier(ex, args...)
    return _build_barrier_expr(:ConditionBarrier, 0, (ex, args...))
end

"""
    _replace_symbols(::BarrierContext, ex::QuoteNode) -> Expr

Rewrite a quoted symbol to a field access on the barrier loop
variable `d`.

Three routing categories:
- **Direct fields** (`:entry_price`, `:entry_ts`, `:idx`): rewritten
    to `d.field` — these are scalar values in the loop context.
- **Bar fields** (`:open`, `:high`, `:low`, `:close`, `:volume`,
    `:timestamp`): rewritten to `d.bars.field[d.idx]` — indexed into
    the price bar arrays at the current bar.
- **All other symbols** (e.g., `:ema_10`): rewritten to
    `d.symbol[d.idx]` — assumed to be feature vectors indexed at the
    current bar.
"""
function _replace_symbols(::BarrierContext, ex::QuoteNode)
    direct_fields = (:entry_price, :entry_ts, :idx)
    bars_fields = (:open, :high, :low, :close, :volume, :timestamp)
    if ex.value in direct_fields
        return :(d.$(ex.value))
    elseif ex.value in bars_fields
        return :(d.bars.$(ex.value)[d.idx])
    else
        return :(d.$(ex.value)[d.idx])
    end
end
