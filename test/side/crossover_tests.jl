# ── Phase 2: Core Correctness ──

@testitem "Crossover: Hand-Calculated Reference (LongShort, wait_for_cross=true)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    # fast crosses above slow at index 4, then below at index 7
    fast = Float64[1, 2, 3, 5, 6, 7, 2, 1, 0]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(Crossover(; wait_for_cross=true), fast, slow)

    @test length(sides) == 9
    # Indices 1-3: fast <= slow, no cross yet → 0
    @test all(sides[1:3] .== Int8(0))
    # Index 4: first cross (fast > slow) → signals start
    @test sides[4] == Int8(1)
    @test sides[5] == Int8(1)
    @test sides[6] == Int8(1)
    # Index 7: fast < slow → short
    @test sides[7] == Int8(-1)
    @test sides[8] == Int8(-1)
    @test sides[9] == Int8(-1)
end

@testitem "Crossover: Hand-Calculated Reference (LongShort, wait_for_cross=false)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    fast = Float64[1, 2, 3, 5, 6, 7, 2, 1, 0]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(
        Crossover(; wait_for_cross=false), fast, slow
    )

    @test length(sides) == 9
    # No waiting — signals start immediately from first valid index
    @test sides[1] == Int8(-1)  # fast < slow
    @test sides[2] == Int8(-1)
    @test sides[3] == Int8(0)   # fast == slow
    @test sides[4] == Int8(1)   # fast > slow
    @test sides[5] == Int8(1)
    @test sides[6] == Int8(1)
    @test sides[7] == Int8(-1)  # fast < slow
    @test sides[8] == Int8(-1)
    @test sides[9] == Int8(-1)
end

@testitem "Crossover: Hand-Calculated Reference (LongOnly)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    fast = Float64[1, 2, 5, 6, 2, 1, 5, 6]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(
        Crossover(; wait_for_cross=true, direction=LongOnly()), fast, slow
    )

    @test length(sides) == 8
    # Indices 1-2: fast <= slow, waiting for cross
    @test all(sides[1:2] .== Int8(0))
    # Index 3: first upward cross → long
    @test sides[3] == Int8(1)
    @test sides[4] == Int8(1)
    # Index 5-6: fast < slow → neutral (LongOnly never emits -1)
    @test sides[5] == Int8(0)
    @test sides[6] == Int8(0)
    # Index 7-8: fast > slow again → long
    @test sides[7] == Int8(1)
    @test sides[8] == Int8(1)
end

@testitem "Crossover: Hand-Calculated Reference (ShortOnly)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    fast = Float64[5, 4, 1, 0, 4, 5, 1, 0]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(
        Crossover(; wait_for_cross=true, direction=ShortOnly()), fast, slow
    )

    @test length(sides) == 8
    # Indices 1-2: fast >= slow, waiting for downward cross
    @test all(sides[1:2] .== Int8(0))
    # Index 3: first downward cross → short
    @test sides[3] == Int8(-1)
    @test sides[4] == Int8(-1)
    # Index 5-6: fast > slow → neutral (ShortOnly never emits +1)
    @test sides[5] == Int8(0)
    @test sides[6] == Int8(0)
    # Index 7-8: fast < slow again → short
    @test sides[7] == Int8(-1)
    @test sides[8] == Int8(-1)
end

@testitem "Crossover: Type Stability" tags = [:side, :crossover, :stability] begin
    using Backtest, Test

    fast64 = Float64[1, 2, 3, 4, 5]
    slow64 = Float64[5, 4, 3, 2, 1]
    fast32 = Float32[1, 2, 3, 4, 5]
    slow32 = Float32[5, 4, 3, 2, 1]

    cross_ls = Crossover()
    cross_lo = Crossover(; direction=LongOnly())
    cross_so = Crossover(; direction=ShortOnly())

    @test @inferred(calculate_side(cross_ls, fast64, slow64)) isa Vector{Int8}
    @test @inferred(calculate_side(cross_ls, fast32, slow32)) isa Vector{Int8}
    @test @inferred(calculate_side(cross_lo, fast64, slow64)) isa Vector{Int8}
    @test @inferred(calculate_side(cross_so, fast64, slow64)) isa Vector{Int8}

    # wait_for_cross=false
    cross_nw = Crossover(; wait_for_cross=false)
    @test @inferred(calculate_side(cross_nw, fast64, slow64)) isa Vector{Int8}
end

@testitem "Crossover: Mathematical Properties" tags = [
    :side, :crossover, :property
] setup = [TestData] begin
    using Backtest, Test

    prices_up = TestData.make_trending_prices(:up; n=200, start=50.0, step=0.5)
    prices_down = TestData.make_trending_prices(:down; n=200, start=200.0, step=0.3)

    # Boundedness: all outputs must be in {-1, 0, 1}
    sides = calculate_side(Crossover(), prices_up, prices_down)
    @test all(s -> s ∈ Int8.([-1, 0, 1]), sides)

    # Monotone diverging series: fast always above slow after some point
    # → should produce all +1 after first cross
    fast_diverge = Float64[i * 1.0 for i in 1:100]
    slow_diverge = Float64[i * 0.5 for i in 1:100]
    sides_div = calculate_side(Crossover(; wait_for_cross=false), fast_diverge, slow_diverge)
    # fast[1]=1 > slow[1]=0.5, so always long from start
    @test all(sides_div .== Int8(1))

    # LongOnly never produces -1
    sides_lo = calculate_side(
        Crossover(; direction=LongOnly(), wait_for_cross=false),
        prices_up, prices_down,
    )
    @test all(s -> s ∈ Int8.([0, 1]), sides_lo)

    # ShortOnly never produces +1
    sides_so = calculate_side(
        Crossover(; direction=ShortOnly(), wait_for_cross=false),
        prices_up, prices_down,
    )
    @test all(s -> s ∈ Int8.([-1, 0]), sides_so)

    # Equal series → all zeros
    flat = TestData.make_flat_prices(; price=100.0, n=100)
    sides_flat = calculate_side(Crossover(; wait_for_cross=false), flat, flat)
    @test all(sides_flat .== Int8(0))
end

# ── Phase 3: Robustness — Edge Cases ──

@testitem "Crossover: Edge Case — All NaN Slow Series" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    fast = Float64[1, 2, 3, 4, 5]
    slow = fill(NaN, 5)

    sides = calculate_side(Crossover(), fast, slow)
    @test length(sides) == 5
    @test all(sides .== Int8(0))
end

@testitem "Crossover: Edge Case — NaN Warmup in Slow Series" tags = [
    :side, :crossover, :edge
] begin
    using Backtest, Test

    # Slow series has NaN warmup (like EMA output)
    fast = Float64[1, 2, 3, 5, 6, 7, 2, 1]
    slow = Float64[NaN, NaN, NaN, 3, 3, 3, 3, 3]

    sides = calculate_side(Crossover(; wait_for_cross=false), fast, slow)

    # First 3 indices: slow is NaN → 0
    @test all(sides[1:3] .== Int8(0))
    # Index 4: fast(5) > slow(3) → 1
    @test sides[4] == Int8(1)
end

@testitem "Crossover: Edge Case — Single Element" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    fast = Float64[5.0]
    slow = Float64[3.0]

    sides = calculate_side(Crossover(; wait_for_cross=true), fast, slow)
    @test length(sides) == 1
    @test sides[1] == Int8(0)  # No cross can occur with 1 element

    sides_nw = calculate_side(Crossover(; wait_for_cross=false), fast, slow)
    @test length(sides_nw) == 1
    @test sides_nw[1] == Int8(1)  # fast > slow → long
end

@testitem "Crossover: Edge Case — Two Elements" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    # Cross happens at index 2
    fast = Float64[1.0, 5.0]
    slow = Float64[3.0, 3.0]

    sides = calculate_side(Crossover(; wait_for_cross=true), fast, slow)
    @test length(sides) == 2
    @test sides[1] == Int8(0)  # Before cross
    @test sides[2] == Int8(1)  # Cross detected at index 2
end

@testitem "Crossover: Edge Case — Flat Prices" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    flat = fill(100.0, 200)
    sides = calculate_side(Crossover(; wait_for_cross=false), flat, flat)
    @test all(sides .== Int8(0))

    sides_wait = calculate_side(Crossover(; wait_for_cross=true), flat, flat)
    @test all(sides_wait .== Int8(0))
end

@testitem "Crossover: Edge Case — No Crossover Found" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    # fast always above slow — no cross occurs when wait_for_cross=true
    # and fast starts above slow
    fast = Float64[10, 11, 12, 13, 14]
    slow = Float64[1, 2, 3, 4, 5]

    sides = calculate_side(Crossover(; wait_for_cross=true), fast, slow)
    # LongShort: fast starts above slow at index 1, no change in relative
    # position → no crossover detected → all zeros
    @test all(sides .== Int8(0))
end

@testitem "Crossover: Edge Case — Very Large Prices" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    fast = Float64[50_000.0 + i for i in 1:100]
    slow = fill(50_000.0, 100)

    sides = calculate_side(Crossover(; wait_for_cross=false), fast, slow)
    @test all(isfinite.(Float64.(sides)))
    @test all(sides .== Int8(1))  # fast always above slow
end

@testitem "Crossover: Edge Case — Very Small Prices" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    fast = Float64[0.001 + 0.0001 * i for i in 1:100]
    slow = fill(0.001, 100)

    sides = calculate_side(Crossover(; wait_for_cross=false), fast, slow)
    @test all(sides .== Int8(1))
end

@testitem "Crossover: Float32 Type Preservation" tags = [:side, :crossover, :edge] begin
    using Backtest, Test

    fast32 = Float32[1, 2, 3, 5, 6]
    slow32 = Float32[3, 3, 3, 3, 3]

    sides = calculate_side(Crossover(), fast32, slow32)
    @test eltype(sides) == Int8
    @test length(sides) == 5
end

@testitem "Crossover: Edge Case — Alternating Crossovers" tags = [
    :side, :crossover, :edge
] begin
    using Backtest, Test

    # Fast oscillates around slow
    fast = Float64[1, 5, 1, 5, 1, 5, 1, 5]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(Crossover(; wait_for_cross=false), fast, slow)

    @test sides[1] == Int8(-1)
    @test sides[2] == Int8(1)
    @test sides[3] == Int8(-1)
    @test sides[4] == Int8(1)
    @test sides[5] == Int8(-1)
    @test sides[6] == Int8(1)
    @test sides[7] == Int8(-1)
    @test sides[8] == Int8(1)
end

@testitem "Crossover: Edge Case — Fast Equals Slow Then Diverges" tags = [
    :side, :crossover, :edge
] begin
    using Backtest, Test

    fast = Float64[3, 3, 3, 3, 5, 6, 7]
    slow = Float64[3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(Crossover(; wait_for_cross=true), fast, slow)

    # Equal → 0, then cross up at index 5
    @test all(sides[1:4] .== Int8(0))
    @test sides[5] == Int8(1)
    @test sides[6] == Int8(1)
    @test sides[7] == Int8(1)
end

# ── Phase 3: Robustness — Constructor & Interface ──

@testitem "Crossover: Constructor Variants" tags = [:side, :crossover, :unit] begin
    using Backtest, Test

    # Default constructor (no symbols)
    c1 = Crossover()
    @test c1 isa AbstractSide

    # With symbols
    c2 = Crossover(:ema_10, :ema_50)
    @test c2 isa AbstractSide

    # With direction
    c3 = Crossover(:ema_10, :ema_50; direction=LongOnly())
    @test c3 isa AbstractSide

    c4 = Crossover(:ema_10, :ema_50; direction=ShortOnly())
    @test c4 isa AbstractSide

    # With wait_for_cross
    c5 = Crossover(:ema_10, :ema_50; wait_for_cross=false)
    @test c5 isa AbstractSide

    # All options
    c6 = Crossover(:ema_10, :ema_50; wait_for_cross=false, direction=LongOnly())
    @test c6 isa AbstractSide
end

@testitem "Crossover: Named Result Builder (_side_result)" tags = [
    :side, :crossover, :unit
] begin
    using Backtest, Test

    fast = Float64[1, 2, 5, 6, 7]
    slow = Float64[3, 3, 3, 3, 3]

    d = (; ema_10=fast, ema_50=slow)
    cross = Crossover(:ema_10, :ema_50; wait_for_cross=false)

    result = Backtest._side_result(cross, d)
    @test result isa NamedTuple
    @test haskey(result, :side)
    @test length(result.side) == 5
    @test result.side == calculate_side(cross, fast, slow)
end

@testitem "Crossover: Callable Interface with NamedTuple" tags = [
    :side, :crossover, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    ema_data = EMA(10, 50)(bars)

    cross = Crossover(:ema_10, :ema_50)
    result = cross(ema_data)

    @test result isa NamedTuple
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :side)
    @test length(result.side) == 100
    @test result.bars === bars
    @test all(s -> s ∈ Int8.([-1, 0, 1]), result.side)
end

@testitem "Crossover: Pipeline Composition via >>" tags = [
    :side, :crossover, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)

    job = bars >> EMA(10, 50) >> Crossover(:ema_10, :ema_50)
    result = job()

    @test result isa NamedTuple
    @test haskey(result, :side)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :bars)
    @test length(result.side) == 100
end

# ── Phase 3: Robustness — Internal Functions ──

@testitem "Crossover: _find_first_cross (LongShort)" tags = [
    :side, :crossover, :unit
] begin
    using Backtest, Test

    # Cross from below to above at index 3
    fast = Float64[1, 2, 5, 6]
    slow = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast, slow, 1, LongShort()) == 3

    # No cross: fast always above slow
    fast2 = Float64[5, 6, 7, 8]
    slow2 = Float64[1, 2, 3, 4]
    @test Backtest._find_first_cross(fast2, slow2, 1, LongShort()) == -1

    # Cross at index 2
    fast3 = Float64[5, 1]
    slow3 = Float64[3, 3]
    @test Backtest._find_first_cross(fast3, slow3, 1, LongShort()) == 2
end

@testitem "Crossover: _find_first_cross (LongOnly)" tags = [
    :side, :crossover, :unit
] begin
    using Backtest, Test

    # Fast starts below, crosses above at index 3
    fast = Float64[1, 2, 5, 6]
    slow = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast, slow, 1, LongOnly()) == 3

    # Fast starts above — needs to go below first, then cross up
    fast2 = Float64[5, 6, 1, 5]
    slow2 = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast2, slow2, 1, LongOnly()) == 4

    # Never crosses up
    fast3 = Float64[1, 1, 1, 1]
    slow3 = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast3, slow3, 1, LongOnly()) == -1
end

@testitem "Crossover: _find_first_cross (ShortOnly)" tags = [
    :side, :crossover, :unit
] begin
    using Backtest, Test

    # Fast starts above, crosses below at index 3
    fast = Float64[5, 4, 1, 0]
    slow = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast, slow, 1, ShortOnly()) == 3

    # Fast starts below — needs to go above first, then cross down
    fast2 = Float64[1, 0, 5, 1]
    slow2 = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast2, slow2, 1, ShortOnly()) == 4

    # Never crosses down
    fast3 = Float64[5, 5, 5, 5]
    slow3 = Float64[3, 3, 3, 3]
    @test Backtest._find_first_cross(fast3, slow3, 1, ShortOnly()) == -1
end

@testitem "Crossover: _get_condition_func correctness" tags = [
    :side, :crossover, :unit
] begin
    using Backtest, Test

    fast = Float64[1, 3, 5]
    slow = Float64[3, 3, 3]

    # LongShort
    cond_ls = Backtest._get_condition_func(fast, slow, LongShort())
    @test cond_ls(1) == Int8(-1)  # 1 < 3
    @test cond_ls(2) == Int8(0)   # 3 == 3
    @test cond_ls(3) == Int8(1)   # 5 > 3

    # LongOnly
    cond_lo = Backtest._get_condition_func(fast, slow, LongOnly())
    @test cond_lo(1) == Int8(0)   # 1 < 3 → neutral
    @test cond_lo(2) == Int8(0)   # 3 == 3 → neutral
    @test cond_lo(3) == Int8(1)   # 5 > 3 → long

    # ShortOnly
    cond_so = Backtest._get_condition_func(fast, slow, ShortOnly())
    @test cond_so(1) == Int8(-1)  # 1 < 3 → short
    @test cond_so(2) == Int8(0)   # 3 == 3 → neutral
    @test cond_so(3) == Int8(0)   # 5 > 3 → neutral
end

# ── Phase 3: Robustness — Performance ──

@testitem "Crossover: Zero Allocations in _fill_sides_generic!" tags = [
    :side, :crossover, :stability
] begin
    using Backtest, Test

    fast = collect(1.0:200.0)
    slow = fill(100.0, 200)
    sides = zeros(Int8, 200)
    cond_f = Backtest._get_condition_func(fast, slow, LongShort())

    # Warmup
    Backtest._fill_sides_generic!(sides, 1, cond_f)

    allocs(sides, from_idx, cond_f) =
        @allocated Backtest._fill_sides_generic!(sides, from_idx, cond_f)

    actual = minimum([@allocated(allocs(sides, 1, cond_f)) for _ in 1:3])
    @test actual == 0
end

# ── Phase 4: Deep Analysis ──

@testitem "Crossover: Static Analysis (JET.jl)" tags = [:side, :crossover, :stability] begin
    using Backtest, Test, JET

    fast = collect(1.0:100.0)
    slow = fill(50.0, 100)

    @test_opt target_modules = (Backtest,) calculate_side(Crossover(), fast, slow)
    @test_call target_modules = (Backtest,) calculate_side(Crossover(), fast, slow)
end

# ── Phase 5: Allocation Budget Tests ──

@testitem "Crossover: Allocation — calculate_side (LongShort)" tags = [
    :side, :crossover, :allocation
] begin
    using Backtest, Test

    fast = collect(1.0:200.0)
    slow = fill(100.0, 200)
    cross = Crossover()

    # Warmup
    calculate_side(cross, fast, slow)

    # Budget: Vector{Int8}(undef, n)
    expected_data = sizeof(Int8) * length(fast)
    budget = expected_data + 512

    allocs_calc(cross, fast, slow) = @allocated calculate_side(cross, fast, slow)

    actual = minimum([@allocated(allocs_calc(cross, fast, slow)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Crossover: Allocation — calculate_side (LongOnly)" tags = [
    :side, :crossover, :allocation
] begin
    using Backtest, Test

    fast = collect(1.0:200.0)
    slow = fill(100.0, 200)
    cross = Crossover(; direction=LongOnly())

    calculate_side(cross, fast, slow)

    expected_data = sizeof(Int8) * length(fast)
    budget = expected_data + 512

    allocs_calc(cross, fast, slow) = @allocated calculate_side(cross, fast, slow)

    actual = minimum([@allocated(allocs_calc(cross, fast, slow)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Crossover: Allocation — calculate_side (ShortOnly)" tags = [
    :side, :crossover, :allocation
] begin
    using Backtest, Test

    fast = collect(1.0:200.0)
    slow = fill(100.0, 200)
    cross = Crossover(; direction=ShortOnly())

    calculate_side(cross, fast, slow)

    expected_data = sizeof(Int8) * length(fast)
    budget = expected_data + 512

    allocs_calc(cross, fast, slow) = @allocated calculate_side(cross, fast, slow)

    actual = minimum([@allocated(allocs_calc(cross, fast, slow)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Crossover: Allocation — Callable with NamedTuple" tags = [
    :side, :crossover, :allocation
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=200)
    ema_data = EMA(10, 50)(bars)
    cross = Crossover(:ema_10, :ema_50)

    # Warmup
    cross(ema_data)

    # Budget: Vector{Int8}(undef, n) + NamedTuple merge overhead
    expected_data = sizeof(Int8) * 200
    budget = expected_data + 1024

    allocs_functor(cross, ema_data) = @allocated cross(ema_data)

    actual = minimum([@allocated(allocs_functor(cross, ema_data)) for _ in 1:3])

    @test actual <= budget
    @test actual > 0
end

@testitem "Crossover: Allocation — Float32" tags = [:side, :crossover, :allocation] begin
    using Backtest, Test

    fast = collect(Float32.(1:200))
    slow = fill(Float32(100), 200)
    cross = Crossover()

    calculate_side(cross, fast, slow)

    expected_data = sizeof(Int8) * length(fast)
    budget = expected_data + 512

    allocs_calc(cross, fast, slow) = @allocated calculate_side(cross, fast, slow)

    actual = minimum([@allocated(allocs_calc(cross, fast, slow)) for _ in 1:3])

    @test actual <= budget
end

# ── wait_for_cross=false reference values for LongOnly and ShortOnly ──
#
# The existing reference tests only cover wait_for_cross=false for LongShort.
# With wait_for_cross=false, _calculate_cross_sides skips _find_first_cross
# and calls _fill_sides_generic! from the first valid (non-NaN) index directly.
# The direction filter then determines what signal to emit at each bar.

@testitem "Crossover: Hand-Calculated Reference (LongOnly, wait_for_cross=false)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    # Same series as the wait_for_cross=true LongOnly reference test
    fast = Float64[1, 2, 5, 6, 2, 1, 5, 6]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(
        Crossover(; wait_for_cross=false, direction=LongOnly()), fast, slow
    )

    @test length(sides) == 8
    # start_idx=1 (slow[1] is not NaN), emit immediately via LongOnly condition:
    # ifelse(fast[i] > slow[i], 1, 0)
    @test sides[1] == Int8(0)   # 1 < 3
    @test sides[2] == Int8(0)   # 2 < 3
    @test sides[3] == Int8(1)   # 5 > 3
    @test sides[4] == Int8(1)   # 6 > 3
    @test sides[5] == Int8(0)   # 2 < 3
    @test sides[6] == Int8(0)   # 1 < 3
    @test sides[7] == Int8(1)   # 5 > 3
    @test sides[8] == Int8(1)   # 6 > 3
end

@testitem "Crossover: Hand-Calculated Reference (ShortOnly, wait_for_cross=false)" tags = [
    :side, :crossover, :reference
] begin
    using Backtest, Test

    # Same series as the wait_for_cross=true ShortOnly reference test
    fast = Float64[5, 4, 1, 0, 4, 5, 1, 0]
    slow = Float64[3, 3, 3, 3, 3, 3, 3, 3]

    sides = calculate_side(
        Crossover(; wait_for_cross=false, direction=ShortOnly()), fast, slow
    )

    @test length(sides) == 8
    # start_idx=1, emit immediately via ShortOnly condition:
    # ifelse(fast[i] < slow[i], -1, 0)
    @test sides[1] == Int8(0)    # 5 > 3
    @test sides[2] == Int8(0)    # 4 > 3
    @test sides[3] == Int8(-1)   # 1 < 3
    @test sides[4] == Int8(-1)   # 0 < 3
    @test sides[5] == Int8(0)    # 4 > 3
    @test sides[6] == Int8(0)    # 5 > 3
    @test sides[7] == Int8(-1)   # 1 < 3
    @test sides[8] == Int8(-1)   # 0 < 3
end
