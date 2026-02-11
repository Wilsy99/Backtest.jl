@testset "Types & Construction" begin
    # ── PriceBars ──

    @testset "PriceBars construction" begin
        n = 10
        o = Float64.(1:n)
        h = Float64.(2:n+1)
        l = Float64.(0:n-1)
        c = Float64.(1:n) .+ 0.5
        v = fill(1000.0, n)
        ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]

        pb = PriceBars(o, h, l, c, v, ts, TimeBar())

        @test pb isa PriceBars{TimeBar,Float64}
        @test pb.open === o
        @test pb.high === h
        @test pb.low === l
        @test pb.close === c
        @test pb.volume === v
        @test pb.timestamp === ts
    end

    @testset "PriceBars length" begin
        bars = make_pricebars(; n=50)
        @test length(bars) == 50
    end

    @testset "PriceBars with Float32" begin
        n = 5
        o = Float32.(1:n)
        h = Float32.(2:n+1)
        l = Float32.(0:n-1)
        c = Float32.(1:n) .+ 0.5f0
        v = fill(1000.0f0, n)
        ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]

        pb = PriceBars(o, h, l, c, v, ts, TimeBar())
        @test pb isa PriceBars{TimeBar,Float32}
    end

    # ── Bar Types ──

    @testset "Bar type hierarchy" begin
        @test TimeBar <: AbstractBarType
        @test DollarBar <: AbstractBarType
        @test TimeBar() isa AbstractBarType
        @test DollarBar() isa AbstractBarType
    end

    # ── Direction Types ──

    @testset "Direction type hierarchy" begin
        @test LongOnly <: AbstractDirection
        @test ShortOnly <: AbstractDirection
        @test LongShort <: AbstractDirection
        @test LongOnly() isa AbstractDirection
        @test ShortOnly() isa AbstractDirection
        @test LongShort() isa AbstractDirection
    end

    # ── Pipeline Composition (>>) ──

    @testset "Pipeline composition with >>" begin
        bars = make_pricebars(; n=200)

        # data >> indicator creates a Job
        job = bars >> EMA(10)
        @test job isa Backtest.Job

        # Job execution returns a NamedTuple
        result = job()
        @test result isa NamedTuple
        @test haskey(result, :bars)
        @test haskey(result, :ema_10)
    end

    @testset "Pipeline chaining with >>" begin
        bars = make_pricebars(; n=200)

        # Chain multiple steps
        job = bars >> EMA(10, 50)
        result = job()

        @test haskey(result, :ema_10)
        @test haskey(result, :ema_50)
    end

    @testset "Pipeline function composition with >>" begin
        # Two indicators composed without data
        composed = EMA(10) >> CUSUM(1.0)

        bars = make_pricebars(; n=200)
        result = composed(bars)

        @test haskey(result, :bars)
        @test haskey(result, :ema_10)
        @test haskey(result, :cusum)
    end

    # ── Execution Basis Types ──

    @testset "Execution basis hierarchy" begin
        @test CurrentOpen <: AbstractExecutionBasis
        @test CurrentClose <: AbstractExecutionBasis
        @test NextOpen <: AbstractExecutionBasis
        @test NextClose <: AbstractExecutionBasis
        @test Immediate <: AbstractExecutionBasis
    end

    @testset "Execution basis index adjustments" begin
        @test Backtest._get_idx_adj(CurrentOpen()) == 0
        @test Backtest._get_idx_adj(CurrentClose()) == 0
        @test Backtest._get_idx_adj(Immediate()) == 0
        @test Backtest._get_idx_adj(NextOpen()) == 1
        @test Backtest._get_idx_adj(NextClose()) == 1
    end

    @testset "Temporal priority ordering" begin
        # Immediate < CurrentOpen < CurrentClose < NextOpen < NextClose
        @test Backtest._temporal_priority(Immediate()) < Backtest._temporal_priority(CurrentOpen())
        @test Backtest._temporal_priority(CurrentOpen()) < Backtest._temporal_priority(CurrentClose())
        @test Backtest._temporal_priority(CurrentClose()) < Backtest._temporal_priority(NextOpen())
        @test Backtest._temporal_priority(NextOpen()) < Backtest._temporal_priority(NextClose())
    end

    # ── Abstract Type Hierarchy ──

    @testset "Abstract type hierarchy" begin
        @test EMA <: AbstractIndicator
        @test CUSUM <: AbstractIndicator
        @test Crossover <: AbstractSide
        @test Event <: AbstractEvent
        @test Label <: AbstractLabel
        @test Label! <: AbstractLabel
        @test LowerBarrier <: AbstractBarrier
        @test UpperBarrier <: AbstractBarrier
        @test TimeBarrier <: AbstractBarrier
        @test ConditionBarrier <: AbstractBarrier
    end
end
