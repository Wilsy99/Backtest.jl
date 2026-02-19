# Testing Philosophy & Framework for Backtest.jl

> **Living document.** This describes the testing *philosophy* and *conventions*, not a snapshot of what exists today. When you add a new module, feature, or pipeline stage, follow the patterns here. Sections marked with specific examples (EMA, CUSUM, etc.) are illustrative — apply the same patterns to every new component.

## 1. Core Mandate: Adversarial QA

Do not write tests to confirm the code works. Write tests to break it.

Every test should target one of these failure modes:

- **Type instabilities**: Code that defeats SIMD/unrolling optimizations.
- **Numerical edge cases**: NaN, Inf, 0.0, negative prices, Bitcoin-scale values, sub-penny values.
- **Boundary conditions**: Empty arrays, single elements, input shorter than feature period, period of 1.
- **Logic gaps**: Assumptions about sorted data, positive prices, non-overlapping time windows, warmup lengths.
- **Interface mismatches**: Field naming between pipeline stages (`:ema10` vs `:ema_10`), type expectations across `>>` composition.
- **Macro hygiene**: Symbol rewriting in `@Event`, `@UpperBarrier`, etc. producing incorrect expressions.

---

## 2. Framework: TestItems.jl

We use [TestItems.jl](https://github.com/JuliaTesting/TestItems.jl), not `include()`.

### Why

- **Isolation**: Each `@testitem` runs in its own module. No leaked state between test files.
- **Parallelism**: Items run concurrently with `--threads=auto` for free.
- **Selective execution**: Tags let you run subsets (`julia --tag=feature`).

### Format

Every test file is a collection of `@testitem` blocks:

```julia
@testitem "EMA: Reference Values" tags=[:feature, :ema, :unit] begin
    using Backtest, Test

    prices = Float64[10, 11, 12, 13, 14, 15]
    ema = calculate_feature(EMA(3), prices)

    @test ema[3] ≈ 11.0
    @test ema[4] ≈ 12.0
end
```

### Rules

1. **Explicit imports**: Every `@testitem` must `using Backtest, Test` (and any other deps) inside the block.
2. **No cross-item dependencies**: Never rely on variables or state from another item.
3. **Shared fixtures via `@testsetup`**: Common data generators live in a setup module that items can reference.
4. **Tags are mandatory**: Every item gets at least one category tag and one component tag.

### Tag Taxonomy

Every `@testitem` gets **at least one category tag** and **at least one component tag**.

**Category tags** (fixed — these describe *what kind* of test):

| Tag | Meaning |
|-----|---------|
| `:unit` | Tests a single function/type in isolation |
| `:property` | Invariant/property-based test (no hardcoded expected values) |
| `:reference` | Pinned against hand-calculated or external reference values |
| `:integration` | Tests multiple pipeline stages composed together |
| `:stability` | `@inferred`, JET checks, and zero-allocation kernel tests |
| `:allocation` | Allocation budget tests — verifies functions stay within computed byte limits |
| `:edge` | Boundary conditions, numerical extremes |
| `:macro` | DSL macro tests |

**Component tags** grow organically with the package. Don't predefine a full taxonomy — add a component tag when you write the first test for that component. Use lowercase, singular, matching the module or type name (e.g., `:ema`, `:cusum`, `:crossover`, `:pipeline`). For modules with multiple implementations, use a finer-grained tag per type (e.g., `:ema` and `:cusum` both fall under the broader `:feature` tag).

The current component tags in use are:

| Tag | Meaning |
|-----|---------|
| `:feature` | Feature module |
| `:ema` | EMA feature |
| `:cusum` | CUSUM feature |
| `:event` | Event detection module |
| `:label` | Label module |
| `:barrier` | Barrier types and dispatch |
| `:execution` | Execution basis types |
| `:pipeline` | Pipeline composition and `>>` operator |

When you add a new module or type, register a new component tag by adding a row to the table above and using it in your `@testitem` blocks.

---

## 3. Shared Test Fixtures via `@testsetup`

Test data generators are defined once and referenced by any `@testitem` that needs them.

```julia
@testsetup module TestData
    using Dates, Backtest

    function make_pricebars(;
        n::Int=200,
        start_price::Float64=100.0,
        start_date::DateTime=DateTime(2024, 1, 1),
        volatility::Float64=2.0,
    )
        timestamps = [start_date + Day(i - 1) for i in 1:n]
        close = [start_price + 0.05 * i + volatility * sin(2π * i / 20) for i in 1:n]

        # Guard against negative prices — the trend term (0.05 * i) grows slowly
        # relative to the sine amplitude (volatility). For short series with high
        # volatility, close prices can go negative, which causes DomainError in
        # CUSUM's log() call. Clamp to a small positive floor.
        close = max.(close, 0.01)

        open = vcat([start_price], close[1:(end - 1)])
        spread = [0.5 + 0.3 * abs(sin(0.7 * i)) for i in 1:n]
        high = max.(open, close) .+ spread
        low = min.(open, close) .- spread
        volume = [1000.0 + 100.0 * abs(sin(0.3 * i)) for i in 1:n]
        return PriceBars(open, high, low, close, volume, timestamps, TimeBar())
    end

    function make_trending_prices(
        direction::Symbol; n::Int=100, start::Float64=100.0, step::Float64=0.5
    )
        if direction === :up
            return [start + step * i for i in 0:(n - 1)]
        elseif direction === :down
            return [start - step * i for i in 0:(n - 1)]
        else
            error("direction must be :up or :down")
        end
    end

    make_flat_prices(; n::Int=200, price::Float64=100.0) = fill(price, n)

    function make_step_prices(;
        n::Int=200, low::Float64=100.0, high::Float64=120.0, step_at::Int=101
    )
        prices = Vector{Float64}(undef, n)
        prices[1:(step_at - 1)] .= low
        prices[step_at:end] .= high
        return prices
    end
end
```

**Safe parameter ranges for `make_pricebars`**: The default parameters (`start_price=100.0`, `volatility=2.0`) are safe for any `n`. If you increase `volatility` or decrease `start_price`, check that `start_price + 0.05 * 1 - volatility > 0` (i.e., `start_price > volatility`) to avoid relying on the floor clamp. When you need negative prices for edge-case testing, generate them explicitly rather than relying on fixture parameters — this makes the test intent clear.

Deterministic sine-wave fixtures are the default for most tests. Use `StableRNGs.jl` only when you need realistic stochastic price paths (e.g., stress-testing CUSUM signal rates under random walks).

---

## 4. The Four Layers of Quality

Every major component must pass all four layers.

### Layer 1: Package Quality (Aqua.jl)

One-time setup, catches entire bug classes automatically.

```julia
@testitem "Package Quality" tags=[:unit] begin
    using Backtest, Test, Aqua

    Aqua.test_all(Backtest; ambiguities=false)
end
```

This checks:
- No unbound type parameters in method signatures
- All dependencies declared in Project.toml
- No stale (unused) dependencies
- Correct compat bounds for all deps
- No type piracy

Enable `ambiguities=true` once the initial noise is resolved.

### Layer 2: Type Stability (`@inferred`)

Your `@simd`, `@inbounds`, and unrolled kernels are worthless if the compiler can't infer types. This is non-negotiable for a performance-oriented package.

```julia
@testitem "EMA: Type Stability" tags=[:feature, :ema, :stability] begin
    using Backtest, Test

    prices64 = Float64.(1:50)
    prices32 = Float32.(1:50)

    # Public API
    @test @inferred(calculate_feature(EMA(5), prices64)) isa Vector{Float64}
    @test @inferred(calculate_feature(EMA(5), prices32)) isa Vector{Float32}

    # Internal kernels (these drive the SIMD loops)
    @test @inferred(Backtest._feature_result(EMA(5), prices64)) isa NamedTuple
    @test @inferred(Backtest._feature_result(CUSUM(1.0), prices64)) isa NamedTuple
end
```

### Layer 3: Static Analysis (JET.jl)

JET traces the call graph and finds method errors, unreachable code, and optimisation failures that `@inferred` misses (e.g., an `Any`-typed intermediate inside a function whose return type is still concrete).

```julia
@testitem "EMA: Static Analysis" tags=[:feature, :ema, :stability] begin
    using Backtest, Test, JET

    prices = collect(1.0:100.0)

    # Check for optimisation issues (type instability inside the body)
    @test_opt target_modules=(Backtest,) calculate_feature(EMA(10), prices)

    # Check for method errors (calling a function that doesn't exist for those types)
    @test_call target_modules=(Backtest,) calculate_feature(EMA(10), prices)
end
```

**Important**: Use `target_modules=(Backtest,)` to filter out false positives from dependencies. Your codebase uses `@generated` functions and closures (`_get_condition_func`) which can produce JET noise from upstream packages — scope the analysis to your own code.

### Layer 4: Invariants (Property Tests)

Don't just check `ema[5] == 97.123`. Check properties that must hold for *any* valid input.

```julia
@testitem "EMA: Mathematical Properties" tags=[:feature, :ema, :property] begin
    using Backtest, Test

    # ... setup fixtures ...

    # Boundedness: EMA cannot exceed the input range
    @test minimum(valid_ema) >= minimum(prices) - eps()
    @test maximum(valid_ema) <= maximum(prices) + eps()

    # Convergence: constant input → EMA equals that constant
    @test all(calculate_feature(EMA(10), fill(42.0, 200))[10:end] .≈ 42.0)

    # Smoothness: longer period → lower variance of differences
    @test var(diff(ema_long)) < var(diff(ema_short))

    # Directionality: monotone input → monotone EMA (after warmup)
    @test all(diff(ema_up[6:end]) .> 0)

    # Lag: on a rising linear trend, EMA is below price
    @test all(ema[11:end] .< prices[11:end])
end
```

---

## 5. Required Test Categories

Beyond the four layers, every component needs these specific categories.

### A. Reference Values (at least one per component)

Pin at least one test against hand-calculated expected output. Property tests catch many bugs, but they *cannot* catch a wrong smoothing factor or off-by-one in the SMA seed.

```julia
@testitem "EMA: Hand-Calculated Reference" tags=[:feature, :ema, :reference] begin
    using Backtest, Test

    # α = 2/(3+1) = 0.5, SMA seed = (10+11+12)/3 = 11.0
    prices = Float64[10, 11, 12, 13, 14, 15]
    ema = calculate_feature(EMA(3), prices)

    @test all(isnan, ema[1:2])
    @test ema[3] ≈ 11.0
    @test ema[4] ≈ 12.0  # 0.5*13 + 0.5*11.0
    @test ema[5] ≈ 13.0
    @test ema[6] ≈ 14.0
end
```

### B. Edge Cases (mandatory per component)

These are non-negotiable for financial data:

| Scenario | What it catches |
|----------|----------------|
| Flat prices (`fill(100.0, n)`) | Division by zero in normalisation, false signals |
| Step function (100 → 200) | Lag behaviour, convergence speed |
| Input length < period | Index out of bounds, incorrect NaN padding |
| Input length == period | Fence-post errors |
| Single element | Empty slice bugs |
| Period of 1 | Degenerate case (EMA should equal input) |
| Very large prices (50,000+) | Overflow in squared terms |
| Very small prices (0.001) | Underflow, loss of precision |
| Float32 input | Type preservation for GPU compatibility |
| Negative prices (for log-based features) | `DomainError` from `log(-x)` |

### C. Integration Tests (pipeline stages composed)

The `>>` pipeline is the core user experience. Integration tests catch interface mismatches between stages that unit tests never will.

```julia
@testitem "Full Pipeline: EMA → Event → Label" tags=[:integration, :pipeline] begin
    using Backtest, Test, Dates

    # ... setup ...

    job = bars >> EMA(10, 50) >> evt >> lab
    result = job()

    @test result isa Backtest.LabelResults
    @test all(result.t₁ .>= result.t₀)
    @test all(l ∈ Int8.([-1, 0, 1]) for l in result.label)

    # Return consistency: upper barrier → positive return
    for i in eachindex(result.label)
        if result.label[i] == Int8(1)
            @test result.ret[i] > 0
        elseif result.label[i] == Int8(-1)
            @test result.ret[i] < 0
        end
    end

    # Log return identity
    for i in eachindex(result.ret)
        @test result.log_ret[i] ≈ log1p(result.ret[i]) atol=1e-12
    end
end
```

Also test: empty events (no signals → empty `LabelResults`), different directions (`LongOnly`, `ShortOnly`), data preservation through the pipeline (all intermediate fields survive `merge`).

### D. DSL Macro Tests

The `@Event`, `@UpperBarrier`, `@LowerBarrier`, `@TimeBarrier`, and `@ConditionBarrier` macros perform symbol rewriting via `_replace_symbols`. They are the most fragile part of the public API and must be tested explicitly.

#### Happy path: macro output matches manual construction

```julia
@testitem "Macro: @Event symbol rewriting" tags=[:macro, :event] begin
    using Backtest, Test, Dates

    bars = # ... make_pricebars ...
    nt = EMA(10, 50)(bars)

    # @Event should produce the same result as the manual Event() form
    evt_manual = Event(d -> d.ema_10 .> d.ema_50; match=:all)
    evt_macro  = @Event :ema_10 .> :ema_50 match=:all

    result_manual = evt_manual(nt)
    result_macro  = evt_macro(nt)

    @test result_manual.event_indices == result_macro.event_indices
end

@testitem "Macro: @UpperBarrier symbol rewriting" tags=[:macro, :label] begin
    using Backtest, Test

    # @UpperBarrier should rewrite :entry_price to d.entry_price
    # and :close to d.bars.close[d.idx]
    ub_manual = UpperBarrier(d -> d.entry_price * 1.05)
    ub_macro  = @UpperBarrier :entry_price * 1.05

    @test ub_manual.label == ub_macro.label  # both default to Int8(1)
end
```

#### Complex expressions: nested, mixed literals, and ambiguous syntax

Macro hygiene is a top failure mode. The happy-path tests above only verify that simple expressions rewrite correctly. You must also test expressions that stress the AST walker:

```julia
@testitem "Macro: Complex expression rewriting" tags=[:macro, :event, :edge] begin
    using Backtest, Test, Dates

    bars = # ... make_pricebars with EMA(10, 50) applied ...
    nt = EMA(10, 50)(bars)

    # Nested arithmetic: multiple symbols mixed with literals
    evt_manual = Event(d -> (d.ema_10 .* 0.5 .+ d.ema_50 .* 0.5) .> 100.0)
    evt_macro  = @Event (:ema_10 .* 0.5 .+ :ema_50 .* 0.5) .> 100.0

    r_manual = evt_manual(nt)
    r_macro  = evt_macro(nt)
    @test r_manual.event_indices == r_macro.event_indices

    # Multiple symbols in one barrier expression
    ub_manual = UpperBarrier(d -> d.entry_price + (d.ema_10[d.idx] - d.ema_50[d.idx]))
    ub_macro  = @UpperBarrier :entry_price + (:ema_10 - :ema_50)
    @test ub_manual.label == ub_macro.label
end

@testitem "Macro: Barrier with literals and field mixing" tags=[:macro, :label, :edge] begin
    using Backtest, Test, Dates

    # Literal-heavy expression: the walker must not rewrite numeric literals
    lb_macro = @LowerBarrier 0.95 * :entry_price - 2.0
    @test lb_macro isa LowerBarrier
    @test lb_macro.label == Int8(-1)

    # Expression that looks like a kwarg but isn't — verify it doesn't
    # get swallowed into the kwargs branch of _build_macro_components
    cb_macro = @ConditionBarrier :close <= :entry_price
    @test cb_macro isa ConditionBarrier

    # Boolean combination in ConditionBarrier
    cb_manual = ConditionBarrier(
        d -> d.ema_10[d.idx] < d.ema_50[d.idx] && d.bars.close[d.idx] <= d.entry_price
    )
    cb_macro = @ConditionBarrier :ema_10 < :ema_50 && :close <= :entry_price
    @test cb_manual.label == cb_macro.label
end
```

**What to cover for every macro:**

| Expression pattern | Why it matters |
|--------------------|---------------|
| Single symbol (`:close`) | Baseline — must work |
| Symbol × literal (`:entry_price * 1.05`) | Verify literals pass through untouched |
| Multiple symbols (`:ema_10 - :ema_50`) | Verify both get rewritten |
| Nested arithmetic (`:ema_10 * 0.5 + :ema_50 * 0.5`) | Deep AST traversal |
| Boolean operators (`&&`, `\|\|`) | Common in `@ConditionBarrier` |
| Comparison that resembles `=` (`:close <= :entry_price`) | Must not parse as a keyword argument |
| Parenthesised sub-expressions | Verify `Expr(:call, ...)` vs `Expr(:block, ...)` handling |

### E. Warning and Error Path Tests

Use `@test_throws` for invalid construction and `@test_logs` for expected warnings.

```julia
@testitem "CUSUM: Error and Warning Paths" tags=[:feature, :cusum, :edge] begin
    using Backtest, Test

    # Constructor validation
    @test_throws ArgumentError CUSUM(0.0)
    @test_throws ArgumentError CUSUM(-1.0)
    @test_throws ArgumentError CUSUM(1.0; span=0)

    # Warmup warning when data is too short
    @test_logs (:warn,) calculate_feature(CUSUM(1.0), fill(100.0, 50))

    # DomainError from log(-x) — note: log(0.0) returns -Inf, doesn't throw
    @test_throws DomainError calculate_feature(
        CUSUM(1.0), vcat(fill(100.0, 50), [-1.0], fill(100.0, 250))
    )
end
```

---

## 6. Performance Testing

This is a performance-oriented package — SIMD kernels, unrolled loops, and `@inbounds` are load-bearing. Performance regressions are bugs. This section covers how to catch them.

### 6a. Zero-Allocation Kernel Tests (`:stability` tag)

Computation kernels must not allocate on the hot path. Use `@allocated` to enforce this in tests.

```julia
@testitem "EMA: Zero Allocations in Kernel" tags=[:feature, :ema, :stability] begin
    using Backtest, Test

    prices = collect(1.0:200.0)
    dest = similar(prices)
    p = 10
    n = length(prices)
    α = 2.0 / (p + 1)
    β = 1.0 - α
    dest[p] = Backtest._sma_seed(prices, p)

    # Warmup call (JIT compilation)
    Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)

    # Pass inputs as arguments — closures that capture outer-scope variables
    # allocate due to Core.Box wrapping (Julia boxing for potential reassignment).
    allocs(dest, prices, p, n, α, β) =
        @allocated Backtest._ema_kernel_unrolled!(dest, prices, p, n, α, β)

    # Run 3 times, take minimum to avoid compilation/GC noise
    actual_kernel = minimum([@allocated(allocs(dest, prices, p, n, α, β)) for _ in 1:3])
    @test actual_kernel == 0
end
```

**When to test for zero allocations:**

- Mutating kernel functions (`_ema_kernel_unrolled!`, `_fill_sides_generic!`, `_calculate_cusum`)
- Pure helper functions (`_sma_seed`)
- Any function annotated with `@inbounds @simd`
- Inner loops of the barrier checking recursion

### 6b. Allocation Budget Tests (`:allocation` tag)

Non-kernel functions that allocate their result (vectors, matrices) must stay within a computed budget. These tests verify that no *unexpected* allocations sneak in — only the result container should be allocated.

**The Min-of-N measurement pattern:**

1. **Warmup** — call the target function once to trigger JIT compilation.
2. **Compute budget** — calculate the exact bytes for the result container data, plus a fixed overhead constant (see table below).
3. **Wrap in a function** — avoid Core.Box overhead from captured variables.
4. **Measure N=3 times, take the minimum** — filters tiered compilation and GC noise that inflate individual measurements.
5. **Assert budget** — `actual <= budget`.
6. **Sanity check** — `actual > 0` (the function *must* allocate its result).

```julia
@testitem "EMA: Allocation — _calculate_ema (single period)" tags=[:feature, :ema, :allocation] begin
    using Backtest, Test

    prices = collect(1.0:200.0)

    # Warmup target function
    Backtest._calculate_ema(prices, 10)

    # Budget: vector data + 512 bytes for container header + alignment + GC noise
    expected_data = sizeof(Float64) * length(prices)
    budget = expected_data + 512

    # Define wrapper
    allocs_ema(prices) = @allocated Backtest._calculate_ema(prices, 10)

    # Run 3 times, take minimum
    actual = minimum([@allocated(allocs_ema(prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0  # sanity: must allocate the result vector
end
```

**Why the function wrapper?** Julia's closures box outer-scope variables that *might* be reassigned (`Core.Box`), which adds spurious allocations to `@allocated`. Wrapping in a named function with explicit arguments avoids this entirely.

**Why Min-of-N?** A single `@allocated` measurement can be inflated by tiered JIT recompilation, GC pauses, or runtime bookkeeping. Taking the minimum of N=3 runs filters this noise while preserving the true allocation floor. The minimum is the right statistic here — we care about the *inherent* allocations, not the worst-case runtime jitter.

**Why fixed overhead constants instead of measuring `vec_header`?** Earlier versions computed the container header dynamically with `@allocated identity(Vector{T}(undef, 0))`. This gets DCE'd (Dead Code Eliminated) to 0 bytes on some platforms (confirmed on Windows Julia 1.12), making the budget too tight. Fixed constants (512, 1024, 1536 bytes) are large enough to absorb container headers (~80 bytes), alignment, and GC jitter, but small enough to catch real bugs like accidental data copies. For example, a 200-element `Float64` vector is 1600 bytes of data — a budget of 1600 + 512 = 2112 still catches a double-allocation (3200+ bytes).

**What to test with allocation budgets:**

| Function layer | Expected allocation | Overhead |
|----------------|-------------------|----------|
| `_calculate_ema` (single period) | `Vector{T}(undef, n)` | 512 bytes |
| `_calculate_ema` (Float32) | `Vector{Float32}(undef, n)` | 512 bytes |
| `_calculate_emas` (multi-period) | `Matrix{T}(undef, n, k)` | 512 bytes |
| `_calculate_cusum` | `Vector{Int8}(undef, n)` | 512 bytes |
| `calculate_feature` (single) | `Vector{T}(undef, n)` | 512 bytes |
| `calculate_feature` (multi) | `Matrix{T}(undef, n, k)` | 1536 bytes |
| EMA functor with PriceBars | Result vector + NamedTuple merge | 1024 bytes |
| EMA functor chaining | Result vector + NamedTuple merge | 1024 bytes |
| EMA functor multi-period | Result matrix + NamedTuple merge | 1024 bytes |
| CUSUM functor with PriceBars | Result vector + NamedTuple merge | 1024 bytes |

**Overhead constant rationale:**

| Constant | Used for | Why |
|----------|----------|-----|
| 512 bytes | Internal functions, `calculate_feature` single period | Container header is ~80 bytes; 512 gives comfortable margin for alignment and GC jitter |
| 1536 bytes | `calculate_feature` multi-period | Dispatches with Periods as a Tuple (not Vector), triggering a different specialization of `_calculate_emas` with more type-computation overhead |
| 1024 bytes | Functor calls (PriceBars, chaining, multi-period) | Accounts for `merge(input, feature_result)` NamedTuple construction overhead |

**When NOT to use `@allocated`:**

- Pipeline composition (`>>`) which creates arbitrarily nested NamedTuples
- Test setup and fixture generation

### 6c. Benchmark Regression (manual, not CI)

Full benchmark regression in CI is fragile (noisy timing on shared runners). Instead, maintain a `benchmarks/` directory with `BenchmarkTools.jl` scripts for manual use when optimising. The `sandbox.jl` file serves this purpose today.

The rule: **if you change a kernel, run the relevant benchmark before and after and include the comparison in your PR description.**

---

## 7. Decision Matrix: Testing Internal Functions

Use this decision tree when deciding whether a new internal function needs its own tests.

| Pattern | Test directly? | Rationale |
|---------|---------------|-----------|
| **Public API** (`calculate_*`, exported constructors) | **Always** | Primary testing surface |
| **Math/computation kernels** (mutating `!` functions, SIMD loops, numerical algorithms) | **Always** | Complex math + performance. Debug hell if you only test via the public API |
| **Index/alignment logic** (anything computing array indices, temporal offsets, warmup lengths) | **Always** | Backtesting correctness depends on perfect index alignment |
| **Named result builders** (functions that define NamedTuple keys consumed by downstream stages) | **Always** | These define the interface contract between pipeline stages |
| **DSL macro internals** (symbol rewriting, AST transforms) | **Via macro output** | Test the macros end-to-end, not the rewriting helpers |
| **Simple validators** (single-field checks like "must be positive") | **Via constructors** | Tested sufficiently through `@test_throws` on the public constructors |
| **Glue code** (thin wrappers, delegation, formatting) | **Via caller** | No independent logic to test |

When in doubt: if the function has a branch, a loop, or arithmetic, test it directly.

---

## 8. Data Generation Strategy

Use two complementary approaches:

### Deterministic Fixtures (default)

Sine-wave and step-function generators with zero external dependencies. Every value is computable by hand. Use these for reference tests, edge cases, and any test where you need to reason about exact values.

### Stochastic Fixtures (when needed)

`StableRNGs.jl` for realistic random-walk price paths. Use these for property tests and stress tests where you want to verify invariants hold across a wider input distribution, not just your hand-crafted data.

```julia
using StableRNGs
rng = StableRNG(42)
prices = 100.0 .+ cumsum(randn(rng, 1000))
```

The seed is always fixed. Tests must be deterministic.

---

## 9. CI Integration

### Test Execution

```yaml
- uses: julia-actions/julia-runtest@v1
  with:
    coverage: true
```

### Coverage Reporting

```yaml
- uses: julia-actions/julia-processcoverage@v1
- uses: codecov/codecov-action@v4
```

### Coverage Target

Coverage is not a vanity metric — it directly shows which kernels and barrier-checking code paths are exercised. The goal is not 100%. The goal is:

- **Every public API function** has at least one test that exercises it.
- **Every branch in computation kernels** (the `if`/`else` paths inside `_ema_kernel_unrolled!`, `_calculate_cusum`, `_check_barrier_recursive!`, etc.) is hit by at least one test.
- **Every error/warning path** reachable by user input is covered by a `@test_throws` or `@test_logs`.
- **Every macro** is tested with at least one simple and one complex expression.

Use the coverage report to identify gaps — if a branch in a kernel has zero hits, write a test that exercises it. If a public function has zero coverage, it's untested and therefore untrustworthy.

---

## 10. File Structure

### Convention

The test directory mirrors `src/` — one subdirectory per module, one test file per major type or concept. Shared infrastructure lives at the top level.

```
test/
├── runtests.jl                      # TestItems entry point (rarely changes)
├── setup_testdata.jl                # @testsetup module TestData
├── aqua_test.jl                     # Package quality (Aqua.jl)
├── type_tests.jl                    # Core types: PriceBars, directions, execution basis
├── macro_tests.jl                   # All DSL macros: symbol rewriting, default labels
├── integration_tests.jl             # Full pipelines, >> operator, data preservation
├── <module>/                        # One directory per src/ module
│   ├── <type>_tests.jl              # One file per major type/concept in that module
│   └── <module>_interface_tests.jl  # Callable interface, chaining, shared dispatch
└── ...
```

### Adding tests for a new module

When you add a new module (e.g., `src/Portfolio/`):

1. Create `test/portfolio/` to mirror it.
2. Add one `<type>_tests.jl` per major type (e.g., `portfolio_optimizer_tests.jl`).
3. Register a component tag (`:portfolio`) in the tag taxonomy table in Section 2.
4. If the module has a callable/pipeline interface, add `portfolio_interface_tests.jl`.
5. Add at least one integration test in `integration_tests.jl` that composes the new module with existing pipeline stages.

### Current structure (as of initial setup)

```
test/
├── runtests.jl
├── setup_testdata.jl
├── aqua_test.jl
├── type_tests.jl
├── feature/
│   ├── ema_tests.jl
│   ├── cusum_tests.jl
│   └── feature_interface_tests.jl
├── side/
│   └── crossover_tests.jl
├── event/
│   └── event_tests.jl
├── label/
│   ├── barrier_tests.jl
│   └── label_tests.jl
├── macro_tests.jl
└── integration_tests.jl
```

---

## 11. Priority Order

This is a phased approach. Complete each phase before moving to the next. Within a phase, order doesn't matter.

### Phase 1: Infrastructure (do once, benefits everything)

| What | Why |
|------|-----|
| Aqua.jl | 5 minutes, catches whole bug classes for free |
| Coverage in CI | Shows where gaps are before writing more tests |
| Test fixtures (`@testsetup`) | Unblocks all subsequent test writing |

### Phase 2: Core correctness (do for every component)

| What | Why |
|------|-----|
| Reference value tests | Catches algorithmic bugs that properties miss |
| `@inferred` type stability | Your SIMD optimisations depend on it |
| Property/invariant tests | More robust than hardcoded values across inputs |

### Phase 3: Robustness (do for every component)

| What | Why |
|------|-----|
| Edge case tests | Numerical robustness at boundaries |
| Integration (pipeline) tests | Catches interface mismatches between stages |
| DSL macro tests (simple + complex) | Fragile surface area, test before users depend on them |
| Zero-allocation kernel tests (`:stability`) | Catches accidental allocation regressions in hot paths |

### Phase 4: Deep analysis (do periodically)

| What | Why |
|------|-----|
| JET.jl static analysis | Catches internal type issues `@inferred` misses |

### Phase 5: Allocation budgets (do for every component with public API)

| What | Why |
|------|-----|
| Internal function budgets (`_calculate_ema`, `_calculate_emas`, `_calculate_cusum`) | Verifies internal functions allocate only the result container |
| `calculate_feature` budget (single + multi) | Verifies public API doesn't add hidden allocations on top of internals |
| Functor budget (PriceBars, chaining, multi-period) | Verifies callable interface overhead stays bounded |
| Float32 allocation parity | Ensures type-generic paths don't introduce extra allocations |

### When adding a new component

Follow the same phase order: write a reference test first, then `@inferred`, then properties, then edge cases, then hook it into an integration test, then zero-allocation kernel tests, then allocation budgets for every public-facing function layer. This applies to every new feature, side, event, label, or future module.