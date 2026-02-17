"""
    Crossover{D<:AbstractDirection, Fast, Slow, Wait} <: AbstractSide

Moving average crossover side detector parameterised by fast and slow
series names, a direction filter, and a wait-for-cross flag.

Determine trade side (`Int8(1)` for long, `Int8(-1)` for short,
`Int8(0)` for neutral) by comparing a fast-moving series against a
slow-moving series. When the fast series crosses above the slow
series, a long signal is produced; when it crosses below, a short
signal is produced.

# Type Parameters
- `D<:AbstractDirection`: direction filter ([`LongOnly`](@ref),
    [`ShortOnly`](@ref), or [`LongShort`](@ref)).
- `Fast::Symbol`: name of the fast series key in the pipeline
    `NamedTuple` (e.g., `:ema_10`). `nothing` when using the
    positional `calculate_side` interface.
- `Slow::Symbol`: name of the slow series key in the pipeline
    `NamedTuple` (e.g., `:ema_50`). `nothing` when using the
    positional `calculate_side` interface.
- `Wait::Bool`: if `true`, output zeros until the first actual
    crossover occurs. If `false`, start emitting signals from the
    first valid index.

# Constructors
    Crossover(fast::Symbol, slow::Symbol; wait_for_cross=true, direction=LongShort())
    Crossover(; wait_for_cross=true, direction=LongShort())

The two-argument form binds the fast/slow series names for pipeline
use. The zero-argument form creates a `Crossover` with
`Fast=nothing, Slow=nothing` for use with `calculate_side` directly.

# Examples
```jldoctest
julia> using Backtest

julia> c = Crossover(:ema_10, :ema_50);

julia> c isa AbstractSide
true

julia> c2 = Crossover(:ema_10, :ema_50; direction=LongOnly());

julia> c2 isa AbstractSide
true
```

# See also
- [`calculate_side`](@ref): compute crossover signals from two
    series.
- [`LongOnly`](@ref), [`ShortOnly`](@ref), [`LongShort`](@ref):
    direction filters.

# Extended help

## Callable Interface

`Crossover` instances are callable. When called with a `NamedTuple`
from a previous pipeline stage, they extract the fast and slow
series by name, compute side signals, and merge the result:

```julia
bars = get_data("AAPL")
result = (bars >> EMA(10, 50) >> Crossover(:ema_10, :ema_50))()
# result is a NamedTuple with fields :bars, :ema_10, :ema_50, :side
```

## Pipeline Data Flow

### Input
Expect a `NamedTuple` with at least:
- `Fast::Symbol` key: the fast series (`AbstractVector{T}`).
- `Slow::Symbol` key: the slow series (`AbstractVector{T}`).

### Output
Return the input `NamedTuple` merged with:
- `side::Vector{Int8}`: side signals where `1` = long, `-1` = short,
    `0` = neutral.

## Wait-for-Cross Behaviour

When `wait_for_cross=true` (default), the output is all zeros until
the first crossover event. This prevents stale signals from a
pre-existing position at the start of the data. When `false`, signals
begin immediately from the first index where the slow series is valid
(not NaN).

## Direction Filtering

- [`LongOnly`](@ref): emit `Int8(1)` when fast > slow, `Int8(0)`
    otherwise.
- [`ShortOnly`](@ref): emit `Int8(-1)` when fast < slow, `Int8(0)`
    otherwise.
- [`LongShort`](@ref): emit `Int8(1)` when fast > slow, `Int8(-1)`
    when fast < slow, `Int8(0)` when equal.
"""
struct Crossover{D<:AbstractDirection,Fast,Slow,Wait} <: AbstractSide
    function Crossover{D,Fast,Slow,Wait}() where {D<:AbstractDirection,Fast,Slow,Wait}
        return new{D,Fast,Slow,Wait}()
    end
end

function Crossover(
    fast::Symbol,
    slow::Symbol;
    wait_for_cross::Bool=true,
    direction::AbstractDirection=LongShort(),
)
    return Crossover{typeof(direction),fast,slow,wait_for_cross}()
end

function Crossover(; wait_for_cross::Bool=true, direction::AbstractDirection=LongShort())
    return Crossover{typeof(direction),nothing,nothing,wait_for_cross}()
end

"""
    _side_result(side::Crossover{D,Fast,Slow,Wait}, d::NamedTuple) -> NamedTuple

Extract the fast and slow series from the pipeline `NamedTuple` by
their bound names (`Fast`, `Slow`), compute crossover signals via
[`calculate_side`](@ref), and return `(side=vals,)`.

This is the bridge between the callable interface and the raw
`calculate_side` function, analogous to `_feature_result` for
features.
"""
function _side_result(
    side::Crossover{D,Fast,Slow,Wait}, d::NamedTuple
) where {D,Fast,Slow,Wait}
    vals = calculate_side(side, d[Fast], d[Slow])
    return (side=vals,)
end

"""
    calculate_side(::Crossover{D,Fast,Slow,Wait}, fast_series::AbstractVector{T}, slow_series::AbstractVector{T}) where {D,Fast,Slow,Wait,T<:AbstractFloat} -> Vector{Int8}

Compute crossover side signals by comparing `fast_series` against
`slow_series`.

Return a `Vector{Int8}` of length `length(fast_series)` where each
entry is `Int8(1)` (long), `Int8(-1)` (short), or `Int8(0)`
(neutral). The output respects the direction filter `D` and the
wait-for-cross flag `Wait`.

# Arguments
- `side::Crossover{D,Fast,Slow,Wait}`: the crossover instance.
- `fast_series::AbstractVector{T}`: the fast-moving series.
- `slow_series::AbstractVector{T}`: the slow-moving series. Must
    have the same length as `fast_series`.

# Returns
- `Vector{Int8}`: side signals. Leading entries are `Int8(0)` until
    the slow series becomes valid (non-NaN). When `Wait=true`,
    additional zeros precede the first crossover.

# Examples
```jldoctest
julia> using Backtest

julia> fast = Float64[1, 2, 3, 4, 5];

julia> slow = Float64[5, 4, 3, 2, 1];

julia> sides = calculate_side(Crossover(), fast, slow);

julia> sides[end]
1
```

# See also
- [`Crossover`](@ref): constructor and type documentation.
"""
function calculate_side(
    ::Crossover{D,Fast,Slow,Wait},
    fast_series::AbstractVector{T},
    slow_series::AbstractVector{T},
) where {D<:AbstractDirection,Fast,Slow,Wait,T<:AbstractFloat}
    return _calculate_cross_sides(fast_series, slow_series, Val(Wait), D())
end

"""
    _calculate_cross_sides(fast_series, slow_series, ::Val{Wait}, dir) -> Vector{Int8}

Core crossover computation. Allocate a result vector of `Int8(0)`,
find the first valid (non-NaN) index in `slow_series`, then fill
side signals using direction-dispatched condition functions.

When `Wait=true`, skip to the first actual crossover before emitting
signals. When `Wait=false`, emit from the first valid index.
"""
function _calculate_cross_sides(
    fast_series::AbstractVector{T}, slow_series::AbstractVector{T}, ::Val{Wait}, dir::D
) where {T<:AbstractFloat,Wait,D<:AbstractDirection}
    n = length(fast_series)
    sides = zeros(Int8, n)

    start_idx = findfirst(!isnan, slow_series)
    isnothing(start_idx) && return sides

    cond_f = _get_condition_func(fast_series, slow_series, dir)

    if !Wait
        _fill_sides_generic!(sides, start_idx, cond_f)
        return sides
    end

    first_cross = _find_first_cross(fast_series, slow_series, start_idx, dir)

    if first_cross != -1
        _fill_sides_generic!(sides, first_cross, cond_f)
    end

    return sides
end

# ── Condition functions: dispatched by direction ──

"""Return a closure that maps index `i` to `Int8(1)` when fast > slow, else `Int8(0)`."""
@inline function _get_condition_func(fast, slow, ::LongOnly)
    return i -> @inbounds ifelse(fast[i] > slow[i], Int8(1), Int8(0))
end

"""Return a closure that maps index `i` to `Int8(-1)` when fast < slow, else `Int8(0)`."""
@inline function _get_condition_func(fast, slow, ::ShortOnly)
    return i -> @inbounds ifelse(fast[i] < slow[i], Int8(-1), Int8(0))
end

"""Return a closure that maps index `i` to `Int8(1)` when fast > slow, `Int8(-1)` when fast < slow, else `Int8(0)`."""
@inline function _get_condition_func(fast, slow, ::LongShort)
    return i -> @inbounds begin
        f, s = fast[i], slow[i]
        ifelse(f > s, Int8(1), ifelse(f < s, Int8(-1), Int8(0)))
    end
end

# ── Find first cross: dispatched by direction ──

"""
    _find_first_cross(fast, slow, start_idx, dir) -> Int

Scan from `start_idx + 1` for the first index where a crossover
occurs. Return the index, or `-1` if no crossover is found.

For [`LongOnly`](@ref): the fast series must first be at or below
the slow series, then cross above. For [`ShortOnly`](@ref): vice
versa. For [`LongShort`](@ref): any change in relative position
counts.
"""
@inline function _find_first_cross(fast, slow, start_idx, ::LongOnly)
    n = length(fast)
    @inbounds has_been_below = fast[start_idx] <= slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        f_val = fast[i]
        s_val = slow[i]
        if has_been_below && f_val > s_val
            return i
        elseif f_val <= s_val
            has_been_below = true
        end
    end
    return -1
end

@inline function _find_first_cross(fast, slow, start_idx, ::ShortOnly)
    n = length(fast)
    @inbounds has_been_above = fast[start_idx] >= slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        f_val = fast[i]
        s_val = slow[i]
        if has_been_above && f_val < s_val
            return i
        elseif f_val >= s_val
            has_been_above = true
        end
    end
    return -1
end

@inline function _find_first_cross(fast, slow, start_idx, ::LongShort)
    n = length(fast)
    @inbounds prev_above = fast[start_idx] > slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        curr_above = fast[i] > slow[i]
        if curr_above != prev_above
            return i
        end
        prev_above = curr_above
    end
    return -1
end
