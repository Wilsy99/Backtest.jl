# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Core Correctness
# ─────────────────────────────────────────────────────────────────────────────

@testitem "CUSUM: Hand-Calculated Reference" tags = [:indicator, :cusum, :reference] begin
    using Backtest, Test

    # Flat prices (100.0) for 101 bars → all log-returns during warmup are 0
    # ema_sq_mean = 0/100 = 0.0 → threshold = sqrt(1e-16) * 1.0 = 1e-8
    # Jump to 200.0 at index 102: log_return = log(2) ≈ 0.693
    # s_pos = max(0, 0 + 0.693 - 0) = 0.693 > 1e-8 → signal +1 at index 102
    prices_up = vcat(fill(100.0, 101), [200.0])
    vals_up = calculate_indicator(CUSUM(1.0), prices_up)

    @test length(vals_up) == 102
    @test eltype(vals_up) == Int8
    @test all(vals_up[1:101] .== Int8(0))   # warmup indices all zero
    @test vals_up[102] == Int8(1)            # positive signal on upward jump

    # Drop to 50.0 at index 102: log_return = log(0.5) ≈ -0.693
    # s_neg = min(0, 0 + (-0.693) + 0) = -0.693 < -1e-8 → signal -1
    prices_down = vcat(fill(100.0, 101), [50.0])
    vals_down = calculate_indicator(CUSUM(1.0), prices_down)

    @test vals_down[102] == Int8(-1)         # negative signal on downward jump

    # Multi-signal trace: flat warmup then alternating jumps
    # i=102: log(200/100)=+0.693, s_pos=0.693 > 1e-8 → +1, s_pos reset
    #   ema_sq_mean = (2/101)*0.693^2 + (99/101)*0 ≈ 0.00951
    # i=103: log(100/200)=-0.693, threshold=sqrt(0.00951)≈0.0975
    #   s_neg = min(0, 0 + (-0.693)) = -0.693 < -0.0975 → -1, s_neg reset
    # i=104: log(200/100)=+0.693, threshold≈0.137
    #   s_pos = max(0, 0 + 0.693) = 0.693 > 0.137 → +1
    prices_multi = vcat(fill(100.0, 101), [200.0, 100.0, 200.0])
    vals_multi = calculate_indicator(CUSUM(1.0), prices_multi)

    @test vals_multi[102] == Int8(1)
    @test vals_multi[103] == Int8(-1)
    @test vals_multi[104] == Int8(1)
end

@testitem "CUSUM: Output Domain Property" tags = [:indicator, :cusum, :property] setup = [
    TestData
] begin
    using Backtest, Test

    for prices in [
        TestData.make_pricebars(; n=200).close,
        TestData.make_trending_prices(:up; n=200, start=50.0, step=0.5),
        [100.0 + 10.0 * sin(2π * i / 20) for i in 1:200],
    ]
        vals = calculate_indicator(CUSUM(1.0), prices)

        @test length(vals) == length(prices)
        @test eltype(vals) == Int8
        @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals)
    end
end

@testitem "CUSUM: Type Stability" tags = [:indicator, :cusum, :stability] begin
    using Backtest, Test

    prices64 = collect(100.0:300.0)  # 201 elements, > warmup

    # Public API — Float64
    @test @inferred(calculate_indicator(CUSUM(1.0), prices64)) isa Vector{Int8}

    # Float32 CUSUM with Float32 prices
    prices32 = Float32.(collect(100.0f0:300.0f0))
    @test @inferred(calculate_indicator(CUSUM(1.0f0), prices32)) isa Vector{Int8}

    # Internal: named result builder
    @test @inferred(Backtest._indicator_result(CUSUM(1.0), prices64)) isa NamedTuple
end

@testitem "CUSUM: Mathematical Properties" tags = [:indicator, :cusum, :property] setup = [
    TestData
] begin
    using Backtest, Test

    prices = TestData.make_pricebars(; n=200).close

    # ── Warmup invariant: indices 1:101 always zero ──
    vals = calculate_indicator(CUSUM(1.0), prices)
    @test all(vals[1:101] .== Int8(0))

    # ── Flat prices → all zeros ──
    flat = TestData.make_flat_prices(; price=100.0, n=200)
    vals_flat = calculate_indicator(CUSUM(1.0), flat)
    @test all(vals_flat .== Int8(0))

    # ── Higher multiplier → fewer or equal signals ──
    vals_low = calculate_indicator(CUSUM(1.0), prices)
    vals_high = calculate_indicator(CUSUM(5.0), prices)
    n_signals_low = count(v -> v != 0, vals_low)
    n_signals_high = count(v -> v != 0, vals_high)
    @test n_signals_high <= n_signals_low

    # ── Directional consistency: strong upward spike → +1 ──
    spike_up = vcat(fill(100.0, 101), [200.0])
    vals_up = calculate_indicator(CUSUM(1.0), spike_up)
    @test vals_up[102] == Int8(1)

    # ── Directional consistency: strong downward spike → -1 ──
    spike_down = vcat(fill(100.0, 101), [50.0])
    vals_down = calculate_indicator(CUSUM(1.0), spike_down)
    @test vals_down[102] == Int8(-1)

    # ── Signal sparsity: accumulators reset after signal ──
    # After signal fires, accumulator resets; values remain in domain
    spiky = vcat(fill(100.0, 101), [200.0, 100.0, 200.0, 100.0, 200.0])
    vals_spiky = calculate_indicator(CUSUM(1.0), spiky)
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spiky)
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Edge Cases
# ─────────────────────────────────────────────────────────────────────────────

@testitem "CUSUM: Constructor Validation" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Invalid: multiplier must be > 0
    @test_throws ArgumentError CUSUM(0.0)
    @test_throws ArgumentError CUSUM(-1.0)

    # Invalid: span must be a positive integer
    @test_throws ArgumentError CUSUM(1.0; span=0)
    @test_throws ArgumentError CUSUM(1.0; span=-1)

    # Valid constructions
    @test CUSUM(1.0) isa CUSUM
    @test CUSUM(0.5; span=50) isa CUSUM
    @test CUSUM(1.0; expected_value=0.01) isa CUSUM
    @test CUSUM(3.0; span=200, expected_value=0.005) isa CUSUM
end

@testitem "CUSUM: Data Shorter Than Warmup" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    prices_50 = fill(100.0, 50)
    prices_101 = fill(100.0, 101)
    prices_102 = fill(100.0, 102)

    # n = 50: warns, returns all zeros
    vals_50 = @test_logs (:warn,) calculate_indicator(CUSUM(1.0), prices_50)
    @test length(vals_50) == 50
    @test all(vals_50 .== Int8(0))

    # n = 101: exactly at boundary (n <= warmup_idx=101) → warns, returns all zeros
    vals_101 = @test_logs (:warn,) calculate_indicator(CUSUM(1.0), prices_101)
    @test length(vals_101) == 101
    @test all(vals_101 .== Int8(0))

    # n = 102: minimum post-warmup → no warning, one post-warmup index
    vals_102 = calculate_indicator(CUSUM(1.0), prices_102)
    @test length(vals_102) == 102
    @test all(vals_102[1:101] .== Int8(0))
end

@testitem "CUSUM: Negative Prices" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Negative price in warmup range → DomainError from log()
    prices_neg_warmup = fill(100.0, 200)
    prices_neg_warmup[50] = -1.0
    @test_throws DomainError calculate_indicator(CUSUM(1.0), prices_neg_warmup)

    # Negative price after warmup → DomainError from log()
    prices_neg_post = fill(100.0, 200)
    prices_neg_post[150] = -1.0
    @test_throws DomainError calculate_indicator(CUSUM(1.0), prices_neg_post)

    # Zero price: log(0.0) = -Inf → doesn't throw, downstream becomes Inf
    # With Inf ema_sq_mean, threshold = Inf, so no signals fire
    prices_zero = fill(100.0, 200)
    prices_zero[50] = 0.0
    vals = calculate_indicator(CUSUM(1.0), prices_zero)
    @test length(vals) == 200
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals)
end

@testitem "CUSUM: Very Large Prices" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Flat large prices → all zeros (log-returns are zero)
    prices_flat = fill(50_000.0, 200)
    vals_flat = calculate_indicator(CUSUM(1.0), prices_flat)

    @test all(vals_flat .== Int8(0))
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_flat)

    # Large prices with a spike → signals still valid
    prices_spike = vcat(fill(50_000.0, 101), [100_000.0], fill(50_000.0, 98))
    vals_spike = calculate_indicator(CUSUM(1.0), prices_spike)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spike)
    @test any(vals_spike[102:end] .== Int8(1))  # spike triggers positive signal
end

@testitem "CUSUM: Very Small Prices" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Flat small prices → all zeros (log-returns are zero)
    # log(0.001) ≈ -6.9, finite and valid
    prices_flat = fill(0.001, 200)
    vals_flat = calculate_indicator(CUSUM(1.0), prices_flat)

    @test all(vals_flat .== Int8(0))
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_flat)

    # Small prices with a spike → signals still valid
    prices_spike = vcat(fill(0.001, 101), [0.002], fill(0.001, 98))
    vals_spike = calculate_indicator(CUSUM(1.0), prices_spike)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spike)
end

@testitem "CUSUM: Flat Prices" tags = [:indicator, :cusum, :edge] setup = [TestData] begin
    using Backtest, Test

    # Flat prices: log-returns are exactly 0, accumulators never grow
    flat = TestData.make_flat_prices(; price=100.0, n=200)
    vals = calculate_indicator(CUSUM(1.0), flat)

    @test all(vals .== Int8(0))
end

@testitem "CUSUM: Step Function" tags = [:indicator, :cusum, :edge] setup = [TestData] begin
    using Backtest, Test

    # Flat 100.0 for 101 bars, then jump to 200.0 → positive signal
    prices_up = TestData.make_step_prices(; n=200, low=100.0, high=200.0, step_at=102)
    vals_up = calculate_indicator(CUSUM(1.0), prices_up)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_up)
    @test any(vals_up[102:end] .== Int8(1))

    # Flat 100.0 for 101 bars, then drop to 50.0 → negative signal
    prices_down = vcat(fill(100.0, 101), fill(50.0, 99))
    vals_down = calculate_indicator(CUSUM(1.0), prices_down)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_down)
    @test any(vals_down[102:end] .== Int8(-1))
end

@testitem "CUSUM: Float32 Construction" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Float32 construction
    ind = CUSUM(1.0f0)
    @test ind isa CUSUM{Float32}
    @test ind.multiplier isa Float32
    @test ind.expected_value isa Float32

    # Float32 CUSUM with Float64 prices → MethodError (type mismatch in _calculate_cusum)
    prices64 = collect(100.0:300.0)
    @test_throws MethodError calculate_indicator(ind, prices64)

    # Float32 CUSUM with Float32 prices → works
    prices32 = Float32.(collect(100.0f0:300.0f0))
    vals = calculate_indicator(ind, prices32)
    @test eltype(vals) == Int8
    @test length(vals) == length(prices32)
end

@testitem "CUSUM: Monotone Trending Prices" tags = [:indicator, :cusum, :edge] begin
    using Backtest, Test

    # Strong uptrend → should trigger positive signals
    prices_up = [100.0 * exp(0.02 * i) for i in 1:200]
    vals_up = calculate_indicator(CUSUM(1.0), prices_up)
    @test any(vals_up .== Int8(1))

    # Strong downtrend → should trigger negative signals
    prices_down = [100.0 * exp(-0.02 * i) for i in 1:200]
    vals_down = calculate_indicator(CUSUM(1.0), prices_down)
    @test any(vals_down .== Int8(-1))

    # Verify signal direction matches trend direction
    # Uptrend: more positive signals than negative
    @test count(vals_up .== Int8(1)) >= count(vals_up .== Int8(-1))
    # Downtrend: more negative signals than positive
    @test count(vals_down .== Int8(-1)) >= count(vals_down .== Int8(1))

    # Gentle trend with high multiplier → fewer or no signals
    prices_gentle = [100.0 + 0.001 * i for i in 1:200]
    vals_gentle = calculate_indicator(CUSUM(100.0), prices_gentle)
    n_signals_gentle = count(v -> v != 0, vals_gentle)
    vals_strong = calculate_indicator(CUSUM(1.0), prices_gentle)
    n_signals_strong = count(v -> v != 0, vals_strong)
    @test n_signals_gentle <= n_signals_strong
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Robustness: Interface
# ─────────────────────────────────────────────────────────────────────────────

@testitem "CUSUM: Named Result Builder (_indicator_result)" tags = [
    :indicator, :cusum, :unit
] begin
    using Backtest, Test

    prices = collect(100.0:300.0)

    nt = Backtest._indicator_result(CUSUM(1.0), prices)
    @test nt isa NamedTuple
    @test haskey(nt, :cusum)
    @test length(keys(nt)) == 1
    @test isequal(nt.cusum, calculate_indicator(CUSUM(1.0), prices))
end

@testitem "CUSUM: Callable Interface with PriceBars" tags = [:indicator, :cusum, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result = CUSUM(1.0)(bars)
    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :cusum)
    @test result.bars === bars
    @test length(result.cusum) == 200
    @test eltype(result.cusum) == Int8
end

@testitem "CUSUM: Callable Interface with NamedTuple (chaining)" tags = [
    :indicator, :cusum, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Chain: EMA(10) then CUSUM(1.0)
    step1 = EMA(10)(bars)
    step2 = CUSUM(1.0)(step1)

    @test haskey(step2, :bars)
    @test haskey(step2, :ema_10)       # preserved from step1
    @test haskey(step2, :cusum)        # added by step2
    @test step2.bars === bars          # original data preserved
    @test isequal(step2.ema_10, step1.ema_10)  # EMA values preserved
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — Deep Analysis
# ─────────────────────────────────────────────────────────────────────────────

@testitem "CUSUM: Static Analysis (JET.jl)" tags = [:indicator, :cusum, :stability] begin
    using Backtest, Test, JET

    prices = collect(100.0:300.0)  # 201 elements, > warmup

    # Optimisation issues (type instability inside the body)
    @test_opt target_modules = (Backtest,) calculate_indicator(CUSUM(1.0), prices)

    # Method errors (calling a function that doesn't exist for those types)
    @test_call target_modules = (Backtest,) calculate_indicator(CUSUM(1.0), prices)
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5 — Allocation Budget Tests
# ─────────────────────────────────────────────────────────────────────────────
#
# CUSUM allocates a Vector{Int8} result — much smaller than EMA's Float64
# vectors. Budget = sizeof(Int8) * n + overhead.
#
# Pattern (Min-of-N):
#   1. Warmup target function
#   2. Define wrapper function (avoid Core.Box)
#   3. Measure N=3 times and take the MINIMUM
#      This filters out occasional JIT compilation or GC noise.
# ─────────────────────────────────────────────────────────────────────────────

@testitem "CUSUM: Allocation — _calculate_cusum" tags = [:indicator, :cusum, :allocation] begin
    using Backtest, Test

    prices = collect(100.0:299.0)  # 200 elements
    n = length(prices)

    # Warmup target function
    Backtest._calculate_cusum(prices, 1.0, 100, 0.0)

    # Budget: sizeof(Int8) * n + 512 bytes overhead
    # For n=200: budget = 200 + 512 = 712; double-allocation = 400 → caught
    expected_data = sizeof(Int8) * n
    budget = expected_data + 512

    # Define wrapper
    allocs_cusum(prices) = @allocated Backtest._calculate_cusum(prices, 1.0, 100, 0.0)

    # Run 3 times, take minimum to avoid compilation/GC noise
    actual = minimum([@allocated(allocs_cusum(prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0  # sanity: must allocate result vector
end

@testitem "CUSUM: Allocation — calculate_indicator" tags = [:indicator, :cusum, :allocation] begin
    using Backtest, Test

    prices = collect(100.0:299.0)  # 200 elements
    n = length(prices)
    ind = CUSUM(1.0)

    # Warmup target function
    calculate_indicator(ind, prices)

    # Budget: same as _calculate_cusum (thin wrapper)
    expected_data = sizeof(Int8) * n
    budget = expected_data + 512

    # Define wrapper
    allocs_calc(ind, prices) = @allocated calculate_indicator(ind, prices)

    # Run 3 times, take minimum
    actual = minimum([@allocated(allocs_calc(ind, prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0  # sanity: must allocate result vector
end

@testitem "CUSUM: Allocation — CUSUM functor with PriceBars" tags = [
    :indicator, :cusum, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    ind = CUSUM(1.0)

    # Warmup target function
    ind(bars)

    # Budget: sizeof(Int8) * n + 1024 bytes (NamedTuple merge overhead)
    expected_data = sizeof(Int8) * 200
    budget = expected_data + 1024

    # Define wrapper
    allocs_functor(ind, bars) = @allocated ind(bars)

    # Run 3 times, take minimum
    actual = minimum([@allocated(allocs_functor(ind, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0  # sanity: must allocate result
end