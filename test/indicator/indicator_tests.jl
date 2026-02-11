@testset "Indicator Callable Interface" begin
    bars = make_pricebars(; n=200)

    # ── PriceBars dispatch ──

    @testset "EMA callable on PriceBars" begin
        result = EMA(10)(bars)

        @test result isa NamedTuple
        @test haskey(result, :bars)
        @test haskey(result, :ema_10)
        @test result.bars === bars
        @test length(result.ema_10) == length(bars)
    end

    @testset "EMA multi-period callable on PriceBars" begin
        result = EMA(5, 20)(bars)

        @test haskey(result, :bars)
        @test haskey(result, :ema_5)
        @test haskey(result, :ema_20)
        @test length(result.ema_5) == length(bars)
        @test length(result.ema_20) == length(bars)
    end

    @testset "CUSUM callable on PriceBars" begin
        result = CUSUM(1.0)(bars)

        @test result isa NamedTuple
        @test haskey(result, :bars)
        @test haskey(result, :cusum)
        @test result.bars === bars
        @test length(result.cusum) == length(bars)
    end

    # ── NamedTuple dispatch ──

    @testset "EMA callable on NamedTuple" begin
        initial_nt = (; bars=bars, some_field=[1, 2, 3])
        result = EMA(10)(initial_nt)

        @test haskey(result, :bars)
        @test haskey(result, :some_field)
        @test haskey(result, :ema_10)
        @test result.some_field == [1, 2, 3]  # preserved
    end

    @testset "CUSUM callable on NamedTuple" begin
        initial_nt = (; bars=bars)
        result = CUSUM(1.0)(initial_nt)

        @test haskey(result, :bars)
        @test haskey(result, :cusum)
    end

    # ── Chaining indicators ──

    @testset "Chain EMA then CUSUM" begin
        result = CUSUM(1.0)(EMA(10)(bars))

        @test haskey(result, :bars)
        @test haskey(result, :ema_10)
        @test haskey(result, :cusum)
    end

    @testset "Chain multiple EMA calls" begin
        result = EMA(20)(EMA(10)(bars))

        @test haskey(result, :ema_10)
        @test haskey(result, :ema_20)
    end

    # ── Uses close prices ──

    @testset "Indicator operates on close prices" begin
        ema_direct = calculate_indicator(EMA(10), bars.close)
        ema_callable = EMA(10)(bars)

        # The callable interface should use bars.close
        for i in 10:length(bars)
            @test ema_callable.ema_10[i] ≈ ema_direct[i]
        end
    end
end
