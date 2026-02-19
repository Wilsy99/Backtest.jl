# ── Phase 2: Core Correctness ──

@testitem "Execution Basis: _temporal_priority ordering" tags = [
    :label, :execution, :unit
] begin
    using Backtest, Test

    # Priority must be strictly increasing: Immediate < CurrentOpen < CurrentClose < NextOpen < NextClose
    @test Backtest._temporal_priority(Immediate()) == 1
    @test Backtest._temporal_priority(CurrentOpen()) == 2
    @test Backtest._temporal_priority(CurrentClose()) == 3
    @test Backtest._temporal_priority(NextOpen()) == 4
    @test Backtest._temporal_priority(NextClose()) == 5

    # Verify strict ordering across all pairs
    bases = [Immediate(), CurrentOpen(), CurrentClose(), NextOpen(), NextClose()]
    for i in 1:(length(bases) - 1)
        @test Backtest._temporal_priority(bases[i]) < Backtest._temporal_priority(bases[i + 1])
    end
end

@testitem "Execution Basis: _get_idx_adj" tags = [:label, :execution, :unit] begin
    using Backtest, Test

    # Current* and Immediate → 0, Next* → 1
    @test Backtest._get_idx_adj(CurrentOpen()) == 0
    @test Backtest._get_idx_adj(CurrentClose()) == 0
    @test Backtest._get_idx_adj(Immediate()) == 0
    @test Backtest._get_idx_adj(NextOpen()) == 1
    @test Backtest._get_idx_adj(NextClose()) == 1
end

@testitem "Execution Basis: _get_price dispatch" tags = [:label, :execution, :unit] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [10.0, 20.0, 30.0],
        [15.0, 25.0, 35.0],
        [5.0, 15.0, 25.0],
        [12.0, 22.0, 32.0],
        [100.0, 200.0, 300.0],
        [DateTime(2024, 1, 1), DateTime(2024, 1, 2), DateTime(2024, 1, 3)],
        TimeBar(),
    )
    args = (; bars=bars)

    # CurrentOpen / NextOpen → open price
    @test Backtest._get_price(CurrentOpen(), nothing, 2, args) == 20.0
    @test Backtest._get_price(NextOpen(), nothing, 3, args) == 30.0

    # CurrentClose / NextClose → close price
    @test Backtest._get_price(CurrentClose(), nothing, 1, args) == 12.0
    @test Backtest._get_price(NextClose(), nothing, 2, args) == 22.0

    # Immediate with float level → return level directly
    @test Backtest._get_price(Immediate(), 105.5, 2, args) == 105.5

    # Immediate with DateTime (TimeBarrier) → fall back to close
    @test Backtest._get_price(Immediate(), DateTime(2024, 1, 1), 2, args) == 22.0

    # Immediate with Bool (ConditionBarrier) → fall back to close
    @test Backtest._get_price(Immediate(), true, 3, args) == 32.0
end

@testitem "Execution Basis: _get_exposure_adj" tags = [:label, :execution, :unit] begin
    using Backtest, Test

    # Open-based and Immediate → 0, Close-based → 1
    @test Backtest._get_exposure_adj(CurrentOpen()) == 0
    @test Backtest._get_exposure_adj(NextOpen()) == 0
    @test Backtest._get_exposure_adj(Immediate()) == 0
    @test Backtest._get_exposure_adj(CurrentClose()) == 1
    @test Backtest._get_exposure_adj(NextClose()) == 1
end

# ── Phase 2: Type Stability ──

@testitem "Execution Basis: Type Stability" tags = [:label, :execution, :stability] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        [10.0, 20.0],
        [15.0, 25.0],
        [5.0, 15.0],
        [12.0, 22.0],
        [100.0, 200.0],
        [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
        TimeBar(),
    )
    args = (; bars=bars)

    @test @inferred(Backtest._temporal_priority(Immediate())) isa Int
    @test @inferred(Backtest._temporal_priority(NextOpen())) isa Int

    @test @inferred(Backtest._get_idx_adj(CurrentOpen())) isa Int
    @test @inferred(Backtest._get_idx_adj(NextClose())) isa Int

    @test @inferred(Backtest._get_price(CurrentOpen(), nothing, 1, args)) isa Float64
    @test @inferred(Backtest._get_price(Immediate(), 105.0, 1, args)) isa Float64

    @test @inferred(Backtest._get_exposure_adj(CurrentOpen())) isa Int
    @test @inferred(Backtest._get_exposure_adj(NextClose())) isa Int
end

# ── Phase 3: Edge Cases ──

@testitem "Execution Basis: _get_price boundary indices" tags = [
    :label, :execution, :edge
] begin
    using Backtest, Test, Dates

    # Single-element PriceBars — verify idx=1 works for all bases
    bars = PriceBars(
        [10.0], [15.0], [5.0], [12.0], [100.0],
        [DateTime(2024, 1, 1)], TimeBar(),
    )
    args = (; bars=bars)

    @test Backtest._get_price(CurrentOpen(), nothing, 1, args) == 10.0
    @test Backtest._get_price(CurrentClose(), nothing, 1, args) == 12.0
    @test Backtest._get_price(NextOpen(), nothing, 1, args) == 10.0
    @test Backtest._get_price(Immediate(), 99.0, 1, args) == 99.0
end

@testitem "Execution Basis: Float32 PriceBars" tags = [:label, :execution, :edge] begin
    using Backtest, Test, Dates

    bars = PriceBars(
        Float32[10.0, 20.0],
        Float32[15.0, 25.0],
        Float32[5.0, 15.0],
        Float32[12.0, 22.0],
        Float32[100.0, 200.0],
        [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
        TimeBar(),
    )
    args = (; bars=bars)

    # Open-based should return Float32
    result = Backtest._get_price(CurrentOpen(), nothing, 1, args)
    @test result isa Float32
    @test result == 10.0f0

    # Close-based should return Float32
    result2 = Backtest._get_price(CurrentClose(), nothing, 1, args)
    @test result2 isa Float32

    # Immediate with Float64 level — returns the level, not bar data
    result3 = Backtest._get_price(Immediate(), 105.0, 1, args)
    @test result3 == 105.0
end
