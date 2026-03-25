# ── Macros ──

"""
    @Long(expr)

Construct a `Long` direction from a scalar condition expression with automatic
symbol rewriting and `lag` support.

Bare symbols are rewritten to indexed field access on the pipeline data `d`:
- Bar fields (`close`, `open`, `high`, `low`, `volume`, `timestamp`) → `d.bars.field[i]`
- Everything else → `d.features.field[i]`

`lag(field, n)` is rewritten to `d.bars.field[i - n]` (or `d.features.field[i - n]`),
and a warmup guard is automatically added so the condition returns `false` for
the first `n` bars.

# Examples
```julia
# Simple feature crossover
side = Side(@Long(ema_10 > ema_20))

# With lag — automatically guarded for i <= 1
side = Side(@Long(ema_10 > ema_20 && close < lag(close, 1)))

# QuoteNode syntax also works
side = Side(@Long(:close > lag(:close, 2)))
```
"""
macro Long(ex)
    max_lag = Ref(0)
    body = _rewrite_side_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Long((d, i) -> $body, $warmup)))
end

"""
    @Short(expr)

Construct a `Short` direction from a scalar condition expression.

Same rewriting rules as [`@Long`](@ref) — see its documentation for details.

# Examples
```julia
side = Side(@Short(ema_10 < ema_20))
side = Side(@Long(close > lag(close, 1)), @Short(close < lag(close, 1)))
```
"""
macro Short(ex)
    max_lag = Ref(0)
    body = _rewrite_side_expr(ex, max_lag)
    warmup = max_lag[]
    return esc(:(Short((d, i) -> $body, $warmup)))
end

# ── AST Rewriting ──

function _rewrite_side_expr(ex::Expr, max_lag::Ref{Int})
    # Indexing: close[i], bars.close[i-1], d.bars.close[i], etc.
    # Normalize the base, keep original index expressions unchanged (don't rewrite i).
    if ex.head == :ref
        base = ex.args[1]
        if base isa Symbol && _is_data_symbol(base)
            base = _resolve_sym(base)
        elseif base isa Expr && base.head == :.
            base = _normalize_dot(base)
        end
        return Expr(:ref, base, ex.args[2:end]...)
    end

    # Property access: bars.close, d.features.ema_20, etc.
    # Normalize and append [i].
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
            # Recurse into arguments but skip the function name (position 1)
            new_args = Any[ex.args[1]]
            for j in 2:length(ex.args)
                push!(new_args, _rewrite_side_expr(ex.args[j], max_lag))
            end
            return Expr(:call, new_args...)
        end
    end

    # Chained comparisons: a < b < c → Expr(:comparison, a, <, b, <, c)
    # Only rewrite value positions (odd indices), not operator positions (even)
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

    # General case (&&, ||, etc.): recurse into all args
    return Expr(ex.head, [_rewrite_side_expr(a, max_lag) for a in ex.args]...)
end

function _rewrite_side_expr(sym::Symbol, ::Ref{Int})
    _is_data_symbol(sym) || return sym
    return :($(_resolve_sym(sym))[i])
end

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

function _is_data_symbol(sym::Symbol)
    sym in _SKIP_SYMBOLS && return false
    s = string(sym)
    return !isempty(s) && (isletter(first(s)) || first(s) == '_')
end

# Resolve a bare symbol to its qualified base (no [i]).
# close → d.bars.close, ema_10 → d.features.ema_10
function _resolve_sym(sym::Symbol)
    if sym in _BAR_FIELDS
        return :(d.bars.$sym)
    else
        return :(d.features.$sym)
    end
end

# Normalize a dot chain: bars.close → d.bars.close, features.ema → d.features.ema
function _normalize_dot(ex::Expr)
    chain = _dot_chain(ex)
    chain === nothing && return ex

    # bars.X → d.bars.X, features.X → d.features.X
    if length(chain) >= 2 && chain[1] in (:bars, :features)
        pushfirst!(chain, :d)
    end

    return _build_dot(chain)
end

# Extract property chain from nested dot exprs: d.bars.close → [:d, :bars, :close]
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

# Build d.x.y from a chain of symbols
function _build_dot(chain)
    ex = chain[1]
    for j in 2:length(chain)
        ex = Expr(:., ex, QuoteNode(chain[j]))
    end
    return ex
end

# ── Types ──

abstract type AbstractDirectionFunc end

struct Long{F} <: AbstractDirectionFunc
    func::F
    warmup::Int
end
Long(func) = Long(func, 0)
(::Long)() = Int8(1)

struct Short{F} <: AbstractDirectionFunc
    func::F
    warmup::Int
end
Short(func) = Short(func, 0)
(::Short)() = Int8(-1)

struct Side{T<:Tuple}
    directions::T
end
Side(args...) = Side(args)

# ── Runtime ──

function (side::Side)(d::NamedTuple)
    sides = Vector{Int8}(undef, length(d.bars))
    @inbounds for i in eachindex(d.bars)
        sides[i] = _check_side(side.directions, d, i)
    end

    return merge(d, (; side=sides))
end

_check_side(::Tuple{}, d::NamedTuple, i::Int) = Int8(0)

# Recursive case: evaluates all directions (first match wins).
# Earlier directions in the tuple take priority over later ones.
# Guards against out-of-bounds access when i <= warmup (lag period).
@inline function _check_side(directions::Tuple, d::NamedTuple, i::Int)
    dir = first(directions)

    is_match = i > dir.warmup && dir.func(d, i)

    rest_val = _check_side(Base.tail(directions), d, i)

    return ifelse(is_match, dir(), rest_val)
end
