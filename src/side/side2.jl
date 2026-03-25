abstract type AbstractDirectionFunc end

struct Long{F} <: AbstractDirectionFunc
    func::F
    min_bar::Int
end
Long(f) = Long(f, 1)
(long::Long)() = Int8(1)

struct Short{F} <: AbstractDirectionFunc
    func::F
    min_bar::Int
end
Short(f) = Short(f, 1)
(short::Short)() = Int8(-1)

struct Side{T<:Tuple}
    directions::T
end
Side(args...) = Side(args)

function (side::Side)(d::NamedTuple)
    n = length(d.bars)
    sides = zeros(Int8, n)
    start = maximum(dir.min_bar for dir in side.directions; init=1)
    @inbounds for i in start:n
        sides[i] = _check_side(side.directions, d, i)
    end

    return merge(d, (; side=sides))
end

_check_side(::Tuple{}, d::NamedTuple, i::Int) = Int8(0)

# Recursive case: evaluates all directions (first match wins).
# Earlier directions in the tuple take priority over later ones.
@inline function _check_side(directions::Tuple, d::NamedTuple, i::Int)
    dir = first(directions)

    is_match = dir.func(d, i)

    rest_val = _check_side(Base.tail(directions), d, i)

    return ifelse(is_match, dir(), rest_val)
end

# ---------------------------------------------------------------------------
# Macro DSL for trading conditions
# ---------------------------------------------------------------------------

struct SideContext end

const _SIDE_BARS_FIELDS = (:open, :high, :low, :close, :volume, :timestamp)
const _SIDE_RESERVED    = (:d, :i, :true, :false, :nothing, :missing,
                           :Inf, :NaN, :pi, :e, :Inf32, :NaN32)
const _SIDE_BROADCAST_OPS = Dict{Symbol,Symbol}(
    :.>  => :>,
    :.<  => :<,
    :.>= => :>=,
    :.<= => :<=,
    :.== => :(==),
    :.!= => :!=,
)

# Quoted symbol: :close, :ema_10
function _replace_symbols(::SideContext, ex::QuoteNode)
    if ex.value in _SIDE_BARS_FIELDS
        return :(d.bars.$(ex.value)[i])
    else
        return :(d.features.$(ex.value)[i])
    end
end

# Bare symbol: close, ema_10  (appears in macro AST as Symbol nodes)
function _replace_symbols(::SideContext, ex::Symbol)
    ex in _SIDE_RESERVED && return ex
    if ex in _SIDE_BARS_FIELDS
        return :(d.bars.$ex[i])
    else
        return :(d.features.$ex[i])
    end
end

# Compound expressions
function _replace_symbols(ctx::SideContext, ex::Expr)
    # lag(field, n)  →  d.bars.field[i-n]  or  d.features.field[i-n]
    if ex.head == :call && length(ex.args) >= 3 && ex.args[1] == :lag
        field_ex = ex.args[2]
        n        = ex.args[3]
        field_sym = isa(field_ex, QuoteNode) ? field_ex.value :
                    isa(field_ex, Symbol)    ? field_ex        : nothing
        if field_sym !== nothing
            if field_sym in _SIDE_BARS_FIELDS
                return :(d.bars.$field_sym[i - $n])
            else
                return :(d.features.$field_sym[i - $n])
            end
        end
    end

    # Already-qualified d.bars.field or d.features.field  →  add [i]
    if ex.head == :. && length(ex.args) == 2
        lhs = ex.args[1]
        rhs = ex.args[2]
        if isa(lhs, Expr) && lhs.head == :. &&
           isa(lhs.args[1], Symbol) && lhs.args[1] == :d &&
           isa(lhs.args[2], QuoteNode) &&
           lhs.args[2].value in (:bars, :features) &&
           isa(rhs, QuoteNode)
            return :($(lhs).$(rhs.value)[i])
        end
    end

    # Broadcast operators  →  scalar equivalents
    if ex.head == :call && isa(ex.args[1], Symbol) &&
       haskey(_SIDE_BROADCAST_OPS, ex.args[1])
        scalar_op = _SIDE_BROADCAST_OPS[ex.args[1]]
        new_args  = [_replace_symbols(ctx, a) for a in ex.args[2:end]]
        return Expr(:call, scalar_op, new_args...)
    end

    # Default: recurse
    return Expr(ex.head, [_replace_symbols(ctx, a) for a in ex.args]...)
end

# Walk raw AST to find the maximum lag amount used (0 if none).
_find_max_lag(ex) = 0
function _find_max_lag(ex::Expr)
    if ex.head == :call && length(ex.args) >= 3 && ex.args[1] == :lag
        n = ex.args[3]
        return isa(n, Int) ? n : 0
    end
    return maximum(_find_max_lag(a) for a in ex.args; init=0)
end

"""
    @Long(condition)

Create a `Long` direction whose condition is evaluated per-bar.

Symbols are automatically rewritten:
- Bar fields (`:open`, `:high`, `:low`, `:close`, `:volume`, `:timestamp`) or bare
  equivalents → `d.bars.field[i]`
- All other symbols → `d.features.symbol[i]`
- `lag(field, n)` → `d.bars.field[i-n]` or `d.features.field[i-n]`
- Already-qualified `d.bars.x` / `d.features.x` → `d.bars.x[i]` / `d.features.x[i]`
- Broadcasting operators (`.>`, `.<`, etc.) → scalar equivalents

The `min_bar` of the resulting struct is set to `max_lag + 1` so that `Side`
never calls the condition at an index where a lag access would be out-of-bounds.

# Example
```julia
@Long(ema_10 .> ema_20 && :close < lag(close, 1))
# expands to: Long((d, i) -> d.features.ema_10[i] > d.features.ema_20[i] &&
#                            d.bars.close[i] < d.bars.close[i-1], 2)
```
"""
macro Long(ex)
    transformed = _replace_symbols(SideContext(), ex)
    min_bar     = _find_max_lag(ex) + 1
    return esc(:(Long((d, i) -> $transformed, $min_bar)))
end

"""
    @Short(condition)

Like [`@Long`](@ref) but creates a `Short` direction (returns `Int8(-1)` when matched).
"""
macro Short(ex)
    transformed = _replace_symbols(SideContext(), ex)
    min_bar     = _find_max_lag(ex) + 1
    return esc(:(Short((d, i) -> $transformed, $min_bar)))
end
