# ── Side module shared infrastructure tests ──
#
# Tests for _fill_sides_generic! and the AbstractSide callable
# interface. These are shared by all side implementations.

@testitem "Side: _fill_sides_generic! correctness" tags = [:side, :unit] begin
    using Backtest, Test

    sides = zeros(Int8, 10)
    cond = i -> Int8(i <= 5 ? 1 : -1)

    Backtest._fill_sides_generic!(sides, 1, cond)

    @test sides[1] == Int8(1)
    @test sides[5] == Int8(1)
    @test sides[6] == Int8(-1)
    @test sides[10] == Int8(-1)
end

@testitem "Side: _fill_sides_generic! partial fill" tags = [:side, :unit] begin
    using Backtest, Test

    sides = zeros(Int8, 10)
    cond = i -> Int8(1)

    # Fill only from index 6 onwards
    Backtest._fill_sides_generic!(sides, 6, cond)

    @test all(sides[1:5] .== Int8(0))
    @test all(sides[6:10] .== Int8(1))
end

@testitem "Side: _fill_sides_generic! from_idx == length" tags = [:side, :edge] begin
    using Backtest, Test

    sides = zeros(Int8, 5)
    cond = i -> Int8(1)

    Backtest._fill_sides_generic!(sides, 5, cond)

    @test all(sides[1:4] .== Int8(0))
    @test sides[5] == Int8(1)
end

@testitem "Side: AbstractSide callable merges correctly" tags = [
    :side, :unit
] setup = [TestData] begin
    using Backtest, Test

    bars = TestData.make_pricebars(; n=100)
    ema_data = EMA(10, 50)(bars)

    cross = Crossover(:ema_10, :ema_50)
    result = cross(ema_data)

    # Callable should preserve all upstream keys
    @test haskey(result, :bars)
    @test haskey(result, :ema_10)
    @test haskey(result, :ema_50)
    @test haskey(result, :side)

    # The side values should match direct calculate_side
    expected = calculate_side(cross, ema_data.ema_10, ema_data.ema_50)
    @test result.side == expected
end
