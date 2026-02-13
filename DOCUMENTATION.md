# Documentation Philosophy & Conventions for Backtest.jl

> **Living document.** This describes the documentation *philosophy* and *conventions*, not a snapshot of what exists today. When you add a new module, type, or function, follow the patterns here. Sections marked with specific examples (EMA, PriceBars, etc.) are illustrative — apply the same patterns to every new component.

## 1. Core Mandate: Documentation as Interface Contract

Docstrings are not afterthoughts. In Julia, documentation *is* the interface. There are no header files, no `Interface` keyword, no enforced method signatures on abstract types. The docstring on an abstract type is the only place where the required method contract lives. The docstring on an exported function is the only guarantee users have about its behaviour.

Every docstring should answer:

- **What does this do?** One sentence, no jargon.
- **What goes in?** Arguments, keyword arguments, their types, and what they *mean* (types alone don't convey semantics).
- **What comes out?** Return type and structure — especially for `NamedTuple` returns that downstream pipeline stages depend on.
- **What can go wrong?** Exceptions, warnings, and the conditions that trigger them.
- **How do I use it?** A runnable example, ideally a doctest.

---

## 2. Format: Julia Markdown Docstrings

We use Julia's built-in Markdown docstrings (`""" ... """`), following the conventions in the [Julia manual](https://docs.julialang.org/en/v1/manual/documentation/) and the [BlueStyle guide](https://github.com/JuliaDiff/BlueStyle).

### Rules

1. **Triple-quoted strings**: Always use `"""..."""`. Opening and closing `"""` go on their own lines.
2. **No blank line** between the docstring and the object it documents. A blank line breaks the association silently.
3. **92-character line width**: Same as code (matches `.JuliaFormatter.toml`).
4. **Backticks for all identifiers**: Every Julia symbol in prose gets backticks — `` `EMA` ``, `` `calculate_indicator` ``, `` `Float64` ``. No exceptions.
5. **4-space indented signature**: The first line after the opening `"""` is the function/type signature, indented by 4 spaces so it renders as a code block.
6. **Imperative mood**: "Return the EMA values", not "Returns the EMA values". Matches Julia Base convention.
7. **Cross-references**: Use `` [`OtherFunction`](@ref) `` when referring to other documented symbols. These become hyperlinks in Documenter.jl output.

### Canonical Section Order

Use `#` (H1) headers for sections inside docstrings. Not every docstring needs every section — include only what's relevant. But when present, they must appear in this order:

```
Signature (4-space indented)
Brief description (one sentence)
Extended description (optional paragraph)
# Arguments
# Keywords
# Returns
# Throws
# Examples
# Extended help
# Implementation
```

| Section | When to include |
|---------|-----------------|
| Signature | Always, for exported symbols |
| Brief description | Always |
| `# Arguments` | When arguments aren't self-evident from the signature |
| `# Keywords` | When keyword arguments exist |
| `# Returns` | When return type/structure isn't obvious — especially for `NamedTuple` returns |
| `# Throws` | When the function validates input and throws |
| `# Examples` | Always, for exported symbols. Use `jldoctest` blocks |
| `# Extended help` | When math background, algorithm details, or implementation theory would overwhelm the quick-help view |
| `# Implementation` | When subtype authors need guidance on which methods to override |

---

## 3. Docstring Templates by Category

### 3a. Exported Functions

Every exported function gets a full docstring. No exceptions.

```julia
"""
    calculate_indicator(ind::EMA{Periods}, prices::AbstractVector{T}) where {Periods, T<:AbstractFloat}

Compute Exponential Moving Average(s) for `prices` using the period(s)
encoded in `ind`.

Return a `Vector{T}` when `ind` has a single period, or a `Matrix{T}`
(columns correspond to periods in declaration order) when `ind` has
multiple periods. The first `period - 1` entries are `NaN` (warmup).

# Arguments
- `ind::EMA{Periods}`: An EMA indicator. Periods are encoded as type
  parameters — use `EMA(10)` for a single period or `EMA(10, 50)` for
  multiple.
- `prices::AbstractVector{T}`: Price series. Must be `AbstractFloat`
  (`Float64`, `Float32`, etc.). Element type is preserved in the output.

# Returns
- `Vector{T}`: When `length(Periods) == 1`. Length equals `length(prices)`.
- `Matrix{T}`: When `length(Periods) > 1`. Size is
  `(length(prices), length(Periods))`.

# Throws
- `ArgumentError`: If any period is not a positive integer (enforced at
  construction time by [`EMA`](@ref)).

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_indicator(EMA(3), prices);

julia> ema[3]
11.0

julia> ema[4]
12.0
```

# Extended help

## Algorithm

The EMA is seeded with the Simple Moving Average (SMA) of the first
`period` values. Subsequent values use the recurrence:

    EMA[i] = α * price[i] + (1 - α) * EMA[i-1]

where `α = 2 / (period + 1)`.

The kernel (`_ema_kernel_unrolled!`) processes 4 elements per iteration
to improve instruction-level parallelism on modern CPUs. A scalar
tail loop handles the remainder.

## Multi-threading

When `EMA` is constructed with `multi_thread=true` and has multiple
periods, each period's computation runs on a separate thread via
`Threads.@threads`. Single-period computation is always single-threaded.
"""
function calculate_indicator(
    ind::EMA{Periods}, prices::AbstractVector{T}
) where {Periods,T<:AbstractFloat}
    # ...
end
```

### 3b. Struct Types

Document the type's purpose, its fields, its constructors, and how it fits into the type hierarchy.

```julia
"""
    EMA{Periods} <: AbstractIndicator

Exponential Moving Average indicator with compile-time period(s).

Periods are stored as a type parameter (a `Tuple` of `Int`s), enabling
`@generated` dispatch to produce specialised, zero-overhead code for
each period combination.

# Fields
- `multi_thread::Bool`: Whether to parallelise multi-period computation
  across threads. Ignored for single-period EMAs.

# Constructors
    EMA(period::Int; multi_thread=false)
    EMA(periods::Vararg{Int}; multi_thread=false)

# Throws
- `ArgumentError`: If no periods are given, if periods are not unique,
  or if any period is not a positive integer.

# Examples
```jldoctest
julia> using Backtest

julia> ema_single = EMA(10);

julia> ema_multi = EMA(10, 20, 50);

julia> ema_threaded = EMA(10, 50; multi_thread=true);
```

# Extended help

## Callable Interface

`EMA` instances are callable. When called with [`PriceBars`](@ref) or a
`NamedTuple` from a previous pipeline stage, they compute the EMA on
`bars.close` and merge the result into the pipeline data:

```julia
bars = get_data("AAPL")
result = EMA(10, 50)(bars)
# result is a NamedTuple with fields :bars, :ema_10, :ema_50
```

The field names follow the pattern `:ema_<period>`.

## Pipeline Composition

Use `>>` to compose into a pipeline:

```julia
job = bars >> EMA(10, 50) >> evt >> lab
result = job()
```
"""
struct EMA{Periods} <: AbstractIndicator
    # ...
end
```

### 3c. Abstract Types (Interface Contracts)

Abstract type docstrings are the **most important** docstrings in the package. They define the interface contract that subtypes must fulfil. Since Julia has no formal interface mechanism, the docstring is the only enforceable specification.

```julia
"""
    AbstractIndicator

Abstract supertype for all technical indicators.

# Interface

Any concrete subtype `T <: AbstractIndicator` **must** implement:

- [`calculate_indicator(ind::T, prices::AbstractVector{<:AbstractFloat})`](@ref):
  Compute the indicator values from a price series. Return type should
  be `AbstractVector` or `AbstractMatrix` of the same float type as
  `prices`.

Any concrete subtype `T <: AbstractIndicator` **must** implement
(internal, for pipeline integration):

- `_indicator_result(ind::T, prices::AbstractVector{<:AbstractFloat})`:
  Return a `NamedTuple` whose keys are the indicator's column names
  (e.g., `(:ema_10,)`) and values are the computed vectors/views.
  This is what the callable interface (`ind(bars)`) uses internally.

# Callable Interface (provided by default)

The following methods are provided for all `AbstractIndicator` subtypes
and should **not** be overridden:

- `(ind::AbstractIndicator)(bars::PriceBars)`: Compute indicator on
  `bars.close`, return `(; bars, indicator_columns...)`.
- `(ind::AbstractIndicator)(d::NamedTuple)`: Compute indicator on
  `d.bars.close`, merge result into `d`.

# Naming Convention

Indicator result keys must be lowercase, using the pattern
`:indicatorname_parameter` (e.g., `:ema_10`, `:cusum`). These names
become the field names that downstream [`Event`](@ref) conditions and
[`@Event`](@ref) macro expressions reference.
"""
abstract type AbstractIndicator end
```

### 3d. Macros

Macro docstrings must explain the surface syntax, show the expansion, and document keyword arguments.

```julia
"""
    @Event expr [key=val ...]

Construct an [`Event`](@ref) from a broadcast expression, with automatic
symbol rewriting.

Symbols prefixed with `:` in the expression are rewritten to field
accesses on the pipeline data. For example, `:ema_10` becomes
`d.ema_10` in the generated closure.

# Arguments
- `expr`: A broadcast expression using `:symbol` syntax to reference
  pipeline fields. Multiple expressions create multiple conditions.

# Keywords
- `match::Symbol=:all`: How to combine multiple conditions. `:all`
  requires all conditions to be true (AND). `:any` requires at least
  one (OR).

# Examples
```julia
# Single condition — equivalent to Event(d -> d.ema_10 .> d.ema_50)
evt = @Event :ema_10 .> :ema_50

# Multiple conditions with OR logic
evt = @Event :ema_10 .> :ema_50 :close .> 100.0 match=:any
```

!!! warning "Broadcasting"
    Use dot-broadcasting operators (`.>`, `.&&`, `.*`, etc.) in the
    expression. A non-broadcasting operator will produce a scalar `Bool`
    instead of a vector, and the `Event` will emit a warning at runtime.
"""
macro Event(args...)
    # ...
end
```

### 3e. Constants and Simple Types

Short docstrings are fine when there's nothing complex to explain. One line above the definition.

```julia
"Market direction: only long (buy) positions are allowed."
struct LongOnly <: AbstractDirection end

"Market direction: only short (sell) positions are allowed."
struct ShortOnly <: AbstractDirection end

"Market direction: both long and short positions are allowed."
struct LongShort <: AbstractDirection end
```

For the core data container:

```julia
"""
    PriceBars{B<:AbstractBarType, T<:AbstractFloat, V<:AbstractVector{T}}

Immutable container for OHLCV price data with timestamps.

This is the entry point for all pipelines. Construct directly or via
[`get_data`](@ref).

# Fields
- `open::V`: Opening prices.
- `high::V`: High prices.
- `low::V`: Low prices.
- `close::V`: Closing prices.
- `volume::V`: Trading volumes.
- `timestamp::Vector{DateTime}`: Bar timestamps.
- `bartype::B`: Bar type indicator ([`TimeBar`](@ref), `DollarBar`, etc.).

# Examples
```jldoctest
julia> using Backtest, Dates

julia> bars = PriceBars(
           [100.0], [105.0], [95.0], [102.0], [1000.0],
           [DateTime(2024, 1, 1)], TimeBar()
       );

julia> length(bars)
1
```
"""
struct PriceBars{B<:AbstractBarType,T<:AbstractFloat,V<:AbstractVector{T}}
    # ...
end
```

### 3f. Internal Functions

Internal functions (not exported, prefixed with `_`) do not require full docstrings but **must** have a docstring when they meet any of these criteria:

| Criterion | Rationale |
|-----------|-----------|
| Contains non-trivial math or algorithms | Future maintainers need to understand the formula |
| Defines the NamedTuple keys consumed by downstream stages | These are implicit interface contracts |
| Has subtle correctness requirements (index arithmetic, warmup logic) | Off-by-one bugs are the #1 source of backtesting errors |
| Is a `@generated` function | The metaprogramming is not self-evident |
| Is referenced in `TESTING.md` as a test target | If it's worth testing directly, it's worth documenting |

Internal docstrings can be shorter — skip `# Examples` unless the function has tricky usage. Always include the signature and a brief description.

```julia
"""
    _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat} -> T

Compute the Simple Moving Average of the first `p` elements of `prices`.
Used to seed the EMA recurrence. Assumes `p <= length(prices)`.
"""
@inline function _sma_seed(prices::AbstractVector{T}, p::Int) where {T<:AbstractFloat}
    # ...
end
```

```julia
"""
    _ema_kernel_unrolled!(ema, prices, p, n, α, β) -> Nothing

In-place EMA computation using 4-wide loop unrolling for
instruction-level parallelism. Processes elements `p+1` through `n`.

Assumes `ema[p]` is already set to the SMA seed. Mutates `ema`
in-place. Zero allocations.
"""
@inline function _ema_kernel_unrolled!(
    ema::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int, α::T, β::T
) where {T<:AbstractFloat}
    # ...
end
```

```julia
"""
    _indicator_result(ind::EMA{Periods}, prices) -> NamedTuple

`@generated` function that returns a `NamedTuple` with keys derived
from the period values (e.g., `(:ema_10, :ema_50)`). Single-period
EMAs return vectors as values; multi-period EMAs return column views
into the result matrix.

This is the bridge between [`calculate_indicator`](@ref) (which
returns raw arrays) and the callable/pipeline interface (which
needs named fields for downstream access).
"""
@generated function _indicator_result(ind::EMA{Periods}, prices) where {Periods}
    # ...
end
```

---

## 4. Doctests

Doctests are fenced code blocks tagged with `jldoctest` that [Documenter.jl](https://documenter.juliadocs.org/stable/man/doctests/) can execute and verify. They serve two purposes: demonstrating usage and preventing documentation rot.

### 4a. Format

Use REPL-style doctests (lines prefixed with `julia>`):

````julia
"""
    EMA(period::Int; multi_thread=false)

Construct a single-period EMA indicator.

# Examples
```jldoctest
julia> using Backtest

julia> ema = EMA(10);

julia> typeof(ema)
EMA{(10,)}
```
"""
````

### 4b. Rules

1. **Every exported function and type** must have at least one `jldoctest` block.
2. **Always include `using Backtest`** at the top of the doctest. Each doctest runs in an isolated module — there's no implicit import.
3. **Semicolons to suppress output** when output isn't the point of the example. Use them on setup lines to keep focus on the demonstrated behaviour.
4. **Deterministic output only**. No `rand()`, no timestamps from `now()`, no memory addresses.
5. **Named doctests** for multi-block examples that share state. Give them a name matching the component: `` ```jldoctest ema_pipeline ``.
6. **Filter non-deterministic output** with the `filter` keyword when unavoidable:

````julia
"""
```jldoctest; filter = r"[0-9\\.]+ seconds"
julia> @time calculate_indicator(EMA(10), randn(1000))
  0.000042 seconds (1 allocation: 7.875 KiB)
```
"""
````

### 4c. What Not to Doctest

| Scenario | Why | Alternative |
|----------|-----|-------------|
| Functions that hit the network (`get_data`) | Non-deterministic, slow, requires API access | Use a plain `julia` block (not `jldoctest`) with a comment: `# requires network` |
| Output with platform-dependent formatting | `Int` is `Int64` on 64-bit, `Int32` on 32-bit | Use explicit types in the example or use a filter |
| Very large output (matrices, DataFrames) | Brittle to formatting changes, hard to read | Show only a slice or assert a property instead |
| Pipeline results with many fields | NamedTuple printing is verbose and order-sensitive | Show individual field access instead: `result.ema_10[1:3]` |

### 4d. Running Doctests

Doctests can be executed in two ways:

**Via Documenter (when docs infrastructure is set up):**

```julia
# In docs/make.jl
makedocs(
    # ...
    doctest = true,  # run doctests during doc build
)
```

**Standalone in tests:**

```julia
# In test/runtests.jl or a dedicated test file
using Documenter, Backtest
doctest(Backtest)
```

This behaves like a `@testset` and integrates with the existing test infrastructure.

**Auto-fixing stale doctests:**

```julia
using Documenter, Backtest
doctest(Backtest; fix=true)
```

This rewrites docstring output in source files to match actual output. Always review the diff before committing. Only works on packages in development mode (`Pkg.develop`).

---

## 5. The `# Extended help` Convention

Julia's REPL supports two help levels: `?foo` (brief) and `??foo` (full). Everything above `# Extended help` appears for `?foo`. Everything including and below appears for `??foo`.

Use this to keep the quick-help view concise while providing depth for users who want it.

### When to Use Extended Help

| Content | Goes in... |
|---------|-----------|
| One-sentence summary | Brief section (above `# Extended help`) |
| Argument/keyword docs | Brief section |
| A short example | Brief section |
| Mathematical derivation | `# Extended help` |
| Algorithm complexity analysis | `# Extended help` |
| Performance tuning guidance (threading, SIMD) | `# Extended help` |
| Comparison with alternative approaches | `# Extended help` |
| Historical context or references to papers | `# Extended help` |

### Example

```julia
"""
    CUSUM(threshold; span=100)

Cumulative Sum (CUSUM) filter for detecting structural breaks in a
price series. Return a `NamedTuple` with positive and negative CUSUM
series.

# Examples
```jldoctest
julia> using Backtest

julia> cusum = CUSUM(1.0);

julia> typeof(cusum)
CUSUM
```

# Extended help

## Theory

The CUSUM filter (Page, 1954) monitors the cumulative sum of
log-returns against a threshold `h`. When the cumulative sum exceeds
`h`, a structural break is signalled and the accumulator resets.

The filter maintains two accumulators:
- `S⁺`: detects upward shifts (positive cumulative sum)
- `S⁻`: detects downward shifts (negative cumulative sum)

The expected return `E[r]` is estimated from a rolling window of
`span` observations.

## References

- Page, E. S. (1954). "Continuous Inspection Schemes."
  *Biometrika*, 41(1/2), 100–115.
- De Prado, M. L. (2018). *Advances in Financial Machine Learning*.
  Chapter 2: CUSUM Filter.
"""
```

---

## 6. Module-Level Documentation

The top-level `Backtest` module and each submodule (`Indicator`, etc.) should have a module docstring placed directly above the `module` keyword.

```julia
"""
    Backtest

High-performance backtesting framework for quantitative trading strategies.

Provides a composable pipeline architecture where data flows through
indicators, event detectors, and labelling stages using the `>>`
operator.

# Quick Start

```julia
using Backtest, Dates

bars = get_data("AAPL"; start_date="2020-01-01")
job = bars >> EMA(10, 50) >> @Event(:ema_10 .> :ema_50) >> Label!(...)
result = job()
```

# Exports

## Data
- [`PriceBars`](@ref), [`TimeBar`](@ref)
- [`get_data`](@ref)

## Indicators
- [`AbstractIndicator`](@ref), [`EMA`](@ref), [`CUSUM`](@ref)
- [`calculate_indicator`](@ref)

## Events
- [`AbstractEvent`](@ref), [`Event`](@ref), [`@Event`](@ref)

## Labels
- [`AbstractLabel`](@ref), [`Label`](@ref), [`Label!`](@ref)
- [`calculate_label`](@ref)
- [`AbstractBarrier`](@ref), [`UpperBarrier`](@ref),
  [`LowerBarrier`](@ref), [`TimeBarrier`](@ref),
  [`ConditionBarrier`](@ref)
- [`@UpperBarrier`](@ref), [`@LowerBarrier`](@ref),
  [`@TimeBarrier`](@ref), [`@ConditionBarrier`](@ref)

## Sides
- [`AbstractSide`](@ref), [`Crossover`](@ref), [`calculate_side`](@ref)

## Directions
- [`LongOnly`](@ref), [`ShortOnly`](@ref), [`LongShort`](@ref)
"""
module Backtest
    # ...
end
```

---

## 7. Documenter.jl Setup

When the package is ready for hosted documentation, use [Documenter.jl](https://documenter.juliadocs.org/stable/) to build HTML from docstrings and Markdown pages.

### Target Directory Structure

```
docs/
├── Project.toml          # docs-specific dependencies
├── make.jl               # Build script
└── src/
    ├── index.md          # Landing page (overview, installation, quick start)
    ├── guide.md          # Tutorial-style walkthrough
    ├── pipeline.md       # Pipeline architecture (>>) explained
    ├── indicators.md     # Indicator module docs
    ├── events.md         # Event detection docs
    ├── labels.md         # Labelling docs
    └── api.md            # Full API reference (@autodocs)
```

### `docs/make.jl`

```julia
using Documenter
using Backtest

makedocs(
    sitename = "Backtest.jl",
    modules = [Backtest],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Guide" => "guide.md",
        "Pipeline Architecture" => "pipeline.md",
        "Indicators" => "indicators.md",
        "Events" => "events.md",
        "Labels" => "labels.md",
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,   # Warn if any exported symbol lacks a docstring
    doctest = true,         # Run all jldoctest blocks
    strict = true,          # Treat warnings as errors in CI
)

deploydocs(
    repo = "github.com/Wilsy99/Backtest.jl.git",
    devbranch = "main",
)
```

### `docs/Project.toml`

```toml
[deps]
Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
Backtest = "..."  # UUID from Project.toml
```

### Key `makedocs` Options

| Option | Value | Why |
|--------|-------|-----|
| `modules = [Backtest]` | Required | Enables docstring coverage checking — warns about any exported symbol whose docstring isn't included in a `@docs` or `@autodocs` block |
| `checkdocs = :exports` | Required | Only checks exported symbols. Use `:all` to also check internal docstrings |
| `doctest = true` | Required | Runs all `jldoctest` blocks during the doc build. Use `:only` to run doctests without building HTML |
| `strict = true` | Required for CI | Fails the build on any warning (missing docstrings, broken cross-refs, failed doctests) |

### API Reference Page (`docs/src/api.md`)

````markdown
# API Reference

```@meta
CurrentModule = Backtest
DocTestSetup = quote
    using Backtest
    using Dates
end
```

## Data Types

```@docs
PriceBars
TimeBar
```

## Indicators

```@docs
AbstractIndicator
EMA
CUSUM
calculate_indicator
```

## Events

```@docs
AbstractEvent
Event
@Event
```

## Labels

```@docs
AbstractLabel
Label
Label!
calculate_label
AbstractBarrier
UpperBarrier
LowerBarrier
TimeBarrier
ConditionBarrier
@UpperBarrier
@LowerBarrier
@TimeBarrier
@ConditionBarrier
```

## Sides

```@docs
AbstractSide
Crossover
calculate_side
```

## Directions

```@docs
LongOnly
ShortOnly
LongShort
```

## Data Loading

```@docs
get_data
```
````

Use `@autodocs` only when you want to include *everything* from a module without listing individual symbols. Prefer explicit `@docs` blocks — they make the page structure intentional and catch renamed/removed symbols at build time.

---

## 8. Cross-References

Use `` [`SymbolName`](@ref) `` to create hyperlinks between docstrings and documentation pages. Documenter resolves these at build time and warns (errors in strict mode) if the target doesn't exist.

### Rules

1. **Always cross-reference** when mentioning another exported symbol in a docstring. Write `` [`Event`](@ref) ``, not `` `Event` ``.
2. **Qualify ambiguous references**: If `calculate_indicator` is documented for multiple types, use `` [`calculate_indicator(::EMA, ::AbstractVector)`](@ref) ``.
3. **Link from `# Throws` sections**: `` [`ArgumentError`](@ref Base.ArgumentError) `` links to Base Julia docs.
4. **Link abstract types from concrete types**: Every concrete type's docstring should link to its parent abstract type.

### Example

```julia
"""
    Crossover <: AbstractSide

Determine trade side based on indicator crossover signals.

See [`AbstractSide`](@ref) for the interface contract.
Uses [`calculate_side`](@ref) as the public computation entry point.
"""
struct Crossover <: AbstractSide
    # ...
end
```

---

## 9. Anti-Patterns

These are documentation mistakes to avoid. They are drawn from real Julia ecosystem patterns and adapted to this codebase.

### Anti-Pattern 1: No Docstring on an Exported Symbol

```julia
# BAD — exported with no documentation
export calculate_indicator
calculate_indicator(ind::EMA, prices) = ...
```

**Rule**: Every symbol in the `export` list gets a docstring. The `checkdocs = :exports` option in `makedocs` enforces this at build time.

### Anti-Pattern 2: Relying on Type Signatures as Documentation

```julia
# BAD — types tell you what, not why
function _single_ema!(
    dest::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int
) where {T<:AbstractFloat}
```

Types answer "what kind of value?" but not "what does this value represent?" or "what are the preconditions?". `p::Int` could be a period, a price index, or a count. Document it.

### Anti-Pattern 3: Blank Line Between Docstring and Definition

```julia
# BAD — the blank line silently detaches the docstring
"""
    EMA(period::Int)

Construct an EMA indicator.
"""

struct EMA{Periods} <: AbstractIndicator  # ← docstring not attached!
```

This is the most insidious bug because it produces no error or warning. The docstring becomes a free-floating string expression that Julia silently discards.

### Anti-Pattern 4: Documenting Every Method Separately

```julia
# BAD — repetitive, hard to maintain
"""Construct a single-period EMA."""
EMA(p::Int; multi_thread::Bool=false) = ...

"""Construct a multi-period EMA."""
EMA(ps::Vararg{Int}; multi_thread::Bool=false) = ...
```

Document the *function* (or *type*), not individual methods. List all constructor forms in the type's docstring under `# Constructors`. Only give a separate docstring to a method when its behaviour substantially differs from the primary documentation.

### Anti-Pattern 5: Non-Runnable Examples

````julia
# BAD — can't be verified, will rot
"""
# Examples
```julia
ema = EMA(10)
result = calculate_indicator(ema, prices)  # what is prices?
```
"""
````

Use `jldoctest` blocks with complete, self-contained examples. If the example can't run as a doctest (network dependency, large data), mark it with a plain `julia` block and add a comment explaining why.

### Anti-Pattern 6: Wall of Text in Quick Help

```julia
# BAD — user types ?calculate_indicator and gets 80 lines
"""
    calculate_indicator(ind, prices)

[... 20 lines of description ...]
[... 15 lines of mathematical derivation ...]
[... 30 lines of implementation notes ...]
[... 15 lines of examples ...]
"""
```

Use `# Extended help` to separate the quick reference from the deep dive. The first screen of `?foo` should answer "what does this do and how do I call it?" in under 30 lines.

### Anti-Pattern 7: Undocumented NamedTuple Return Structure

```julia
# BAD — downstream pipeline stages depend on these keys
function (ind::EMA{Periods})(bars::PriceBars)
    return merge((bars=bars,), _indicator_result(ind, bars.close))
end
# What keys? What types? What order? ¯\_(ツ)_/¯
```

In a pipeline architecture, the return structure of one stage is the input interface of the next. Document every `NamedTuple` return — its keys, their types, and what they represent. This is especially critical for `_indicator_result` and the `Event` callable.

### Anti-Pattern 8: Forgetting `@ref` Cross-References

```julia
# BAD — mentions PriceBars but doesn't link to it
"""
    get_data(tickers; start_date, end_date, timeframe) -> DataFrame

Fetch historical OHLCV data. See PriceBars for the data container.
"""
```

```julia
# GOOD
"""
See [`PriceBars`](@ref) for the data container.
"""
```

Unlinked references become dead text in the rendered docs. Linked references become navigable and are validated at build time.

---

## 10. Pipeline-Specific Documentation Requirements

The `>>` pipeline is the core user experience. Its documentation has special requirements because the implicit interface between stages is defined by `NamedTuple` key conventions, not by types.

### Document the Data Flow

Every callable stage (indicators, events, labels) must document:

1. **What it expects in the input `NamedTuple`** (required keys).
2. **What it adds to the output `NamedTuple`** (new keys and their types).
3. **What it passes through unchanged** (merged keys from upstream).

Example for `Event`:

```julia
"""
# Pipeline Data Flow

## Input
Expects a `NamedTuple` with at least:
- `bars::PriceBars`: The price data.
- Additional keys as referenced by condition expressions
  (e.g., `:ema_10`, `:ema_50`).

## Output
Returns the input `NamedTuple` merged with:
- `event_indices::Vector{Int}`: Indices where all (or any) conditions
  are satisfied.
"""
```

### Document the `>>` Operator

The `>>` operator itself and the `Job` type need docstrings explaining composition semantics:

```julia
"""
    data >> stage -> Job
    job >> stage -> Job
    stage >> stage -> ComposedFunction

Compose pipeline stages using the `>>` operator.

When the left operand is data (e.g., [`PriceBars`](@ref)), creates a
[`Job`](@ref) that can be executed with `job()`. When the left operand
is already a `Job`, appends the stage. When both operands are stages,
creates a composed function.

# Examples
```julia
job = bars >> EMA(10, 50) >> @Event(:ema_10 .> :ema_50) >> Label!(...)
result = job()
```
"""
```

---

## 11. Decision Matrix: What Needs a Docstring?

| Symbol kind | Exported? | Needs docstring? | Minimum content |
|-------------|-----------|-----------------|-----------------|
| Function | Yes | **Always** | Signature, brief, arguments, returns, example |
| Macro | Yes | **Always** | Signature, brief, syntax explanation, example |
| Struct | Yes | **Always** | Signature, brief, fields, constructors, example |
| Abstract type | Yes | **Always** | Signature, brief, **full interface contract**, example implementation |
| Constant | Yes | **Always** | One-line description |
| Direction type (`LongOnly`, etc.) | Yes | **Always** | One-line description |
| Internal function (`_foo`) | No | **If non-trivial** | Signature, brief, preconditions |
| Internal helper (`_natural`, etc.) | No | **Only if complex** | Signature, brief |
| `@generated` function | No | **Always** | Signature, brief, what the generated code does |
| Module | — | **Always** | Brief, exports overview, quick start |

---

## 12. Priority Order

This is a phased approach. Complete each phase before moving to the next.

### Phase 1: Interface Contracts (do once, unblocks contributors)

| What | Why |
|------|-----|
| Abstract type docstrings (`AbstractIndicator`, `AbstractSide`, `AbstractEvent`, `AbstractBarrier`, `AbstractLabel`) | These define the rules. Without them, nobody knows how to add a new indicator or barrier type |
| Module docstring for `Backtest` | Entry point for `?Backtest` in the REPL |
| `PriceBars` docstring | Core data type that everything depends on |

### Phase 2: Public API (do for every exported symbol)

| What | Why |
|------|-----|
| Exported function docstrings (`calculate_indicator`, `calculate_side`, `calculate_label`, `get_data`) | Users call these directly |
| Exported type docstrings (`EMA`, `CUSUM`, `Crossover`, `Event`, `Label`, `Label!`, barrier types) | Users construct these directly |
| Exported macro docstrings (`@Event`, `@UpperBarrier`, `@LowerBarrier`, `@TimeBarrier`, `@ConditionBarrier`) | DSL surface — most error-prone to use without docs |
| Direction/execution basis types (`LongOnly`, `ShortOnly`, `LongShort`, `CurrentOpen`, etc.) | Small types, one-line docstrings, but must exist |

### Phase 3: Doctests (do for every exported symbol)

| What | Why |
|------|-----|
| Add `jldoctest` blocks to all Phase 2 docstrings | Prevents documentation rot, serves as executable examples |
| Add `doctest(Backtest)` to test suite | CI enforcement |

### Phase 4: Internal Documentation (do for non-trivial internals)

| What | Why |
|------|-----|
| `@generated` functions (`_indicator_result`) | Metaprogramming is not self-documenting |
| Computation kernels (`_ema_kernel_unrolled!`, `_calculate_cusum`, `_sma_seed`) | Math-heavy code with subtle preconditions |
| Pipeline data flow (what each `NamedTuple` contains at each stage) | The implicit interface that makes or breaks correctness |
| Macro internals (`_replace_symbols`, `_build_macro_components`) | AST manipulation context |

### Phase 5: Documenter.jl Infrastructure (do once)

| What | Why |
|------|-----|
| Create `docs/` directory with `make.jl`, `Project.toml` | Enables hosted documentation |
| Write `index.md` (installation, quick start) | First thing new users see |
| Write `guide.md` (tutorial walkthrough) | Onboarding experience |
| Write `api.md` (full `@docs` listing) | Comprehensive reference |
| CI workflow for doc deployment | Automated, always up-to-date |

### Phase 6: Narrative Documentation (ongoing)

| What | Why |
|------|-----|
| Pipeline architecture guide (`pipeline.md`) | Explains the `>>` mental model |
| Per-module guides (indicators, events, labels) | Deep dives with worked examples |
| Performance guide | Threading, SIMD, allocation guidance |
| Contributing guide (how to add a new indicator/barrier) | Unblocks external contributors |

### When Adding a New Component

Follow the same phase order: write the abstract type's interface contract first, then the concrete type's full docstring with constructors and examples, then add `jldoctest` blocks, then document non-trivial internals, then add the symbol to `api.md`. This applies to every new indicator, side, event, label, barrier, or future module.
