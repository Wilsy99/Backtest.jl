include("crossover.jl")

"""
    (s::AbstractSide)(d::NamedTuple) -> NamedTuple

Compute side signals and merge them into the pipeline `NamedTuple`.

Delegate to `_side_result(s, d)` to obtain a `(side=...,)` tuple,
then merge it into `d`, preserving all upstream keys.

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with keys required by the specific side
implementation (e.g., fast and slow series for [`Crossover`](@ref)).

## Output
Return the input `NamedTuple` merged with:
- `side::Vector{Int8}`: side signals from the side detector.
"""
function (s::AbstractSide)(d::NamedTuple)
    return merge(d, _side_result(s, d))
end

"""
    _fill_sides_generic!(sides, from_idx, condition_func) -> Nothing

Fill `sides[from_idx:end]` by applying `condition_func(i)` at each
index. Use `@inbounds @simd` for vectorised execution.

Mutate `sides` in-place. This is the hot-path kernel for all side
detectors — it must remain zero-allocation and type-stable.
"""
@inline function _fill_sides_generic!(
    sides::AbstractVector{Int8}, from_idx::Int, condition_func::F
) where {F}
    @inbounds @simd for i in from_idx:length(sides)
        sides[i] = condition_func(i)
    end
end

# ── Macros ──

"""
    @Long(expr) -> Long

Construct a [`Long`](@ref) direction from a scalar condition expression
with automatic symbol rewriting and `lag` support.

Bare symbols are rewritten to indexed field access on the pipeline
data `d`:
- Bar fields (`close`, `open`, `high`, `low`, `volume`,
    `timestamp`) become `d.bars.field[i]`.
- All other symbols become `d.features.field[i]`.

Partial paths (`bars.close`, `features.ema_10`) and fully qualified
paths (`d.bars.close`) are normalised and indexed automatically.
Pre-indexed expressions (`close[i]`, `d.bars.close[i-1]`) are
recognised and left as-is (no double-indexing).

`lag(field, n)` is rewritten to `d.bars.field[i - n]` (or
`d.features.field[i - n]`), and a `warmup` guard is set so the
condition returns `false` for the first `n` bars, preventing
out-of-bounds access.

# Arguments
- `expr`: a Julia expression using bare symbols for pipeline fields.
    Supports `&&`, `||`, comparisons, arithmetic, and `lag(field, n)`
    for historical lookback.

# Returns
- `Long`: a direction functor wrapping the rewritten condition and
    the computed `warmup` period.

# Examples
```julia
# Simple feature crossover
side = Side(@Long(ema_10 > ema_20))

# With lag — automatically guarded for i <= 1
side = Side(@Long(ema_10 > ema_20 && close < lag(close, 1)))

# QuoteNode syntax also works
side = Side(@Long(:close > lag(:close, 2)))

# Partial and full paths are normalised
side = Side(@Long(bars.close > features.ema_20))
side = Side(@Long(d.bars.close > d.features.ema_20))
```

# See also
- [`@Short`](@ref): short direction macro with identical rewriting.
- [`Long`](@ref): the underlying type constructed by this macro.
- [`Side`](@ref): container that evaluates direction conditions
    per-bar.
"""
macro Long(ex)
    max_lag = Ref(0)
    body = _rewrite_side_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Long((d, i) -> $body, $warmup)))
end

"""
    @Short(expr) -> Short

Construct a [`Short`](@ref) direction from a scalar condition
expression with automatic symbol rewriting and `lag` support.

Identical rewriting rules to [`@Long`](@ref) — see its documentation
for the full symbol resolution and `lag` behaviour.

# Arguments
- `expr`: a Julia expression using bare symbols for pipeline fields.

# Returns
- `Short`: a direction functor wrapping the rewritten condition and
    the computed `warmup` period.

# Examples
```julia
side = Side(@Short(ema_10 < ema_20))

# Long and short in one Side — first match wins
side = Side(
    @Long(close > lag(close, 1)),
    @Short(close < lag(close, 1)),
)
```

# See also
- [`@Long`](@ref): long direction macro with identical rewriting.
- [`Short`](@ref): the underlying type constructed by this macro.
- [`Side`](@ref): container that evaluates direction conditions
    per-bar.
"""
macro Short(ex)
    max_lag = Ref(0)
    body = _rewrite_side_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Short((d, i) -> $body, $warmup)))
end

# ── AST Rewriting ──

"""
    _rewrite_side_expr(ex::Expr, max_lag::Ref{Int}) -> Expr

Recursively rewrite an expression AST for per-bar evaluation.

Dispatch on `ex.head` to handle each node type:
- `:ref` — pre-indexed access (`close[i]`): normalise the base,
    keep original indices unchanged (avoids rewriting `i` as data).
- `:.` — property access (`bars.close`): normalise and append `[i]`.
- `:call` with `lag` — rewrite `lag(field, n)` to
    `d.bars.field[i - n]` and update `max_lag`.
- `:call` (other) — recurse into arguments, skip the function name.
- `:comparison` — rewrite value positions only, skip operators.
- General (`:&&`, `:||`, etc.) — recurse into all arguments.
"""
function _rewrite_side_expr(ex::Expr, max_lag::Ref{Int})
    if ex.head == :ref
        base = ex.args[1]
        if base isa Symbol && _is_data_symbol(base)
            base = _resolve_sym(base)
        elseif base isa Expr && base.head == :.
            base = _normalize_dot(base)
        end
        return Expr(:ref, base, ex.args[2:end]...)
    end

    if ex.head == :.
        base = _normalize_dot(ex)
        return :($base[i])
    end

    if ex.head == :call
        if ex.args[1] == :lag
            length(ex.args) == 3 || error("lag requires exactly 2 arguments: lag(field, n)")
            raw = ex.args[2]
            n = ex.args[3]
            sym = raw isa QuoteNode ? raw.value : raw
            sym isa Symbol || error("First argument to lag must be a field name")
            n isa Integer || error("Second argument to lag must be an integer literal")
            max_lag[] = max(max_lag[], n)
            return :($(_resolve_sym(sym))[i - $n])
        else
            new_args = Any[ex.args[1]]
            for j in 2:length(ex.args)
                push!(new_args, _rewrite_side_expr(ex.args[j], max_lag))
            end
            return Expr(:call, new_args...)
        end
    end

    if ex.head == :comparison
        new_args = Any[]
        for (j, a) in enumerate(ex.args)
            if isodd(j)
                push!(new_args, _rewrite_side_expr(a, max_lag))
            else
                push!(new_args, a)
            end
        end
        return Expr(:comparison, new_args...)
    end

    return Expr(ex.head, [_rewrite_side_expr(a, max_lag) for a in ex.args]...)
end

"""Rewrite a bare `Symbol` to indexed data access (`d.bars.close[i]` or `d.features.ema[i]`)."""
function _rewrite_side_expr(sym::Symbol, ::Ref{Int})
    _is_data_symbol(sym) || return sym
    return :($(_resolve_sym(sym))[i])
end

"""Rewrite a `QuoteNode` (`:close`) to indexed data access."""
function _rewrite_side_expr(ex::QuoteNode, ::Ref{Int})
    sym = ex.value
    sym isa Symbol || return ex
    return :($(_resolve_sym(sym))[i])
end

# Fallback for literals (numbers, strings, etc.)
_rewrite_side_expr(ex, ::Ref{Int}) = ex

# ── Symbol Resolution Helpers ──

const _BAR_FIELDS = (:open, :high, :low, :close, :volume, :timestamp)
const _SKIP_SYMBOLS = (:NaN, :Inf, :pi, :nothing, :missing)

"""Return `true` if `sym` looks like a data field name (starts with a letter or underscore, not a Julia constant)."""
function _is_data_symbol(sym::Symbol)
    sym in _SKIP_SYMBOLS && return false
    s = string(sym)
    return !isempty(s) && (isletter(first(s)) || first(s) == '_')
end

"""Resolve a bare symbol to its qualified base without indexing. `close` → `d.bars.close`, `ema_10` → `d.features.ema_10`."""
function _resolve_sym(sym::Symbol)
    if sym in _BAR_FIELDS
        return :(d.bars.$sym)
    else
        return :(d.features.$sym)
    end
end

"""Normalise a dot-access expression by prepending `d.` when the root is `bars` or `features`."""
function _normalize_dot(ex::Expr)
    chain = _dot_chain(ex)
    chain === nothing && return ex

    if length(chain) >= 2 && chain[1] in (:bars, :features)
        pushfirst!(chain, :d)
    end

    return _build_dot(chain)
end

"""Extract a property chain from nested dot expressions. `d.bars.close` → `[:d, :bars, :close]`."""
function _dot_chain(ex::Expr)
    ex.head == :. || return nothing
    field = ex.args[2]
    field isa QuoteNode || return nothing
    parent = ex.args[1]
    if parent isa Symbol
        return Symbol[parent, field.value]
    elseif parent isa Expr
        chain = _dot_chain(parent)
        chain === nothing && return nothing
        push!(chain, field.value)
        return chain
    end
    return nothing
end

"""Build a nested dot expression from a chain of symbols. `[:d, :bars, :close]` → `d.bars.close`."""
function _build_dot(chain)
    ex = chain[1]
    for j in 2:length(chain)
        ex = Expr(:., ex, QuoteNode(chain[j]))
    end
    return ex
end

# ── Types ──

"""
    AbstractDirectionFunc

Supertype for direction condition wrappers used by [`Side`](@ref).

A direction functor pairs a per-bar condition function with a signal
value. When the condition matches at bar `i`, calling the functor
with no arguments returns the signal (`Int8(1)` for long,
`Int8(-1)` for short).

# Interface

Subtypes must implement:
- `dir.func::Function`: a `(d, i) -> Bool` condition function.
- `dir.warmup::Int`: number of leading bars to skip (lag guard).
- `dir()::Int8`: return the direction signal value.

# Existing Subtypes
- [`Long`](@ref): returns `Int8(1)` when matched.
- [`Short`](@ref): returns `Int8(-1)` when matched.

# See also
- [`Side`](@ref): container that evaluates direction conditions.
- [`@Long`](@ref), [`@Short`](@ref): macros for constructing
    directions from DSL expressions.
"""
abstract type AbstractDirectionFunc end

"""
    Long{F} <: AbstractDirectionFunc

Direction functor that produces `Int8(1)` (long) when its condition
matches.

# Fields
- `func::F`: a `(d::NamedTuple, i::Int) -> Bool` condition function
    evaluated at each bar index.
- `warmup::Int`: number of leading bars to skip. When using
    `lag(field, n)`, this is the maximum lag depth. Defaults to `0`.

# Constructors
    Long(func)              # warmup defaults to 0
    Long(func, warmup)      # explicit warmup period
    @Long(expr)             # macro: rewrites symbols and computes warmup

# Examples
```julia
# Manual construction with explicit warmup
long = Long((d, i) -> d.bars.close[i] > d.bars.close[i-1], 1)

# Macro construction (warmup computed automatically)
long = @Long(close > lag(close, 1))
```

# See also
- [`Short`](@ref): the short direction counterpart.
- [`@Long`](@ref): macro for constructing `Long` from DSL
    expressions.
- [`Side`](@ref): container that evaluates directions per-bar.
"""
struct Long{F} <: AbstractDirectionFunc
    func::F
    warmup::Int
end
Long(func) = Long(func, 0)
(::Long)() = Int8(1)

"""
    Short{F} <: AbstractDirectionFunc

Direction functor that produces `Int8(-1)` (short) when its condition
matches.

# Fields
- `func::F`: a `(d::NamedTuple, i::Int) -> Bool` condition function
    evaluated at each bar index.
- `warmup::Int`: number of leading bars to skip. When using
    `lag(field, n)`, this is the maximum lag depth. Defaults to `0`.

# Constructors
    Short(func)             # warmup defaults to 0
    Short(func, warmup)     # explicit warmup period
    @Short(expr)            # macro: rewrites symbols and computes warmup

# Examples
```julia
# Manual construction
short = Short((d, i) -> d.bars.close[i] < d.bars.close[i-1], 1)

# Macro construction
short = @Short(close < lag(close, 1))
```

# See also
- [`Long`](@ref): the long direction counterpart.
- [`@Short`](@ref): macro for constructing `Short` from DSL
    expressions.
- [`Side`](@ref): container that evaluates directions per-bar.
"""
struct Short{F} <: AbstractDirectionFunc
    func::F
    warmup::Int
end
Short(func) = Short(func, 0)
(::Short)() = Int8(-1)

"""
    Side{T<:Tuple}

Per-bar side detector that evaluates a tuple of
[`AbstractDirectionFunc`](@ref) conditions at each bar index.

Iterate over every bar in `d.bars`, evaluate each direction condition
in priority order (first match wins), and return a `Vector{Int8}` of
side signals merged into the pipeline `NamedTuple`.

# Type Parameters
- `T<:Tuple`: compile-time tuple type of the direction functors.

# Fields
- `directions::T`: tuple of [`Long`](@ref) and/or [`Short`](@ref)
    functors. Earlier entries take priority — at each bar, the first
    matching condition determines the signal.

# Constructors
    Side(directions...)

# Examples
```julia
# Long-only side detector
side = Side(@Long(ema_10 > ema_20))

# Long and short — first match wins at each bar
side = Side(
    @Long(close > lag(close, 1)),
    @Short(close < lag(close, 1)),
)

# Manual construction
side = Side(
    Long((d, i) -> d.features.ema_10[i] > d.features.ema_20[i]),
    Short((d, i) -> d.features.ema_10[i] < d.features.ema_20[i]),
)
```

# Pipeline Data Flow

## Input
Expect a `NamedTuple` with at least:
- `bars::PriceBars`: the price data (determines iteration range).
- `features::NamedTuple`: (optional) feature vectors referenced by
    the direction conditions.

## Output
Return the input `NamedTuple` merged with:
- `side::Vector{Int8}`: per-bar signals where `1` = long,
    `-1` = short, `0` = neutral.

# See also
- [`Long`](@ref), [`Short`](@ref): direction functors.
- [`@Long`](@ref), [`@Short`](@ref): macros for constructing
    directions from DSL expressions.
- [`Crossover`](@ref): alternative side detector based on moving
    average crossovers.
"""
struct Side{T<:Tuple}
    directions::T
end
Side(args...) = Side(args)

# ── Runtime ──

"""
    (side::Side)(d::NamedTuple) -> NamedTuple

Evaluate all direction conditions at each bar and merge the resulting
`side::Vector{Int8}` into the pipeline.

Iterate over `eachindex(d.bars)`, calling [`_check_side`](@ref) at
each index to determine the signal. Direction conditions with a
non-zero `warmup` are skipped for the first `warmup` bars to prevent
out-of-bounds access from `lag` lookbacks.

# Arguments
- `d::NamedTuple`: pipeline data with at least `bars::PriceBars`.

# Returns
- `NamedTuple`: the input merged with `side::Vector{Int8}`.
"""
function (side::Side)(d::NamedTuple)
    sides = Vector{Int8}(undef, length(d.bars))
    @inbounds for i in eachindex(d.bars)
        sides[i] = _check_side(side.directions, d, i)
    end

    return merge(d, (; side=sides))
end

"""Return `Int8(0)` (neutral) when no directions remain to check."""
_check_side(::Tuple{}, d::NamedTuple, i::Int) = Int8(0)

"""
    _check_side(directions::Tuple, d::NamedTuple, i::Int) -> Int8

Evaluate direction conditions recursively — first match wins.

Skip the condition when `i <= dir.warmup` to guard against
out-of-bounds access from `lag` lookbacks. Earlier directions in the
tuple take priority over later ones.
"""
@inline function _check_side(directions::Tuple, d::NamedTuple, i::Int)
    dir = first(directions)

    is_match = i > dir.warmup && dir.func(d, i)

    rest_val = _check_side(Base.tail(directions), d, i)

    return ifelse(is_match, dir(), rest_val)
end
