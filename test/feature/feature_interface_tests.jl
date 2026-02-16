# ── Feature Interface Tests ──
#
# These test the shared AbstractFeature callable interface defined in
# src/feature/feature.jl. Per-type behaviour is covered in ema_tests.jl
# and cusum_tests.jl — this file covers cross-feature concerns:
# composition, data preservation, and pipeline operator integration.

# ── Phase 2: Core Correctness ──

@testitem "Feature Interface: Cross-Feature Composition" tags = [:feature, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    step1 = EMA(10, 50)(bars)
    step2 = CUSUM(1.0)(step1)

    @test step2 isa NamedTuple
    @test haskey(step2, :bars)
    @test haskey(step2, :ema_10)
    @test haskey(step2, :ema_50)
    @test haskey(step2, :cusum)
    @test length(keys(step2)) == 4
end

@testitem "Feature Interface: Data Preservation Through Chain" tags = [:feature, :property] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    step1 = EMA(10)(bars)
    step2 = CUSUM(1.0)(step1)
    step3 = EMA(20)(step2)

    # PriceBars reference identity survives the entire chain
    @test step3.bars === bars

    # Earlier feature results are preserved exactly
    @test isequal(step3.ema_10, step1.ema_10)
    @test isequal(step3.cusum, step2.cusum)

    # Feature values match independent computation
    independent_ema20 = calculate_feature(EMA(20), bars.close)
    @test isequal(step3.ema_20, independent_ema20)
end

@testitem "Feature Interface: Pipeline Operator Composition" tags = [:feature, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    composed = EMA(10, 50) >> CUSUM(1.0)
    result = composed(bars)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :cusum)

    # Composed result matches sequential calls
    sequential = CUSUM(1.0)(EMA(10, 50)(bars))
    @test isequal(result.ema_10, sequential.ema_10)
    @test isequal(result.ema_50, sequential.ema_50)
    @test isequal(result.cusum, sequential.cusum)
end

@testitem "Feature Interface: Job Creation and Execution" tags = [:feature, :unit] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    job = bars >> EMA(10, 50) >> CUSUM(1.0)
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :cusum)
    @test result.bars === bars
end

# ── Phase 2: Type Stability ──

@testitem "Feature Interface: Type Stability of Callable" tags = [:feature, :stability] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    @test @inferred(EMA(10)(bars)) isa NamedTuple
    @test @inferred(CUSUM(1.0)(bars)) isa NamedTuple

    step1 = EMA(10)(bars)
    @test @inferred(CUSUM(1.0)(step1)) isa NamedTuple
    @test @inferred(EMA(20)(step1)) isa NamedTuple
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Feature Interface: Output Types Match Input Precision" tags = [
    :feature, :property
] setup = [TestData] begin
    using Backtest, Test, Dates

    # Float64 path
    bars64 = TestData.make_pricebars(; n=200)
    result64 = EMA(10)(bars64)
    @test eltype(result64.ema_10) == Float64

    # Float32 path
    n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    p32 = Float32.(100.0 .+ collect(1:n) .* 0.05f0)
    bars32 = PriceBars(p32, p32, p32, p32, p32, ts, TimeBar())
    result32 = EMA(10)(bars32)
    @test eltype(result32.ema_10) == Float32
end

@testitem "Feature Interface: Ordering Independence" tags = [:feature, :property] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # EMA then CUSUM vs CUSUM then EMA — feature values are independent
    path_a = CUSUM(1.0)(EMA(10)(bars))
    path_b = EMA(10)(CUSUM(1.0)(bars))

    @test isequal(path_a.ema_10, path_b.ema_10)
    @test isequal(path_a.cusum, path_b.cusum)
end

@testitem "Feature Interface: Many Features Composed" tags = [:feature, :edge] setup = [
    TestData
] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)

    # Five features chained — stress test for NamedTuple merge depth
    result = (EMA(5) >> EMA(10) >> EMA(20) >> EMA(50) >> CUSUM(1.0))(bars)

    @test haskey(result, :ema_5)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_20)
    @test haskey(result, :ema_50)
    @test haskey(result, :cusum)
    @test result.bars === bars
end

# ── Phase 5: Allocation Budget Tests ──
#
# Per-type functor allocations are tested in ema_tests.jl and
# cusum_tests.jl. These tests cover the cross-feature chaining path
# where the input NamedTuple is wider than the single-feature case.
# Budget = new feature's result data + 1024 bytes merge overhead.

@testitem "Feature Interface: Allocation — CUSUM functor after EMA" tags = [
    :feature, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    ema_result = EMA(10, 50)(bars)
    feat = CUSUM(1.0)

    feat(ema_result)

    # Budget: CUSUM result (Int8 × n) + 1024 bytes merge overhead
    expected_data = sizeof(Int8) * 200
    budget = expected_data + 1024

    allocs_chain(feat, d) = @allocated feat(d)

    actual = minimum([@allocated(allocs_chain(feat, ema_result)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Feature Interface: Allocation — EMA functor after CUSUM" tags = [
    :feature, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    cusum_result = CUSUM(1.0)(bars)
    feat = EMA(20)

    feat(cusum_result)

    # Budget: EMA result (Float64 × n) + 1024 bytes merge overhead
    expected_data = sizeof(Float64) * 200
    budget = expected_data + 1024

    allocs_chain(feat, d) = @allocated feat(d)

    actual = minimum([@allocated(allocs_chain(feat, cusum_result)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Feature Interface: Allocation — EMA multi-period functor after EMA" tags = [
    :feature, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    step1 = EMA(10)(bars)
    feat = EMA(5, 20, 50)

    feat(step1)

    # Budget: EMA matrix (Float64 × n × 3) + 1024 bytes merge overhead
    expected_data = sizeof(Float64) * 200 * 3
    budget = expected_data + 1024

    allocs_chain(feat, d) = @allocated feat(d)

    actual = minimum([@allocated(allocs_chain(feat, step1)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end