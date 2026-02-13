# Documentation Philosophy & Conventions for Backtest.jl

> **Living document.** This describes the documentation *philosophy* and *conventions*, not a snapshot of what exists today. When you add a new module, type, or public function, follow the patterns here. Sections marked with specific examples (EMA, CUSUM, etc.) are illustrative — apply the same patterns to every new component.

## 1. Core Mandate: Documentation as Contract

Docstrings are not afterthoughts or decorations. They are the **interface contract** between this package and its users. Every exported name must have a docstring that answers three questions:

1. **What does it do?** (one-line summary)
2. **How do I call it?** (signature, arguments, keyword arguments)
3. **What comes back?** (return type and shape)

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

### Formatting Rules

| Rule | Rationale |
|------|-----------|
| Wrap lines at **92 characters** | Standard across BlueStyle, SciML, and the Julia manual |
| Use **imperative mood** ("Compute the index" not "Computes" or "Returns") | Matches the Julia standard library convention |
| **Backtick** all Julia identifiers (`PriceBars`, `true`, `Float64`) | Renders as code in all output formats |
| Indent the signature by **four spaces** | Julia convention; distinguishes the signature from prose |
| Place `"""` on **their own lines** | Avoids ragged indentation in multi-line docstrings |
| End the one-line summary with a **period** | Consistent punctuation |
| **No blank line** between closing `"""` and the object | Julia parser requirement — a blank line breaks the association |

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
| **Internal types used across modules** (`LabelResults`, `EventResult`) | When they appear in public return types |
| **Constants and configuration** (`DEFAULT_SPAN`, thresholds) | When their value affects user-visible behaviour |
| **Pipeline operator overloads** (`>>`) | Non-standard syntax that users encounter immediately |

### Skip (do not document)

| Target | Why |
|--------|-----|
| **Simple validators** (`_natural(x)`) | Intent is obvious from name + `@test_throws` coverage |
| **Glue code** (thin delegation wrappers) | Adds noise without value |
| **Re-exports from dependencies** | Document at the source, not the passthrough |

### Document the Function, Not Individual Methods

Follow the Julia convention: write one docstring for the *function* (generic), not separate docstrings for each method. Only split into per-method docstrings when behaviour fundamentally diverges between methods (e.g., `calculate_indicator(::EMA, ...)` vs `calculate_indicator(::CUSUM, ...)` if their contracts differ).

---

## 4. Docstring Templates by Category

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

**Functions**: [`calculate_indicator`](@ref), [`get_data`](@ref)

**Macros**: [`@Event`](@ref), [`@UpperBarrier`](@ref),
[`@LowerBarrier`](@ref), [`@TimeBarrier`](@ref),
[`@ConditionBarrier`](@ref)

# Quick Start

```julia
using Backtest, Dates

bars = get_data("AAPL"; start_date="2020-01-01", end_date="2023-12-31")
pb = PriceBars(bars)
job = pb >> EMA(10, 50) >> @Event(:ema_10 .> :ema_50) >> Label(
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

Abstract types define extension points. Document the interface contract — what subtypes must implement.

```julia
"""
    AbstractIndicator

Supertype for all technical indicators.

Subtypes must implement:

- `calculate_indicator(ind::MyIndicator, prices::AbstractVector{T}) where {T<:AbstractFloat}`:
    compute the indicator values from a price vector. Return a `Vector{T}`
    (single-output) or `Matrix{T}` (multi-output) with the same element
    type as the input.
- `_indicator_result(ind::MyIndicator, prices::AbstractVector{T}) -> NamedTuple`:
    wrap the raw indicator output in a `NamedTuple` with descriptive keys
    for pipeline composition.

# Implementation Notes
- Indicators are callable: `ind(pricebars)` delegates to `calculate_indicator`
    and merges the result into the pipeline `NamedTuple`.
- Preserve the input element type (`Float32` in → `Float32` out) to
    support GPU workflows.
- Use `NaN` padding for warmup periods, not zero-filling.
"""
abstract type AbstractIndicator end
```

### 4c. Concrete Struct Docstring

Document the purpose, fields, constructor constraints, and the callable interface.

```julia
"""
    EMA{Periods} <: AbstractIndicator

Exponential moving average indicator parameterised by one or more periods.

Compute EMA values using the recursive formula `EMA[t] = α * price[t] + (1 - α) * EMA[t-1]`
where `α = 2 / (period + 1)`. The first `period - 1` values are `NaN` (warmup). The
value at index `period` is the simple moving average seed.

# Type Parameters
- `Periods::Tuple{Vararg{Int}}`: the EMA periods. Must be unique positive integers.

# Fields
- `multi_thread::Bool`: enable multi-threaded computation for multi-period EMAs.

# Constructor
    EMA{(10,)}(; multi_thread=false)
    EMA(periods::Int...; multi_thread=false)

# Throws
- `ArgumentError`: if any period is non-positive, or periods are not unique.

# Examples
```jldoctest
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
"""
struct EMA{Periods} <: AbstractIndicator
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
- `Vector{T}`: when `length(Periods) == 1`. First `period - 1` entries are `NaN`.
- `Matrix{T}`: when `length(Periods) > 1`. Column `j` corresponds to `Periods[j]`.

# Examples
```jldoctest
julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_indicator(EMA(3), prices);

julia> ema[3] ≈ 11.0
true
```

# See also
- [`EMA`](@ref): constructor and type documentation.
"""
function calculate_indicator(
    ind::EMA{Periods}, prices::AbstractVector{T}
) where {Periods, T<:AbstractFloat}
```

### 4e. Macro Docstring

Macros are the most error-prone part of the public API. Docstrings must show both simple and complex expressions, and explain the symbol rewriting rules.

```julia
"""
    @Event(expr; match=:all)

Construct an [`Event`](@ref) using a DSL expression with automatic symbol rewriting.

Symbols prefixed with `:` in `expr` are rewritten to access fields of the
pipeline `NamedTuple`. For example, `:ema_10` becomes `d.ema_10` and
`:close` becomes `d.bars.close`.

# Arguments
- `expr`: a Julia expression using `:symbol` notation for pipeline fields.

# Keywords
- `match::Symbol=:all`: either `:all` (return all matching indices) or
    `:first` (return only the first match).

# Examples

Simple crossover:
```julia
evt = @Event :ema_10 .> :ema_50
```

Weighted average threshold:
```julia
evt = @Event (:ema_10 .* 0.5 .+ :ema_50 .* 0.5) .> 100.0
```

First match only:
```julia
evt = @Event :ema_10 .> :ema_50 match=:first
```

# See also
- [`Event`](@ref): the underlying type constructed by this macro.
- [`@UpperBarrier`](@ref), [`@LowerBarrier`](@ref): barrier macros
    using the same symbol rewriting rules.
"""
macro Event(expr)
```

### 4f. Internal Kernel Docstring

Internal functions do not need the full template. Focus on the algorithm, mutation semantics, and performance contract.

```julia
"""
    _ema_kernel_unrolled!(dest, prices, period, n, α, β)

Fill `dest[period+1:n]` with EMA values using the unrolled recurrence.

Mutate `dest` in-place. Assume `dest[period]` is already set to the SMA seed.
This function is the SIMD hot path — it must remain zero-allocation and type-stable.

`α` is the smoothing factor `2/(period+1)` and `β = 1 - α`.
"""
function _ema_kernel_unrolled!(dest, prices, period, n, α, β)
```

### 4g. Pipeline Operator Docstring

```julia
"""
    >>(left, right)

Compose two pipeline stages into a callable chain.

The `>>` operator is the primary way to build backtesting pipelines.
Each stage receives the output `NamedTuple` of the previous stage and
merges its results in.

# Examples
```julia
pipeline = pricebars >> EMA(10, 50) >> event >> label
result = pipeline()
```

# See also
- [`PriceBars`](@ref): typical first stage of a pipeline.
- [`EMA`](@ref), [`Event`](@ref), [`Label`](@ref): common pipeline stages.
"""
```

### 4h. Direction/Enum-Like Type Docstrings

Small marker types can share a docstring or use brief individual ones.

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

---

## 5. The `# Examples` Section

Examples are the most valuable part of a docstring. They serve as both documentation and executable tests.

### Use `jldoctest` Blocks for Testable Examples

Prefer ` ```jldoctest ` over ` ```julia ` whenever the output is deterministic.

```julia
"""
# Examples
```jldoctest
julia> prices = Float64[10, 11, 12, 13, 14, 15];

julia> ema = calculate_indicator(EMA(3), prices);

julia> ema[3] ≈ 11.0
true
```
"""
```

### Use ` ```julia ` for Non-Deterministic Examples

Network calls (`get_data`), file I/O, or anything involving randomness should use untested code blocks:

```julia
"""
# Examples
```julia
df = get_data("AAPL"; start_date="2020-01-01")
bars = PriceBars(df)
```
"""
```

### Doctest Rules

| Rule | Rationale |
|------|-----------|
| **No `rand()` without a seeded RNG** | Output varies across sessions |
| **Self-contained** | Users copy-paste and run; don't reference undefined variables |
| **Whitespace-exact** | Array output must match character-for-character |
| **Use `≈` for floating-point** | Avoid fragile exact-equality on floats |
| **Use `[...]` for long error traces** | Match `ERROR:` line, truncate the rest |

### Named Doctests for Multi-Step Examples

When an example spans setup and verification across multiple docstrings, use a shared label:

```julia
"""
```jldoctest pipeline_example
julia> using Backtest, Dates

julia> prices = Float64[10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

julia> result = calculate_indicator(EMA(3), prices);

julia> length(result) == length(prices)
true
```
"""
```

### Setup Blocks

For examples that require package imports, use the `setup` keyword:

```julia
"""
```jldoctest; setup = :(using Backtest)
julia> ema = EMA(10);

julia> ema isa AbstractIndicator
true
```
"""
```

---

## 6. Documenting for Extensibility

### The Interface Contract Pattern

Abstract types in this package define extension points. Their docstrings must spell out exactly what a subtype must implement — this is the *interface contract*.

```julia
"""
    AbstractBarrier

Supertype for all barrier types used in the triple-barrier labelling method.

# Interface

Subtypes must implement:

- A constructor accepting a condition function and a label value.
- Integration with `_check_barrier_recursive!` via the barrier dispatch
    mechanism.

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

For structs with more than two or three fields, document fields individually using inline strings:

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

Julia's help system (`?Label`) displays these inline field docstrings automatically.

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

## 7. Cross-References and Discoverability

### `@ref` Links

Use `[`Name`](@ref)` to create clickable cross-references in Documenter.jl output. Use them in:

- `# See also` sections
- Prose descriptions ("pass a [`PriceBars`](@ref) instance")
- Module docstrings listing exports

### `# See also` Section Convention

Always alphabetical. One line per reference with a brief relationship description:

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

## 8. Writing Style

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

## 9. DocStringExtensions.jl (Optional Tooling)

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

## 10. Documenter.jl Site (Future)

This package does not currently have a `docs/` site. When one is created, follow this structure.

### Directory Layout

```
docs/
├── src/
│   ├── index.md            # Landing page / quick-start
│   ├── tutorial.md         # The "90% use case" walkthrough
│   ├── indicators.md       # Indicator guide + API
│   ├── events.md           # Event detection guide + API
│   ├── labels.md           # Triple-barrier labelling guide + API
│   ├── pipelines.md        # Pipeline composition guide
│   ├── extending.md        # How to add custom indicators/barriers
│   └── api.md              # Full API reference (auto-generated)
├── make.jl                 # Build script
└── Project.toml            # Docs-specific dependencies
```

### `make.jl` Template

```julia
using Documenter
using Backtest

makedocs(
    sitename = "Backtest.jl",
    modules  = [Backtest],
    pages    = [
        "Home"        => "index.md",
        "Tutorial"    => "tutorial.md",
        "Guides" => [
            "Indicators" => "indicators.md",
            "Events"     => "events.md",
            "Labels"     => "labels.md",
            "Pipelines"  => "pipelines.md",
            "Extending"  => "extending.md",
        ],
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,
    doctest   = true,
)

deploydocs(
    repo = "github.com/Wilsy99/Backtest.jl.git",
)
```

### API Page Template (`api.md`)

````markdown
# API Reference

## Module

```@docs
Backtest
```

## Types

```@docs
PriceBars
EMA
CUSUM
Event
Label
UpperBarrier
LowerBarrier
TimeBarrier
ConditionBarrier
```

## Functions

```@docs
calculate_indicator
get_data
```

## Macros

```@docs
@Event
@UpperBarrier
@LowerBarrier
@TimeBarrier
@ConditionBarrier
```
````

### `checkdocs = :exports`

This setting makes `makedocs` warn about any exported name that lacks a docstring. Treat these warnings as errors in CI once all exports are documented.

### Doctest Integration

Enable `doctest = true` in `makedocs` to run all `jldoctest` blocks during the documentation build. Alternatively, add `doctest(Backtest)` to `test/runtests.jl` to catch docstring rot during regular CI.

---

## 11. CI Integration for Documentation

### Doctest Execution in Tests

Add a doctest runner to the test suite so that stale examples break CI, not just the docs build:

```julia
@testitem "Doctests" tags=[:unit] begin
    using Documenter, Backtest
    doctest(Backtest)
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

### Checking for Undocumented Exports

On Julia 1.11+, use `Docs.undocumented_names` in CI to enforce coverage:

```julia
@testitem "Documentation Coverage" tags=[:unit] begin
    using Backtest, Test
    undocumented = Docs.undocumented_names(Backtest)
    @test isempty(undocumented) || error("Undocumented exports: $undocumented")
end
```

---

## 12. Priority Order

Complete each phase before moving to the next. Within a phase, order doesn't matter.

### Phase 1: Exported Types and Functions (do first)

| What | Why |
|------|-----|
| Module docstring for `Backtest` | First thing users see after `using Backtest; ?Backtest` |
| All exported types (`PriceBars`, `EMA`, `CUSUM`, `Event`, `Label`, barriers, directions) | Users construct these directly |
| All exported functions (`calculate_indicator`, `get_data`) | Primary API surface |
| All exported macros (`@Event`, `@UpperBarrier`, etc.) | Fragile surface area; examples prevent misuse |

### Phase 2: Abstract Types and Extension Points (do for every interface)

| What | Why |
|------|-----|
| `AbstractIndicator`, `AbstractBarrier`, `AbstractSide`, etc. | Define the extension contract for contributors |
| Pipeline operator (`>>`) | Core composition mechanism; non-obvious syntax |

### Phase 3: Examples and Doctests (do for every documented name)

| What | Why |
|------|-----|
| Add `jldoctest` blocks to all exported function docstrings | Executable examples catch documentation rot |
| Add `julia` blocks for I/O-dependent examples (`get_data`) | Users need copy-pasteable examples even if untestable |
| Run `doctest(Backtest)` in CI | Prevents stale examples from accumulating |

### Phase 4: Internal Documentation (do for performance-critical code)

| What | Why |
|------|-----|
| Computation kernels (`_ema_kernel_unrolled!`, `_calculate_cusum`) | Complex algorithms that future contributors must understand |
| Pipeline NamedTuple builders (`_indicator_result`) | Define the inter-stage contract |
| Symbol rewriting internals (`_replace_symbols`) | Fragile macro plumbing |

### Phase 5: Documenter.jl Site (do when the API stabilises)

| What | Why |
|------|-----|
| `docs/` directory structure | Generates a browsable HTML site |
| Tutorial page ("the 90% use case") | Onboards new users faster than API reference alone |
| `checkdocs = :exports` in CI | Enforces documentation coverage mechanically |

### When Adding a New Component

Follow the same phase order: write the type docstring first (with fields and constructor), then the public function docstrings (with arguments, returns, and throws), then add examples, then document internal kernels if they exist. This applies to every new indicator, side, event, label, or future module.
