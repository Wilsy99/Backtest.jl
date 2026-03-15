# ── Phase 2: Core Correctness ──

@testitem "CUSUM: Hand-Calculated Reference" tags = [:feature, :cusum, :reference] begin
    using Backtest, Test

    # Flat warmup → ema_sq_mean = 0 → threshold = sqrt(1e-16) ≈ 1e-8
    # Jump at i=102: log(200/100) = 0.693 → s_pos = 0.693 > 1e-8 → signal +1
    prices_up = vcat(fill(100.0, 101), [200.0])
    vals_up = compute(CUSUM(1.0), prices_up)

    @test length(vals_up) == 102
    @test eltype(vals_up) == Int8
    @test all(vals_up[1:101] .== Int8(0))
    @test vals_up[102] == Int8(1)

    # Drop at i=102: log(50/100) = -0.693 → s_neg = -0.693 < -1e-8 → signal -1
    prices_down = vcat(fill(100.0, 101), [50.0])
    vals_down = compute(CUSUM(1.0), prices_down)

    @test vals_down[102] == Int8(-1)

    # Multi-signal: alternating jumps produce alternating signals
    # i=102: +0.693 > 1e-8 → +1
    # i=103: -0.693 < -threshold → -1
    # i=104: +0.693 > threshold → +1
    prices_multi = vcat(fill(100.0, 101), [200.0, 100.0, 200.0])
    vals_multi = compute(CUSUM(1.0), prices_multi)

    @test vals_multi[102] == Int8(1)
    @test vals_multi[103] == Int8(-1)
    @test vals_multi[104] == Int8(1)
end

@testitem "CUSUM: Hand-Calculated Reference (non-default span)" tags = [
    :feature, :cusum, :reference
] begin
    using Backtest, Test

    # span=10 → warmup_idx=11: first 11 bars are warmup, signals from bar 12.
    # Flat warmup → ema_sq_mean = 0 → threshold = sqrt(1e-16) ≈ 1e-8
    # Jump at i=12: log(200/100) = 0.693 → s_pos = 0.693 > 1e-8 → signal +1
    prices_up = vcat(fill(100.0, 11), [200.0])
    vals_up = compute(CUSUM(1.0; span=10), prices_up)

    @test length(vals_up) == 12
    @test eltype(vals_up) == Int8
    @test all(vals_up[1:11] .== Int8(0))
    @test vals_up[12] == Int8(1)

    # Drop at i=12: log(50/100) = -0.693 → s_neg = -0.693 < -1e-8 → signal -1
    prices_down = vcat(fill(100.0, 11), [50.0])
    vals_down = compute(CUSUM(1.0; span=10), prices_down)

    @test vals_down[12] == Int8(-1)
end

@testitem "CUSUM: Output Domain Property" tags = [:feature, :cusum, :property] setup = [
    TestData
] begin
    using Backtest, Test

    for prices in [
        TestData.make_pricebars(; n=200).close,
        TestData.make_trending_prices(:up; n=200, start=50.0, step=0.5),
        [100.0 + 10.0 * sin(2π * i / 20) for i in 1:200],
    ]
        vals = compute(CUSUM(1.0), prices)

        @test length(vals) == length(prices)
        @test eltype(vals) == Int8
        @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals)
    end
end

@testitem "CUSUM: Type Stability" tags = [:feature, :cusum, :stability] begin
    using Backtest, Test

    prices64 = collect(100.0:300.0)

    @test @inferred(compute(CUSUM(1.0), prices64)) isa Vector{Int8}

    prices32 = Float32.(collect(100.0f0:300.0f0))
    @test @inferred(compute(CUSUM(1.0f0), prices32)) isa Vector{Int8}

    @test @inferred(Backtest._feature_result(CUSUM(1.0), prices64)) isa Vector{Int8}
end

@testitem "CUSUM: Mathematical Properties" tags = [:feature, :cusum, :property] setup = [
    TestData
] begin
    using Backtest, Test

    prices = TestData.make_pricebars(; n=200).close

    vals = compute(CUSUM(1.0), prices)
    @test all(vals[1:101] .== Int8(0))

    flat = TestData.make_flat_prices(; price=100.0, n=200)
    vals_flat = compute(CUSUM(1.0), flat)
    @test all(vals_flat .== Int8(0))

    # Higher multiplier → fewer or equal signals (wider threshold)
    vals_low = compute(CUSUM(1.0), prices)
    vals_high = compute(CUSUM(5.0), prices)
    @test count(!=(0), vals_high) <= count(!=(0), vals_low)

    spike_up = vcat(fill(100.0, 101), [200.0])
    @test compute(CUSUM(1.0), spike_up)[102] == Int8(1)

    spike_down = vcat(fill(100.0, 101), [50.0])
    @test compute(CUSUM(1.0), spike_down)[102] == Int8(-1)

    spiky = vcat(fill(100.0, 101), [200.0, 100.0, 200.0, 100.0, 200.0])
    vals_spiky = compute(CUSUM(1.0), spiky)
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spiky)
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "CUSUM: Constructor Validation" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    @test_throws ArgumentError CUSUM(0.0)
    @test_throws ArgumentError CUSUM(-1.0)
    @test_throws ArgumentError CUSUM(1.0; span=0)
    @test_throws ArgumentError CUSUM(1.0; span=-1)

    @test CUSUM(1.0) isa CUSUM
    @test CUSUM(0.5; span=50) isa CUSUM
    @test CUSUM(1.0; expected_value=0.01) isa CUSUM
    @test CUSUM(3.0; span=200, expected_value=0.005) isa CUSUM
end

@testitem "CUSUM: Data Shorter Than Warmup" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices_50 = fill(100.0, 50)
    prices_101 = fill(100.0, 101)
    prices_102 = fill(100.0, 102)

    vals_50 = @test_logs (:warn,) compute(CUSUM(1.0), prices_50)
    @test length(vals_50) == 50
    @test all(vals_50 .== Int8(0))

    # warmup_idx = span + 1 = 101 for default span=100; n=101 is at the boundary so still warns
    vals_101 = @test_logs (:warn,) compute(CUSUM(1.0), prices_101)
    @test length(vals_101) == 101
    @test all(vals_101 .== Int8(0))

    vals_102 = compute(CUSUM(1.0), prices_102)
    @test length(vals_102) == 102
    @test all(vals_102[1:101] .== Int8(0))
end

@testitem "CUSUM: Negative Prices" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices_neg_warmup = fill(100.0, 200)
    prices_neg_warmup[50] = -1.0
    @test_throws DomainError compute(CUSUM(1.0), prices_neg_warmup)

    prices_neg_post = fill(100.0, 200)
    prices_neg_post[150] = -1.0
    @test_throws DomainError compute(CUSUM(1.0), prices_neg_post)

    # log(0.0) = -Inf rather than throwing; downstream Inf threshold blocks signals
    prices_zero = fill(100.0, 200)
    prices_zero[50] = 0.0
    vals = compute(CUSUM(1.0), prices_zero)
    @test length(vals) == 200
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals)
end

@testitem "CUSUM: Very Large Prices" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices_flat = fill(50_000.0, 200)
    vals_flat = compute(CUSUM(1.0), prices_flat)

    @test all(vals_flat .== Int8(0))
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_flat)

    prices_spike = vcat(fill(50_000.0, 101), [100_000.0], fill(50_000.0, 98))
    vals_spike = compute(CUSUM(1.0), prices_spike)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spike)
    @test any(vals_spike[102:end] .== Int8(1))
end

@testitem "CUSUM: Very Small Prices" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices_flat = fill(0.001, 200)
    vals_flat = compute(CUSUM(1.0), prices_flat)

    @test all(vals_flat .== Int8(0))
    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_flat)

    prices_spike = vcat(fill(0.001, 101), [0.002], fill(0.001, 98))
    vals_spike = compute(CUSUM(1.0), prices_spike)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_spike)
end

@testitem "CUSUM: Flat Prices" tags = [:feature, :cusum, :edge] setup = [TestData] begin
    using Backtest, Test

    flat = TestData.make_flat_prices(; price=100.0, n=200)
    vals = compute(CUSUM(1.0), flat)

    @test all(vals .== Int8(0))
end

@testitem "CUSUM: Step Function" tags = [:feature, :cusum, :edge] setup = [TestData] begin
    using Backtest, Test

    prices_up = TestData.make_step_prices(; n=200, low=100.0, high=200.0, step_at=102)
    vals_up = compute(CUSUM(1.0), prices_up)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_up)
    @test any(vals_up[102:end] .== Int8(1))

    prices_down = vcat(fill(100.0, 101), fill(50.0, 99))
    vals_down = compute(CUSUM(1.0), prices_down)

    @test all(v -> v ∈ (Int8(-1), Int8(0), Int8(1)), vals_down)
    @test any(vals_down[102:end] .== Int8(-1))
end

@testitem "CUSUM: Float32 Construction" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    feat = CUSUM(1.0f0)
    @test feat isa CUSUM{Float32}
    @test feat.multiplier isa Float32
    @test feat.expected_value isa Float32

    # Float32 CUSUM with Float64 prices is a type mismatch in _calculate_cusum
    prices64 = collect(100.0:300.0)
    @test_throws MethodError compute(feat, prices64)

    prices32 = Float32.(collect(100.0f0:300.0f0))
    vals = compute(feat, prices32)
    @test eltype(vals) == Int8
    @test length(vals) == length(prices32)
end

@testitem "CUSUM: Monotone Trending Prices" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices_up = [100.0 * exp(0.02 * i) for i in 1:200]
    vals_up = compute(CUSUM(1.0), prices_up)
    @test any(vals_up .== Int8(1))

    prices_down = [100.0 * exp(-0.02 * i) for i in 1:200]
    vals_down = compute(CUSUM(1.0), prices_down)
    @test any(vals_down .== Int8(-1))

    @test count(vals_up .== Int8(1)) >= count(vals_up .== Int8(-1))
    @test count(vals_down .== Int8(-1)) >= count(vals_down .== Int8(1))

    # Gentle trend with high multiplier → fewer signals than low multiplier
    prices_gentle = [100.0 + 0.001 * i for i in 1:200]
    vals_gentle = compute(CUSUM(100.0), prices_gentle)
    vals_strong = compute(CUSUM(1.0), prices_gentle)
    @test count(!=(0), vals_gentle) <= count(!=(0), vals_strong)
end

# ── Phase 3: Robustness — Interface ──

@testitem "CUSUM: Named Result Builder (_feature_result)" tags = [:feature, :cusum, :unit] begin
    using Backtest, Test

    prices = collect(100.0:300.0)

    result = Backtest._feature_result(CUSUM(1.0), prices)
    @test result isa Vector{Int8}
    @test isequal(result, compute(CUSUM(1.0), prices))
end

@testitem "CUSUM: Callable Interface with PriceBars" tags = [:feature, :cusum, :unit] setup = [
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
    :feature, :cusum, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    step1 = EMA(10)(bars)
    step2 = CUSUM(1.0)(step1)

    @test haskey(step2, :bars)
    @test haskey(step2, :ema_10)
    @test haskey(step2, :cusum)
    @test step2.bars === bars
    @test isequal(step2.ema_10, step1.ema_10)
end

# ── Phase 4: Deep Analysis ──

@testitem "CUSUM: Static Analysis (JET.jl)" tags = [:feature, :cusum, :stability] begin
    using Backtest, Test, JET

    prices = collect(100.0:300.0)

    @test_opt target_modules = (Backtest,) compute(CUSUM(1.0), prices)
    @test_call target_modules = (Backtest,) compute(CUSUM(1.0), prices)
end

# ── Phase 5: Allocation Budget Tests ──
#
# CUSUM allocates a Vector{Int8} result — much smaller than EMA's
# Float64 vectors. See TESTING.md §6b for the Min-of-N pattern and
# overhead constant rationale.

@testitem "CUSUM: Allocation — _calculate_cusum" tags = [:feature, :cusum, :allocation] begin
    using Backtest, Test

    prices = collect(100.0:299.0)
    n = length(prices)

    Backtest._calculate_cusum(prices, 1.0, 100, 0.0)

    expected_data = sizeof(Int8) * n
    budget = expected_data + 512

    allocs_cusum(prices) = @allocated Backtest._calculate_cusum(prices, 1.0, 100, 0.0)

    actual = minimum([@allocated(allocs_cusum(prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "CUSUM: Allocation — compute" tags = [:feature, :cusum, :allocation] begin
    using Backtest, Test

    prices = collect(100.0:299.0)
    n = length(prices)
    feat = CUSUM(1.0)

    compute(feat, prices)

    expected_data = sizeof(Int8) * n
    budget = expected_data + 512

    allocs_calc(feat, prices) = @allocated compute(feat, prices)

    actual = minimum([@allocated(allocs_calc(feat, prices)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "CUSUM: Allocation — CUSUM functor with PriceBars" tags = [
    :feature, :cusum, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    feat = CUSUM(1.0)

    feat(bars)

    expected_data = sizeof(Int8) * 200
    budget = expected_data + 1024

    allocs_functor(feat, bars) = @allocated feat(bars)

    actual = minimum([@allocated(allocs_functor(feat, bars)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

# ── span parameter behaviour ──

@testitem "CUSUM: span and expected_value are stored correctly" tags = [
    :feature, :cusum, :unit
] begin
    using Backtest, Test

    @test CUSUM(1.0).span == 100
    @test CUSUM(1.0; span=50).span == 50
    @test CUSUM(0.5; span=200).span == 200
    @test CUSUM(1.0; expected_value=0.01).expected_value ≈ 0.01
    @test CUSUM(3.0; span=200, expected_value=0.005).expected_value ≈ 0.005
end

@testitem "CUSUM: span determines warmup boundary" tags = [:feature, :cusum, :unit] begin
    using Backtest, Test

    # warmup_idx = span + 1, so the warmup length scales with span.
    # span=50 → warmup_idx=51: n=51 warns, n=52 does not
    @test_logs (:warn,) compute(CUSUM(1.0; span=50), fill(100.0, 51))
    vals_52 = compute(CUSUM(1.0; span=50), fill(100.0, 52))
    @test length(vals_52) == 52
    @test all(vals_52[1:51] .== Int8(0))

    # span=10 → warmup_idx=11: n=11 warns, n=12 does not
    @test_logs (:warn,) compute(CUSUM(1.0; span=10), fill(100.0, 11))
    vals_12 = compute(CUSUM(1.0; span=10), fill(100.0, 12))
    @test length(vals_12) == 12
    @test all(vals_12[1:11] .== Int8(0))

    # span=200 → warmup_idx=201: n=201 warns, n=202 does not
    @test_logs (:warn,) compute(CUSUM(1.0; span=200), fill(100.0, 201))
    vals_202 = compute(CUSUM(1.0; span=200), fill(100.0, 202))
    @test length(vals_202) == 202
    @test all(vals_202[1:201] .== Int8(0))
end

# ── field keyword ──

@testitem "CUSUM: field keyword defaults to :close" tags = [:feature, :cusum, :unit] begin
    using Backtest, Test

    @test CUSUM(1.0).field === :close
    @test CUSUM(0.5; span=50).field === :close
end

@testitem "CUSUM: field keyword selects target series" tags = [:feature, :cusum, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    result_close = CUSUM(1.0)(bars)
    result_high = CUSUM(1.0; field=:high)(bars)

    # High-based CUSUM should match computing CUSUM directly on high prices
    expected = compute(CUSUM(1.0), bars.high)
    @test isequal(result_high.cusum, expected)
end

# ── compute! (in-place) ──

@testitem "CUSUM: compute! matches allocating version" tags = [:feature, :cusum, :unit] begin
    using Backtest, Test

    prices = vcat(fill(100.0, 101), [200.0, 100.0, 200.0])
    dest = Vector{Int8}(undef, length(prices))

    result = compute!(dest, CUSUM(1.0), prices)

    @test result === dest
    @test isequal(dest, compute(CUSUM(1.0), prices))
end

@testitem "CUSUM: compute! with short data" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    # Data shorter than warmup — should return zeros without error
    prices = fill(100.0, 50)
    dest = Vector{Int8}(undef, 50)

    result = compute!(dest, CUSUM(1.0), prices)

    @test result === dest
    @test all(dest .== Int8(0))
end

@testitem "CUSUM: compute! dimension mismatch" tags = [:feature, :cusum, :edge] begin
    using Backtest, Test

    prices = fill(100.0, 200)
    dest_short = Vector{Int8}(undef, 100)

    @test_throws DimensionMismatch compute!(dest_short, CUSUM(1.0), prices)
end

@testitem "CUSUM: compute! zeroes dest before computing" tags = [:feature, :cusum, :unit] begin
    using Backtest, Test

    prices = vcat(fill(100.0, 101), [200.0])
    dest = fill(Int8(99), length(prices))

    compute!(dest, CUSUM(1.0), prices)

    # Warmup region must be zero (was 99 before the call)
    @test all(dest[1:101] .== Int8(0))
    @test dest[102] == Int8(1)
end