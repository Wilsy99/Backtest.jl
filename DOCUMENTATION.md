# Documentation Philosophy & Conventions for Backtest.jl

> **Living document.** This describes the documentation *philosophy* and *conventions*, not a snapshot of what exists today. When you add a new module, type, or public function, follow the patterns here. Sections marked with specific examples (EMA, CUSUM, etc.) are illustrative — apply the same patterns to every new component.

## 1. Core Mandate: Documentation as Contract

Docstrings are not afterthoughts or decorations. They are the **interface contract** between this package and its users. In Julia there are no header files, no `Interface` keyword, no enforced method signatures on abstract types. The docstring on an abstract type is the only place where the required method contract lives. The docstring on an exported function is the only guarantee users have about its behaviour.

Every exported docstring must answer three questions:

1. **What does it do?** (one-line summary)
2. **How do I call it?** (signature, arguments, keyword arguments)
3. **What comes back?** (return type and shape — especially `NamedTuple` returns that downstream pipeline stages depend on)

If a user has to read the source to understand an exported function, the docstring has failed.

---

## 2. Format: Julia-Standard Markdown

All docstrings use Julia's triple-quoted string syntax placed immediately before the documented object. No blank lines between the docstring and the object it documents.

### Structure

Every docstring follows this skeleton, omitting inapplicable sections:

```julia
"""
    function_name(arg1::Type1, arg2::Type2; kwarg1=default) -> ReturnType

One-line summary in imperative mood, ending with a period.

Extended description if the one-liner is insufficient. Explain *why*
this exists, not just *what* it does. Wrap lines at 92 characters.

# Arguments
- `arg1::Type1`: description of the first argument.
- `arg2::Type2`: description of the second argument.

# Keywords
- `kwarg1::Type=default`: description of the keyword argument.

# Returns
- `ReturnType`: description of what is returned.

# Throws
- `ArgumentError`: when this specific condition is violated.

# Examples
```jldoctest
julia> function_name(x, y)
expected_output
```

# See also
- [`related_function`](@ref): brief description of the relationship.

# Extended help

Lengthy mathematical background, algorithm derivation, or performance
notes that would clutter the main docstring. Visible via `??` in the
REPL but hidden from `?`.
"""
```

Not every docstring needs every section — include only what's relevant. But when present, sections must appear in this order.

### Formatting Rules

| Rule | Rationale |
|------|-----------|
| Wrap lines at **92 characters** | Standard across BlueStyle, SciML, and the Julia manual |
| Use **imperative mood** ("Compute the index" not "Computes" or "Returns") | Matches the Julia standard library convention |
| **Backtick** all Julia identifiers (`` `PriceBars` ``, `` `true` ``, `` `Float64` ``) | Renders as code in all output formats |
| Indent the signature by **four spaces** | Julia convention; distinguishes the signature from prose |
| Place `"""` on **their own lines** | Avoids ragged indentation in multi-line docstrings |
| End the one-line summary with a **period** | Consistent punctuation |
| **No blank line** between closing `"""` and the object | Julia parser requirement — a blank line breaks the association silently |

### One-Line Docstrings

For trivially simple functions or constants, a single-line docstring is acceptable:

```julia
"""Return the smoothing factor `α = 2 / (period + 1)` for an EMA with the given `period`."""
_smoothing_factor(period::Int) = 2.0 / (period + 1)
```

Use one-liners only when the function has no keyword arguments, no noteworthy edge cases, and an obvious return type.

---

## 3. What to Document

### Always Document (mandatory)

| Target | Why |
|--------|-----|
| **Exported functions** (`calculate_indicator`, `get_data`) | Primary user-facing API |
| **Exported types** (`PriceBars`, `EMA`, `CUSUM`, `Label`) | Users construct these directly |
| **Exported abstract types** (`AbstractIndicator`, `AbstractBarrier`) | Users subtype these to extend the package |
| **Exported macros** (`@Event`, `@UpperBarrier`, etc.) | Most fragile surface area; users need examples |
| **The module itself** (`Backtest`) | Entry point; should list exports and show a quick-start example |

### Document When Non-Trivial (recommended)

| Target | When |
|--------|------|
| **Internal computation kernels** (`_ema_kernel_unrolled!`, `_calculate_cusum`) | When the algorithm is non-obvious or performance-critical |
| **`@generated` functions** (`_indicator_result`) | Always — metaprogramming is never self-evident |
| **Internal types used across modules** (`LabelResults`, `EventResult`) | When they appear in public return types |
| **NamedTuple builders** (functions defining pipeline keys) | These are implicit interface contracts between stages |
| **Index/alignment logic** (warmup lengths, temporal offsets) | Off-by-one bugs are the #1 source of backtesting errors |
| **Constants and configuration** (`DEFAULT_SPAN`, thresholds) | When their value affects user-visible behaviour |
| **Pipeline operator overloads** (`>>`) | Non-standard syntax that users encounter immediately |

Use this decision tree for internal functions:

| Criterion | Needs docstring? |
|-----------|-----------------|
| Contains non-trivial math or algorithms | **Yes** |
| Defines `NamedTuple` keys consumed by downstream stages | **Yes** |
| Has subtle correctness requirements (index arithmetic, warmup logic) | **Yes** |
| Is a `@generated` function | **Yes** |
| Is referenced in `TESTING.md` as a direct test target | **Yes** |
| Is a simple validator (`_natural(x)`) | No — intent is obvious from name + `@test_throws` coverage |
| Is glue code (thin delegation wrapper) | No — adds noise without value |

### Skip (do not document)

| Target | Why |
|--------|-----|
| **Simple validators** (`_natural(x)`) | Intent is obvious from name + `@test_throws` coverage |
| **Glue code** (thin delegation wrappers) | Adds noise without value |
| **Re-exports from dependencies** | Document at the source, not the passthrough |

### Document the Function, Not Individual Methods

Follow the Julia convention: write one docstring for the *function* (generic), not separate docstrings for each method. Only split into per-method docstrings when behaviour fundamentally diverges between methods (e.g., `calculate_indicator(::EMA, ...)` vs `calculate_indicator(::CUSUM, ...)` if their contracts differ).

---

## 4. Inline Code Comments

Docstrings and inline comments serve different purposes. Do not conflate them.

- **Docstrings** are the external-facing contract: what does this do, how do I call it, what comes back. They exist for *users* of the function.
- **Inline comments** are internal-facing notes for *readers of the implementation*. They should be rare.

### Philosophy: Code Speaks First

Code should be readable on its own. Well-chosen names, clear control flow, and small functions eliminate most need for comments. A comment that restates what the code does is pure noise — it doubles the maintenance surface and goes stale faster than the code it describes.

The only comments that earn their place explain **why** — decisions, constraints, or trade-offs that aren't evident from the code itself.

### When Comments Are Justified

| Situation | Example | Why it earns its place |
|-----------|---------|----------------------|
| **Performance trade-off** | Why a loop is manually unrolled instead of using the obvious approach | The "obvious" version was tried and was slower; without the comment, someone will "simplify" it back |
| **Algorithm reference** | Which paper or formula a kernel implements | You can't derive the intent from arithmetic alone |
| **Non-obvious precondition** | Why `p <= n` is assumed rather than checked | The caller already validated this; the comment prevents a redundant guard from being added |
| **Workaround for a known issue** | Compiler bug, dependency quirk, or platform-specific behaviour | Without context, the workaround looks like bad code and gets "fixed" |
| **Domain semantics** | Why `NaN` is used instead of `0.0` for warmup entries | The choice is meaningful (NaN propagates; zero silently corrupts downstream statistics) |

### When Comments Are Noise

| Pattern | Why it's noise |
|---------|---------------|
| `# Compute the SMA seed` above a function named `_sma_seed` | The name already says this |
| `# Loop through prices` above `for i in 1:n` | The code is self-evident |
| `# Return the result` above `return results` | Adds nothing |
| `# Check if period is valid` above `_natural(period)` | The function name conveys the intent |
| Commented-out code blocks | Use version control, not comments. Delete dead code |

### Section Headers

Section headers (ASCII dividers) are acceptable for organising long files into logical groups. Keep them lightweight:

```julia
# ── Barrier checking: recursive tuple unrolling ──
```

These help readers navigate a file without cluttering individual functions. Use the `# ── Description ──` format for consistency. Don't use heavy box-drawing styles — they draw attention disproportionate to their value.

### Examples from This Codebase

**Justified** — the field type `Function` doesn't convey *which* function:
```julia
struct Event{T<:Tuple} <: AbstractEvent
    conditions::T
    logic::Function # Stores bitwise operator (& / |)
end
```

**Justified** — explains *why* the fallback exists, not *what* it does:
```julia
# Fallback for non-symbols (numbers, strings, etc.)
_replace_symbols(ctx, ex) = ex
```

**Would be noise** — the function name already says this:
```julia
# BAD
# Calculate single EMA for one period
function _single_ema!(dest, prices, p, n)
```

### The Rule

If you're tempted to write a comment, first ask: can I make the code say this instead — through a better name, a clearer structure, or an extracted function? If yes, do that. If no, write the comment. Comments are a last resort, not a first instinct.

---

## 5. Docstring Templates by Category

### 4a. Module Docstring

The module docstring is the first thing users see after `using Backtest; ?Backtest`. It must orient them immediately.

```julia
"""
    Backtest

A performance-oriented framework for financial event-driven backtesting
using the triple-barrier method.

Compose indicator, event detection, and labelling stages into pipelines
using the `>>` operator:

    bars >> EMA(10, 50) >> event >> label

# Exports

**Types**: [`PriceBars`](@ref), [`EMA`](@ref), [`CUSUM`](@ref),
[`Event`](@ref), [`Label`](@ref), [`UpperBarrier`](@ref),
[`LowerBarrier`](@ref), [`TimeBarrier`](@ref),
[`ConditionBarrier`](@ref)

**Functions**: [`calculate_indicator`](@ref), [`get_data`](@ref),
[`calculate_side`](@ref), [`calculate_label`](@ref)

**Macros**: [`@Event`](@ref), [`@UpperBarrier`](@ref),
[`@LowerBarrier`](@ref), [`@TimeBarrier`](@ref),
[`@ConditionBarrier`](@ref)

**Directions**: [`LongOnly`](@ref), [`ShortOnly`](@ref),
[`LongShort`](@ref)

# Quick Start

```julia
using Backtest, Dates

bars = get_data("AAPL"; start_date="2020-01-01", end_date="2023-12-31")
job = bars >> EMA(10, 50) >> @Event(:ema_10 .> :ema_50) >> Label(
    @UpperBarrier(:entry_price * 1.05),
    @LowerBarrier(:entry_price * 0.95),
    @TimeBarrier(20),
)
result = job()
```
"""
module Backtest
```

### 4b. Abstract Type Docstring

Abstract types define extension points. Their docstrings are the **most important** in the package — they are the only place the interface contract lives.

```julia
"""
    AbstractIndicator

Supertype for all technical indicators.

# Interface

Subtypes must implement:

- `calculate_indicator(ind::MyIndicator, prices::AbstractVector{T}) where {T<:AbstractFloat}`:
    compute the indicator values from a price vector. Return a `Vector{T}`
    (single-output) or `Matrix{T}` (multi-output) with the same element
    type as the input.
- `_indicator_result(ind::MyIndicator, prices::AbstractVector{T}) -> NamedTuple`:
    wrap the raw indicator output in a `NamedTuple` with descriptive keys
    for pipeline composition (e.g., `(:ema_10,)`).

# Implementation Notes

- Indicators are callable: `ind(pricebars)` delegates to
    `calculate_indicator` and merges the result into the pipeline
    `NamedTuple`. Do **not** override the callable methods.
- Preserve the input element type (`Float32` in → `Float32` out) to
    support GPU workflows.
- Use `NaN` padding for warmup periods, not zero-filling.

# Naming Convention

Indicator result keys must be lowercase, using the pattern
`:indicatorname_parameter` (e.g., `:ema_10`, `:cusum`). These names
become the field names that downstream [`Event`](@ref) conditions and
[`@Event`](@ref) macro expressions reference.

# Existing Subtypes

- [`EMA`](@ref): Exponential Moving Average.
- [`CUSUM`](@ref): Cumulative Sum filter for structural breaks.
"""
abstract type AbstractIndicator end
```

### 4c. Concrete Struct Docstring

Document the purpose, fields, constructor constraints, and the callable interface.

```julia
"""
    EMA{Periods} <: AbstractIndicator

Exponential moving average indicator parameterised by one or more
periods.

Compute EMA values using the recursive formula
`EMA[t] = α * price[t] + (1 - α) * EMA[t-1]` where
`α = 2 / (period + 1)`. The first `period - 1` values are `NaN`
(warmup). The value at index `period` is the simple moving average
seed.

# Type Parameters
- `Periods::Tuple{Vararg{Int}}`: the EMA periods. Must be unique
    positive integers.

# Fields
- `multi_thread::Bool`: enable multi-threaded computation for
    multi-period EMAs.

# Constructors
    EMA(period::Int; multi_thread=false)
    EMA(periods::Vararg{Int}; multi_thread=false)

# Throws
- `ArgumentError`: if any period is non-positive, or periods are not
    unique.

# Examples
```jldoctest
julia> using Backtest

julia> ema = EMA(10);

julia> prices = collect(1.0:20.0);

julia> result = calculate_indicator(ema, prices);

julia> length(result) == 20
true

julia> all(isnan, result[1:9])
true
```

# See also
- [`CUSUM`](@ref): cumulative sum indicator for structural breaks.
- [`calculate_indicator`](@ref): the dispatch point for all indicators.

# Extended help

## Callable Interface

`EMA` instances are callable. When called with [`PriceBars`](@ref)
or a `NamedTuple` from a previous pipeline stage, they compute the
EMA on `bars.close` and merge the result into the pipeline data:

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

### 4d. Public Function Docstring

```julia
"""
    calculate_indicator(ind::EMA{Periods}, prices::AbstractVector{T}) where {Periods, T<:AbstractFloat} -> Union{Vector{T}, Matrix{T}}

Compute EMA values for `prices` at the periods specified in `ind`.

Return a `Vector{T}` when `Periods` contains a single period, or a
`Matrix{T}` of size `(length(prices), length(Periods))` for multiple
periods. The element type of the output matches the input.

# Arguments
- `ind::EMA{Periods}`: the EMA indicator instance.
- `prices::AbstractVector{T}`: price series. Must have at least
    `maximum(Periods)` elements for meaningful output.

# Returns
- `Vector{T}`: when `length(Periods) == 1`. First `period - 1`
    entries are `NaN`.
- `Matrix{T}`: when `length(Periods) > 1`. Column `j` corresponds
    to `Periods[j]`.

# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_indicator(EMA(3), prices);

julia> ema[3] ≈ 11.0
true
```

# See also
- [`EMA`](@ref): constructor and type documentation.

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

### 4e. Macro Docstring

Macros are the most error-prone part of the public API. Docstrings must show both simple and complex expressions, and explain the symbol rewriting rules.

```julia
"""
    @Event expr [key=val ...]

Construct an [`Event`](@ref) using a DSL expression with automatic
symbol rewriting.

Symbols prefixed with `:` in `expr` are rewritten to access fields of
the pipeline `NamedTuple`. For example, `:ema_10` becomes `d.ema_10`
and `:close` becomes `d.bars.close`.

# Arguments
- `expr`: a Julia expression using `:symbol` notation for pipeline
    fields. Multiple expressions create multiple conditions.

# Keywords
- `match::Symbol=:all`: how to combine multiple conditions. `:all`
    requires all conditions to be true (AND). `:any` requires at least
    one (OR).

# Examples

Simple crossover:
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

!!! warning "Broadcasting"
    Use dot-broadcasting operators (`.>`, `.&&`, `.*`, etc.) in the
    expression. A non-broadcasting operator will produce a scalar `Bool`
    instead of a vector, and the `Event` will emit a warning at runtime.

# See also
- [`Event`](@ref): the underlying type constructed by this macro.
- [`@UpperBarrier`](@ref), [`@LowerBarrier`](@ref): barrier macros
    using the same symbol rewriting rules.
"""
macro Event(args...)
    # ...
end
```

### 4f. Internal Kernel Docstring

Internal functions do not need the full template. Focus on the algorithm, mutation semantics, and performance contract.

```julia
"""
    _ema_kernel_unrolled!(dest, prices, period, n, α, β) -> Nothing

Fill `dest[period+1:n]` with EMA values using 4-wide loop unrolling
for instruction-level parallelism.

Mutate `dest` in-place. Assume `dest[period]` is already set to the
SMA seed. This function is the SIMD hot path — it must remain
zero-allocation and type-stable.

`α` is the smoothing factor `2/(period+1)` and `β = 1 - α`.
"""
function _ema_kernel_unrolled!(dest, prices, period, n, α, β)
```

```julia
"""
    _indicator_result(ind::EMA{Periods}, prices) -> NamedTuple

`@generated` function that returns a `NamedTuple` with keys derived
from the period values (e.g., `(:ema_10, :ema_50)`). Single-period
EMAs return vectors as values; multi-period EMAs return column views
into the result matrix.

This is the bridge between [`calculate_indicator`](@ref) (which returns
raw arrays) and the callable/pipeline interface (which needs named
fields for downstream access).
"""
@generated function _indicator_result(ind::EMA{Periods}, prices) where {Periods}
```

### 4g. Pipeline Operator Docstring

```julia
"""
    data >> stage -> Job
    job >> stage -> Job
    stage >> stage -> ComposedFunction

Compose pipeline stages using the `>>` operator.

When the left operand is data (e.g., [`PriceBars`](@ref)), create a
[`Job`](@ref) that can be executed with `job()`. When the left operand
is already a `Job`, append the stage. When both operands are pipeline
stages, create a composed function.

# Examples
```julia
job = bars >> EMA(10, 50) >> @Event(:ema_10 .> :ema_50) >> Label!(...)
result = job()
```

# See also
- [`PriceBars`](@ref): typical first stage of a pipeline.
- [`EMA`](@ref), [`Event`](@ref), [`Label`](@ref): common stages.
"""
```

### 4h. Direction/Enum-Like Type Docstrings

Small marker types get brief individual docstrings with cross-references.

```julia
"""
    LongOnly <: AbstractDirection

Restrict event detection to long (buy) signals only.

# See also
- [`ShortOnly`](@ref): restrict to short signals.
- [`LongShort`](@ref): allow both directions.
"""
struct LongOnly <: AbstractDirection end
```

### 4i. Core Data Container

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
- `bartype::B`: Bar type indicator ([`TimeBar`](@ref), `DollarBar`,
    etc.).

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

# See also
- [`get_data`](@ref): fetch historical data from YFinance.
- [`TimeBar`](@ref): the default bar type.
"""
struct PriceBars{B<:AbstractBarType,T<:AbstractFloat,V<:AbstractVector{T}}
    # ...
end
```

---

## 6. The `# Examples` Section

Examples are the most valuable part of a docstring. They serve as both documentation and executable tests.

### Use `jldoctest` Blocks for Testable Examples

Prefer `` ```jldoctest `` over `` ```julia `` whenever the output is deterministic.

```julia
"""
# Examples
```jldoctest
julia> using Backtest

julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_indicator(EMA(3), prices);

julia> ema[3] ≈ 11.0
true
```
"""
```

### Use `` ```julia `` for Non-Deterministic Examples

Network calls (`get_data`), file I/O, or anything involving randomness should use untested code blocks:

```julia
"""
# Examples
```julia
# Requires network access
df = get_data("AAPL"; start_date="2020-01-01")
```
"""
```

### Doctest Rules

| Rule | Rationale |
|------|-----------|
| **No `rand()` without a seeded RNG** | Output varies across sessions |
| **Self-contained** | Users copy-paste and run; don't reference undefined variables |
| **Always include `using Backtest`** | Each doctest runs in an isolated module — no implicit imports |
| **Whitespace-exact** | Array output must match character-for-character |
| **Use `≈` for floating-point** | Avoid fragile exact-equality on floats |
| **Use `[...]` for long error traces** | Match the `ERROR:` line, truncate the rest |
| **Semicolons to suppress output** | Use on setup lines to keep focus on demonstrated behaviour |

### Named Doctests for Multi-Step Examples

When an example spans setup and verification across multiple docstrings, use a shared label:

````julia
"""
```jldoctest pipeline_example
julia> using Backtest, Dates

julia> prices = Float64[10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

julia> result = calculate_indicator(EMA(3), prices);

julia> length(result) == length(prices)
true
```
"""
````

### Setup Blocks

For examples that require package imports, use the `setup` keyword:

````julia
"""
```jldoctest; setup = :(using Backtest)
julia> ema = EMA(10);

julia> ema isa AbstractIndicator
true
```
"""
````

### Filter Non-Deterministic Output

When output contains unavoidable non-deterministic content, use the `filter` keyword:

````julia
"""
```jldoctest; filter = r"[0-9\\.]+ seconds"
julia> @time calculate_indicator(EMA(10), randn(1000))
  0.000042 seconds (1 allocation: 7.875 KiB)
```
"""
````

### What Not to Doctest

| Scenario | Why | Alternative |
|----------|-----|-------------|
| Functions that hit the network (`get_data`) | Non-deterministic, slow, requires API access | Use a plain `julia` block with a comment: `# requires network` |
| Output with platform-dependent formatting | `Int` is `Int64` on 64-bit, `Int32` on 32-bit | Use explicit types or a filter |
| Very large output (matrices, DataFrames) | Brittle to formatting changes, hard to read | Show only a slice or assert a property instead |
| Pipeline results with many fields | NamedTuple printing is verbose and order-sensitive | Show individual field access: `result.ema_10[1:3]` |

### Running Doctests

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

## 7. The `# Extended help` Convention

Julia's REPL supports two help levels: `?foo` (brief) and `??foo` (full). Everything above `# Extended help` appears for `?foo`. Everything including and below appears for `??foo`.

Use this to keep the quick-help view concise while providing depth for users who want it. The first screen of `?foo` should answer "what does this do and how do I call it?" in under 30 lines.

### What Goes Where

| Content | Goes in... |
|---------|-----------|
| One-sentence summary | Brief section (above `# Extended help`) |
| Argument/keyword docs | Brief section |
| A short example | Brief section |
| `# See also` | Brief section |
| Mathematical derivation | `# Extended help` |
| Algorithm complexity analysis | `# Extended help` |
| Performance tuning guidance (threading, SIMD) | `# Extended help` |
| Comparison with alternative approaches | `# Extended help` |
| Historical context or references to papers | `# Extended help` |
| Callable interface / pipeline composition details | `# Extended help` |

### Example

```julia
"""
    CUSUM(threshold; span=100)

Cumulative Sum (CUSUM) filter for detecting structural breaks in a
price series.

# Examples
```jldoctest
julia> using Backtest

julia> cusum = CUSUM(1.0);

julia> typeof(cusum)
CUSUM
```

# See also
- [`EMA`](@ref): a smoothing indicator (contrast with CUSUM's
    change-detection approach).

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

## 8. Documenting for Extensibility

### The Interface Contract Pattern

Abstract types in this package define extension points. Their docstrings must spell out exactly what a subtype must implement — this is the *interface contract*. See the `AbstractIndicator` example in Section 4b.

For every abstract type, document:
1. **Required methods** with full signatures and return type expectations.
2. **Provided methods** (defaults) that subtypes should *not* override.
3. **Optional methods** with useful fallbacks.
4. **Existing subtypes** as a `# See also` list.

```julia
"""
    AbstractBarrier

Supertype for all barrier types used in the triple-barrier labelling
method.

# Interface

Subtypes must implement:

- A constructor accepting a condition function and a label value.
- Integration with `_check_barrier_recursive!` via the barrier
    dispatch mechanism.

Subtypes may optionally implement:

- Custom `show` methods for REPL display.

# Existing Subtypes

- [`UpperBarrier`](@ref): triggered when price crosses above a threshold.
- [`LowerBarrier`](@ref): triggered when price crosses below a threshold.
- [`TimeBarrier`](@ref): triggered after a fixed number of bars.
- [`ConditionBarrier`](@ref): triggered by an arbitrary boolean condition.
"""
abstract type AbstractBarrier end
```

### Field Documentation

For structs with more than two or three fields, document fields individually using inline strings. Julia's help system (`?Label`) displays these automatically.

```julia
struct Label{B<:Tuple,E<:AbstractExecutionBasis,NT<:NamedTuple} <: AbstractLabel
    "Tuple of barrier instances applied during labelling."
    barriers::B
    "Determines which price is used as the trade entry price."
    entry_basis::E
    "Drop events whose barriers are not resolved by end of data."
    drop_unfinished::Bool
    "Additional arguments forwarded to barrier evaluation."
    barrier_args::NT
end
```

This is complementary to the `# Fields` section in the type docstring — inline strings document individual fields, while `# Fields` provides the user-facing overview. Use inline strings for structs with 3+ fields; for simpler structs, the `# Fields` section alone is sufficient.

### Accessor Functions Over Fields

When a field's name or type may change, document an accessor function instead:

```julia
"""
    barriers(label::Label) -> Tuple

Return the barriers associated with `label`.
"""
barriers(label::Label) = label.barriers
```

Documented fields become implicit public API — changing them is a breaking change. Accessor functions provide a stable interface that decouples documentation from implementation.

---

## 9. Pipeline Data Flow Documentation

The `>>` pipeline is the core user experience. Its documentation has special requirements because the implicit interface between stages is defined by `NamedTuple` key conventions, not by types.

### Document the Data Flow

Every callable stage (indicators, events, labels) must document:

1. **What it expects in the input `NamedTuple`** (required keys).
2. **What it adds to the output `NamedTuple`** (new keys and their types).
3. **What it passes through unchanged** (merged keys from upstream).

Include this as a `# Pipeline Data Flow` section in the callable's docstring (or in `# Extended help` if the docstring is already long):

```julia
"""
# Pipeline Data Flow

## Input
Expects a `NamedTuple` with at least:
- `bars::PriceBars`: The price data.
- Additional keys as referenced by condition expressions
  (e.g., `:ema_10`, `:ema_50`).

## Output
Return the input `NamedTuple` merged with:
- `event_indices::Vector{Int}`: Indices where all (or any) conditions
  are satisfied.
"""
```

### Why This Matters

In a pipeline architecture, the return structure of one stage is the input interface of the next. An undocumented `NamedTuple` return is an anti-pattern (see Section 12, Anti-Pattern 7). Every stage's data contract must be explicit.

---

## 10. Cross-References and Discoverability

### `@ref` Links

Use `` [`Name`](@ref) `` to create clickable cross-references in Documenter.jl output. These are validated at build time — broken references become errors in strict mode.

### Rules

1. **Always cross-reference** when mentioning another exported symbol in a docstring. Write `` [`Event`](@ref) ``, not `` `Event` ``.
2. **Qualify ambiguous references**: If `calculate_indicator` is documented for multiple types, use `` [`calculate_indicator(::EMA, ::AbstractVector)`](@ref) ``.
3. **Link from `# Throws` sections**: `` [`ArgumentError`](@ref Base.ArgumentError) `` links to Base Julia docs.
4. **Link abstract types from concrete types**: Every concrete type's docstring should link to its parent abstract type.

### `# See also` Section Convention

Place `# See also` after `# Examples` and before `# Extended help`. Always alphabetical. One line per reference with a brief relationship description:

```julia
"""
# See also
- [`calculate_indicator`](@ref): the dispatch point for all indicators.
- [`CUSUM`](@ref): an alternative indicator for structural break detection.
- [`EMA`](@ref): constructor and type-parameter documentation.
"""
```

### Discoverability Checklist

Before merging a PR that adds a new public name, verify:

- [ ] The name has a docstring.
- [ ] The docstring has at least one example.
- [ ] Related functions reference each other via `# See also`.
- [ ] The module docstring lists the new export.
- [ ] `Docs.undocumented_names(Backtest)` does not include the new name (Julia 1.11+).

---

## 11. Writing Style

### Imperative Mood

Julia convention uses imperative mood for function summaries:

| Do | Don't |
|----|-------|
| "Compute the EMA for the given prices." | "Computes the EMA..." |
| "Return a `NamedTuple` of indicator results." | "Returns a NamedTuple..." |
| "Throw an `ArgumentError` if periods are empty." | "Throws an ArgumentError..." |

### Precision Over Brevity

Be specific about types, shapes, and edge-case behaviour. Vague docstrings are worse than no docstrings — they create false confidence.

| Vague | Precise |
|-------|---------|
| "Returns the EMA values." | "Return a `Vector{T}` of length `n` where the first `period - 1` entries are `NaN`." |
| "Takes a price array." | "`prices::AbstractVector{T}` where `T<:AbstractFloat`." |
| "May throw an error." | "Throw `ArgumentError` if any period is non-positive or periods are not unique." |

### Backtesting Domain Language

Use consistent terminology across all docstrings:

| Term | Meaning | Don't Say |
|------|---------|-----------|
| **warmup period** | The first `period - 1` entries filled with `NaN` | "burn-in", "padding" |
| **pipeline stage** | A callable composed via `>>` | "step", "phase" |
| **barrier** | A condition that terminates a label window | "stop", "limit" |
| **entry basis** | The price used as trade entry (`NextOpen`, `CurrentClose`) | "fill price", "execution price" |
| **event** | A detected signal in the data (indices where conditions hold) | "trigger", "signal" |
| **label** | The outcome classification (`Int8(-1)`, `Int8(0)`, `Int8(1)`) | "class", "target" |

---

## 12. Anti-Patterns

These are documentation mistakes to avoid. They are drawn from real Julia ecosystem patterns and adapted to this codebase.

### Anti-Pattern 1: No Docstring on an Exported Symbol

```julia
# BAD — exported with no documentation
export calculate_indicator
calculate_indicator(ind::EMA, prices) = ...
```

**Rule**: Every symbol in the `export` list gets a docstring. The `checkdocs = :exports` option in `makedocs` and `Docs.undocumented_names` enforce this mechanically.

### Anti-Pattern 2: Relying on Type Signatures as Documentation

```julia
# BAD — types tell you what kind of value, not what it represents
function _single_ema!(
    dest::AbstractVector{T}, prices::AbstractVector{T}, p::Int, n::Int
) where {T<:AbstractFloat}
```

`p::Int` could be a period, a price index, or a count. Types answer "what kind of value?" but not "what does this value represent?" or "what are the preconditions?".

```julia
# GOOD
"""
    _single_ema!(dest, prices, p, n)

Compute a single EMA of period `p` over `prices[1:n]`, writing
results into `dest`. Assume `length(dest) >= n` and `p <= n`.
"""
```

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
# What keys? What types? What order?
```

In a pipeline architecture, the return structure of one stage is the input interface of the next. Document every `NamedTuple` return — its keys, their types, and what they represent. This is especially critical for `_indicator_result` and the `Event` callable.

### Anti-Pattern 8: Forgetting `@ref` Cross-References

```julia
# BAD — mentions PriceBars but doesn't link to it
"""
Fetch historical OHLCV data. See PriceBars for the data container.
"""

# GOOD
"""
Fetch historical OHLCV data. See [`PriceBars`](@ref) for the data
container.
"""
```

Unlinked references become dead text in the rendered docs. Linked references become navigable and are validated at build time.

---

## 13. DocStringExtensions.jl (Optional Tooling)

[DocStringExtensions.jl](https://github.com/JuliaDocs/DocStringExtensions.jl) can auto-generate signature and field listings. It is **not currently a dependency** of this package. If adopted, use it as follows:

### Templates (module-level)

```julia
using DocStringExtensions

@template (FUNCTIONS, METHODS, MACROS) =
    """
    $(TYPEDSIGNATURES)

    $(DOCSTRING)
    """

@template TYPES =
    """
    $(TYPEDEF)

    $(DOCSTRING)

    # Fields
    $(TYPEDFIELDS)
    """
```

With templates active, individual docstrings contain only the descriptive body:

```julia
"""
Compute EMA values for `prices` at the periods specified in `ind`.

Return a `Vector{T}` for single-period or `Matrix{T}` for multi-period.

# Examples
```jldoctest
julia> using Backtest

julia> calculate_indicator(EMA(3), Float64[10,11,12,13,14,15])[3] ≈ 11.0
true
```
"""
function calculate_indicator(ind::EMA{Periods}, prices::AbstractVector{T}) where {Periods,T}
```

### When to Adopt

Adopt DocStringExtensions when:
- The package has 20+ documented functions and signature drift becomes a maintenance burden.
- A `docs/` site is being built with Documenter.jl.

Do not adopt it prematurely — the manual style in Section 4 is sufficient and more explicit.

---

## 14. Documenter.jl Site

This package does not currently have a `docs/` site. When one is created, follow this structure.

### Directory Layout

```
docs/
├── Project.toml          # docs-specific dependencies
├── make.jl               # Build script
└── src/
    ├── index.md          # Landing page / quick-start
    ├── tutorial.md       # The "90% use case" walkthrough
    ├── indicators.md     # Indicator guide + API
    ├── events.md         # Event detection guide + API
    ├── labels.md         # Triple-barrier labelling guide + API
    ├── pipelines.md      # Pipeline composition guide
    ├── extending.md      # How to add custom indicators/barriers
    └── api.md            # Full API reference
```

### `docs/make.jl`

```julia
using Documenter
using Backtest

makedocs(
    sitename = "Backtest.jl",
    modules  = [Backtest],
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    pages = [
        "Home"     => "index.md",
        "Tutorial" => "tutorial.md",
        "Guides" => [
            "Indicators" => "indicators.md",
            "Events"     => "events.md",
            "Labels"     => "labels.md",
            "Pipelines"  => "pipelines.md",
            "Extending"  => "extending.md",
        ],
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,   # Warn about undocumented exports
    doctest   = true,       # Run all jldoctest blocks
    strict    = true,       # Treat warnings as errors in CI
)

deploydocs(
    repo = "github.com/Wilsy99/Backtest.jl.git",
    devbranch = "main",
)
```

### Key `makedocs` Options

| Option | Value | Why |
|--------|-------|-----|
| `modules = [Backtest]` | Required | Enables docstring coverage checking — warns about any exported symbol whose docstring isn't in a `@docs`/`@autodocs` block |
| `checkdocs = :exports` | Required | Only checks exported symbols. Use `:all` to also check internals |
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

## Module

```@docs
Backtest
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

Prefer explicit `@docs` blocks — they make the page structure intentional and catch renamed/removed symbols at build time. Use `@autodocs` only when you want to include *everything* from a module without listing individual symbols.

---

## 15. CI Integration

### Doctest Execution in Tests

Add a doctest runner to the test suite so that stale examples break CI, not just the docs build:

```julia
@testitem "Doctests" tags=[:unit] begin
    using Documenter, Backtest
    doctest(Backtest)
end
```

### Documentation Coverage Check

On Julia 1.11+, use `Docs.undocumented_names` in CI to enforce that every export has a docstring:

```julia
@testitem "Documentation Coverage" tags=[:unit] begin
    using Backtest, Test
    undocumented = Docs.undocumented_names(Backtest)
    @test isempty(undocumented) ||
        error("Undocumented exports: $(join(undocumented, ", "))")
end
```

### Documentation Build in CI

When a `docs/` site exists, add a workflow step:

```yaml
- name: Build documentation
  run: julia --project=docs docs/make.jl
  env:
    DOCUMENTER_KEY: ${{ secrets.DOCUMENTER_KEY }}
```

The `strict = true` setting in `makedocs` ensures that missing docstrings, broken cross-references, and failed doctests all fail the CI build.

---

## 16. Priority Order

Complete each phase before moving to the next. Within a phase, order doesn't matter.

### Phase 1: Exported Types and Functions (do first)

| What | Why |
|------|-----|
| Module docstring for `Backtest` | First thing users see after `using Backtest; ?Backtest` |
| All exported types (`PriceBars`, `EMA`, `CUSUM`, `Event`, `Label`, barriers, directions) | Users construct these directly |
| All exported functions (`calculate_indicator`, `get_data`, `calculate_side`, `calculate_label`) | Primary API surface |
| All exported macros (`@Event`, `@UpperBarrier`, `@LowerBarrier`, `@TimeBarrier`, `@ConditionBarrier`) | Fragile surface area; examples prevent misuse |

### Phase 2: Abstract Types and Extension Points (do for every interface)

| What | Why |
|------|-----|
| `AbstractIndicator`, `AbstractBarrier`, `AbstractSide`, `AbstractEvent`, `AbstractLabel` | Define the extension contract for contributors |
| Pipeline operator (`>>`) and `Job` type | Core composition mechanism; non-obvious syntax |

### Phase 3: Examples and Doctests (do for every documented name)

| What | Why |
|------|-----|
| Add `jldoctest` blocks to all Phase 1–2 docstrings | Executable examples catch documentation rot |
| Add `julia` blocks for I/O-dependent examples (`get_data`) | Users need copy-pasteable examples even if untestable |
| Run `doctest(Backtest)` in CI | Prevents stale examples from accumulating |

### Phase 4: Internal Documentation (do for non-trivial internals)

| What | Why |
|------|-----|
| `@generated` functions (`_indicator_result`) | Metaprogramming is never self-documenting |
| Computation kernels (`_ema_kernel_unrolled!`, `_calculate_cusum`, `_sma_seed`) | Complex algorithms that future contributors must understand |
| Pipeline NamedTuple builders | Define the inter-stage data contract |
| Symbol rewriting internals (`_replace_symbols`, `_build_macro_components`) | Fragile macro plumbing |

### Phase 5: Documenter.jl Site (do when the API stabilises)

| What | Why |
|------|-----|
| `docs/` directory structure | Generates a browsable HTML site |
| Tutorial page ("the 90% use case") | Onboards new users faster than API reference alone |
| `checkdocs = :exports` and `strict = true` in CI | Enforces documentation coverage mechanically |

### Phase 6: Narrative Documentation (ongoing)

| What | Why |
|------|-----|
| Pipeline architecture guide (`pipelines.md`) | Explains the `>>` mental model |
| Per-module guides (indicators, events, labels) | Deep dives with worked examples |
| Extending guide (how to add a new indicator/barrier) | Unblocks external contributors |
| Performance guide | Threading, SIMD, allocation guidance |

### When Adding a New Component

Follow the same phase order: write the exported type docstring first (with fields, constructors, and examples), then the public function docstrings (with arguments, returns, throws), then the abstract type interface contract if it's a new extension point, then add `jldoctest` blocks, then document internal kernels if they exist. This applies to every new indicator, side, event, label, barrier, or future module.