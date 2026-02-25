"""
    Event{T<:Tuple} <: AbstractEvent

Detect events in price data by evaluating one or more condition functions
against a pipeline `NamedTuple`.

An event is a bar index where all (`:all`) or any (`:any`) of the supplied
conditions evaluate to `true`. Conditions must return a `BitVector` or
`Vector{Bool}` of the same length as the price series — use dot-broadcasting
operators (`.>`, `.&&`, etc.) to ensure this.

# Type Parameters
- `T<:Tuple`: the compile-time tuple type of the condition functions.

# Fields
- `conditions::T`: tuple of condition functions, each accepting the pipeline
    data and returning a boolean vector.
- `logic::Function`: bitwise operator used to combine conditions. Set to `(&)`
    for `:all` (AND) logic or `(|)` for `:any` (OR) logic.

# Constructors
    Event(cond_funcs::Function...; match::Symbol = :all)

# Keywords
- `match::Symbol = :all`: combination logic. `:all` requires every condition
    to hold at a bar (AND); `:any` requires at least one (OR).

# Throws
- No construction errors. Invalid condition functions (returning a scalar
    `Bool`) trigger a runtime `@warn` when the event is evaluated.

# Examples
```jldoctest
julia> using Backtest, Dates

julia> bars = PriceBars(
           [99.0, 100.0, 101.0],
           [100.0, 101.0, 102.0],
           [98.0,  99.0, 100.0],
           [100.0, 101.0, 100.5],
           [1000.0, 1100.0, 900.0],
           [DateTime(2024,1,1), DateTime(2024,1,2), DateTime(2024,1,3)],
           TimeBar(),
       );

julia> evt = Event(d -> d.bars.close .> 100.0);

julia> result = evt(bars);

julia> result.event_indices
2-element Vector{Int64}:
 2
 3
```

# See also
- [`calculate_event`](@ref): standalone computation function.
- [`@Event`](@ref): DSL macro for constructing `Event` with symbol rewriting.
- [`AbstractEvent`](@ref): supertype and interface contract.

# Extended help

## Pipeline Data Flow

### Input (NamedTuple form)
Expects a `NamedTuple` with at least:
- `bars::PriceBars`: the price data.
- Any additional keys referenced by condition expressions (e.g., `:ema_10`,
    `:ema_50`).

### Output
Returns the input `NamedTuple` merged with:
- `event_indices::Vector{Int}`: bar indices where all (or any) conditions
    hold.

### Direct PriceBars form
When called with a `PriceBars` directly, returns a `NamedTuple` with:
- `bars::PriceBars`: the original input.
- `event_indices::Vector{Int}`: bar indices satisfying the conditions.

## Callable Interface

`Event` instances are callable. Use them in a pipeline:

```julia
using Backtest, Dates

bars = get_data("AAPL"; start_date="2020-01-01", end_date="2023-12-31")
result = bars >> EMA(10, 50) >> Event(d -> d.ema_10 .> d.ema_50)
```
"""
struct Event{T<:Tuple} <: AbstractEvent
    conditions::T
    logic::Function # Stores bitwise operator (& / |)
end

"""
    Event(cond_funcs::Function...; match::Symbol = :all) -> Event

Construct an [`Event`](@ref) from one or more condition functions.

Each function in `cond_funcs` must accept the pipeline data (a `PriceBars` or
`NamedTuple`) and return a `BitVector` or `Vector{Bool}`. Non-broadcasting
conditions that return a scalar `Bool` will trigger a warning at evaluation
time.

# Arguments
- `cond_funcs::Function...`: one or more condition functions.

# Keywords
- `match::Symbol = :all`: `:all` for AND logic (every condition must hold),
    `:any` for OR logic (at least one must hold).

# Returns
- `Event`: a callable event detector.

# Examples
```jldoctest
julia> using Backtest

julia> evt = Event(d -> d.close .> 100.0);

julia> evt isa AbstractEvent
true

julia> evt_any = Event(
           d -> d.close .> 100.0,
           d -> d.close .< 110.0;
           match = :any,
       );

julia> evt_any isa AbstractEvent
true
```

# See also
- [`calculate_event`](@ref): standalone computation function.
- [`@Event`](@ref): DSL macro that constructs `Event` with symbol rewriting.
"""
function Event(cond_funcs::Function...; match::Symbol=:all)
    op = match === :any ? (|) : (&)
    return Event(cond_funcs, op)
end

# ── Standalone Calculation ──

"""
    calculate_event(event::Event, data) -> Vector{Int}

Evaluate the event detector against `data` and return the bar indices
where the combined condition mask is `true`.

This is the standalone computation function for the Event stage. The
functor interface (`event(bars)`, `event(d)`) delegates to this
function after wrapping the input.

`data` must be whatever the condition closures expect — typically a
`NamedTuple` with at least `bars::PriceBars`, plus any feature keys
referenced by the conditions (e.g., `:ema_10`).

# Arguments
- `event::Event`: the event detector.
- `data`: the data passed to each condition function. Must support
    `data.bars.close` to determine the series length.

# Returns
- `Vector{Int}`: sorted bar indices where all (`:all`) or any (`:any`)
    conditions hold.

# Examples
```julia
using Backtest, Dates

bars = PriceBars(
    [99.0, 100.0, 101.0],
    [100.0, 101.0, 102.0],
    [98.0,  99.0, 100.0],
    [100.0, 101.0, 100.5],
    [1000.0, 1100.0, 900.0],
    [DateTime(2024,1,1), DateTime(2024,1,2), DateTime(2024,1,3)],
    TimeBar(),
)

evt = Event(d -> d.bars.close .> 100.0)
indices = calculate_event(evt, (bars=bars,))  # [2, 3]
```

# See also
- [`Event`](@ref): constructor and type documentation.
- [`calculate_event(::Event, ::PriceBars)`](@ref): convenience overload.
"""
function calculate_event(event::Event, data)
    n = length(data.bars.close)
    return _resolve_indices(event, data, n)
end

"""
    calculate_event(event::Event, bars::PriceBars) -> Vector{Int}

Convenience overload that wraps `bars` as `(bars=bars,)` before
evaluating.

Only works when conditions reference bar fields (`:close`, `:open`,
etc.) and do not depend on upstream feature keys.

# Arguments
- `event::Event`: the event detector.
- `bars::PriceBars`: the price data.

# Returns
- `Vector{Int}`: sorted bar indices where conditions hold.

# Examples
```julia
using Backtest, Dates

bars = PriceBars(
    [99.0, 100.0, 101.0],
    [100.0, 101.0, 102.0],
    [98.0,  99.0, 100.0],
    [100.0, 101.0, 100.5],
    [1000.0, 1100.0, 900.0],
    [DateTime(2024,1,1), DateTime(2024,1,2), DateTime(2024,1,3)],
    TimeBar(),
)

evt = Event(d -> d.bars.close .> 100.0)
indices = calculate_event(evt, bars)  # [2, 3]
```

# See also
- [`Event`](@ref): constructor and type documentation.
- [`calculate_event(::Event, data)`](@ref): general overload for pipeline data.
"""
function calculate_event(event::Event, bars::PriceBars)
    return calculate_event(event, (bars=bars,))
end

"""
    (e::Event)(bars::PriceBars) -> NamedTuple
    (e::Event)(d::NamedTuple)   -> NamedTuple

Evaluate the event detector against price data or a pipeline `NamedTuple`.

Apply each condition in `e.conditions` to `data`, combine the boolean vectors
using `e.logic` (`&` for AND, `|` for OR), and return the indices where the
combined mask is `true`.

Conditions that return a scalar `Bool` instead of a vector trigger a warning
and will broadcast incorrectly — this usually indicates a missing dot (`.`)
on a comparison operator.

# Arguments
- `bars::PriceBars`: price data for direct (non-pipeline) use.
- `d::NamedTuple`: pipeline data from an upstream stage.

# Returns
- `NamedTuple`: the input merged with `event_indices::Vector{Int}`.
    When called on `PriceBars`, the tuple also includes `bars::PriceBars`.

# Examples
```jldoctest
julia> using Backtest, Dates

julia> bars = PriceBars(
           [99.0, 100.0, 101.0],
           [100.0, 101.0, 102.0],
           [98.0,  99.0, 100.0],
           [100.0, 101.0, 102.0],
           [1000.0, 1100.0, 900.0],
           [DateTime(2024,1,1), DateTime(2024,1,2), DateTime(2024,1,3)],
           TimeBar(),
       );

julia> evt = Event(d -> d.bars.close .> 100.0);

julia> r = evt(bars);

julia> r.event_indices
2-element Vector{Int64}:
 2
 3
```

# See also
- [`Event`](@ref): constructor and type documentation.
- [`calculate_event`](@ref): standalone computation function.
- [`_resolve_indices`](@ref): the underlying index-resolution kernel.

# Pipeline Data Flow

## Input (NamedTuple form)
Requires at least `bars::PriceBars` in the `NamedTuple`, plus any keys
referenced by the condition expressions.

## Output
Returns the input merged with `event_indices::Vector{Int}`.
"""
function (e::Event)(bars::PriceBars)
    d = (bars=bars,)
    indices = calculate_event(e, d)
    return (; bars=bars, event_indices=indices)
end

function (e::Event)(d::NamedTuple)
    indices = calculate_event(e, d)
    return merge(d, (; event_indices=indices))
end

"""
    _resolve_indices(e::Event, data, n::Int) -> Vector{Int}

Apply all conditions in `e` to `data` and return the bar indices where the
combined boolean mask is `true`.

Start the mask as `trues(n)` for AND logic or `falses(n)` for OR logic, then
accumulate each condition result with `e.logic`. Emit a warning when a
condition returns a scalar `Bool` instead of a vector.

# Arguments
- `e::Event`: the event detector whose conditions and logic operator are used.
- `data`: the pipeline data passed to each condition function (a `PriceBars`
    or `NamedTuple`).
- `n::Int`: length of the price series; determines the initial mask size.

# Returns
- `Vector{Int}`: sorted indices where the combined condition mask is `true`.
"""
function _resolve_indices(e::Event, data, n::Int)
    is_and_mode = e.logic === (&)
    mask = is_and_mode ? trues(n) : falses(n)

    for condition in e.conditions
        res = condition(data)

        if res isa Bool
            @warn "Event condition returned a single Bool instead of a vector. " *
                "This usually means you forgot a dot (.) for broadcasting (e.g., use .!= instead of !=)."
        end

        mask .= e.logic.(mask, res)
    end

    return findall(mask)
end

struct EventContext end

"""
    @Event expr [key=val ...]

Construct an [`Event`](@ref) using a DSL expression with automatic symbol
rewriting.

Symbols prefixed with `:` in `expr` are rewritten to access fields of the
pipeline `NamedTuple` `d`. For example, `:ema_10` becomes `d.ema_10`.
Each positional expression becomes one condition function; keyword arguments
are forwarded to the [`Event`](@ref) constructor.

# Arguments
- `expr`: a Julia expression using `:symbol` notation for pipeline fields.
    Multiple positional expressions create multiple independent conditions.

# Keywords
- `match::Symbol = :all`: forwarded to [`Event`](@ref). `:all` requires all
    conditions to hold (AND); `:any` requires at least one (OR).

# Examples

Simple crossover condition:
```julia
evt = @Event :ema_10 .> :ema_50
```

Weighted average threshold:
```julia
evt = @Event (:ema_10 .* 0.5 .+ :ema_50 .* 0.5) .> 100.0
```

Multiple conditions with OR logic:
```julia
evt = @Event :ema_10 .> :ema_50 :close .> 100.0 match=:any
```

!!! warning "Use dot-broadcasting operators"
    Use broadcasted operators (`.>`, `.<`, `.*`, etc.) in the expression.
    A non-broadcasting operator returns a scalar `Bool`, which triggers a
    runtime warning and produces incorrect index results.

# See also
- [`Event`](@ref): the underlying type constructed by this macro.
- [`calculate_event`](@ref): standalone computation function.
- [`@UpperBarrier`](@ref), [`@LowerBarrier`](@ref): barrier macros using the
    same symbol-rewriting rules.
"""
macro Event(args...)
    funcs, kwargs = _build_macro_components(EventContext(), args)
    return esc(:(Event($(funcs...); $(kwargs...))))
end

"""
    _replace_symbols(::EventContext, ex::QuoteNode) -> Expr

Rewrite a quoted symbol to a field access on the pipeline variable `d`.

Price-bar field names (`:open`, `:high`, `:low`, `:close`, `:volume`,
`:timestamp`) are routed through `d.bars.symbol` so that the same expression
works regardless of whether `d` is a wrapped `PriceBars` (from the direct
callable) or a pipeline `NamedTuple`. All other symbols (feature keys such
as `:ema_10`) are rewritten to the flat form `d.symbol`.

# See also
- `_replace_symbols(ctx, ex::Expr)`: recursive case for compound expressions.
- `_replace_symbols(ctx, ex)`: fallback for literals and other non-symbol nodes.
"""
function _replace_symbols(::EventContext, ex::QuoteNode)
    bars_fields = (:open, :high, :low, :close, :volume, :timestamp)
    if ex.value in bars_fields
        return :(d.bars.$(ex.value))
    else
        return Expr(:., :d, ex)
    end
end
