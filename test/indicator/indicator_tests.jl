using Backtest, Test

@testset "Indicator Types" begin
    @testset "Abstract Type Hierarchy" begin
        @test EMA <: Indicator
        @test CUSUM <: Indicator
        @test isabstracttype(Indicator)
    end

    @testset "EMA Constructor" begin
        @testset "Valid periods" begin
            @test EMA(1).period == 1
            @test EMA(5).period == 5
            @test EMA(10).period == 10
            @test EMA(100).period == 100
            @test EMA(1000).period == 1000
        end

        @testset "Invalid periods" begin
            @test_throws ArgumentError EMA(0)
            @test_throws ArgumentError EMA(-1)
            @test_throws ArgumentError EMA(-100)
        end

        @testset "Non-integer periods" begin
            @test_throws MethodError EMA(5.0)
            @test_throws MethodError EMA(5.5)
        end

        @testset "Type" begin
            @test EMA(5) isa EMA
            @test EMA(5) isa Indicator
        end
    end

    @testset "CUSUM Constructor" begin
        @testset "Valid inputs - defaults" begin
            c = CUSUM(1.0)
            @test c.multiplier == 1.0
            @test c.span == 100
            @test c.expected_value == 0.0
        end

        @testset "Valid inputs - custom values" begin
            c = CUSUM(0.5; span=50, expected_value=0.01)
            @test c.multiplier == 0.5
            @test c.span == 50
            @test c.expected_value == 0.01
        end

        @testset "Valid inputs - integer multiplier promoted to float" begin
            c = CUSUM(2)
            @test c.multiplier == 2.0
            @test typeof(c.multiplier) <: AbstractFloat
        end

        @testset "Invalid multiplier" begin
            @test_throws ArgumentError CUSUM(0)
            @test_throws ArgumentError CUSUM(0.0)
            @test_throws ArgumentError CUSUM(-1)
            @test_throws ArgumentError CUSUM(-0.5)
        end

        @testset "Invalid span" begin
            @test_throws ArgumentError CUSUM(1.0; span=0)
            @test_throws ArgumentError CUSUM(1.0; span=-1)
        end

        @testset "Type parameterization" begin
            c64 = CUSUM(1.0)
            @test c64 isa CUSUM{Float64}

            c32 = CUSUM(1.0f0)
            @test c32 isa CUSUM{Float32}
        end

        @testset "expected_value can be negative" begin
            c = CUSUM(1.0; expected_value=-0.01)
            @test c.expected_value == -0.01
        end
    end

    @testset "Timeframe Types" begin
        @test Daily <: Timeframe
        @test Weekly <: Timeframe
        @test isabstracttype(Timeframe)

        @test Daily() isa Timeframe
        @test Weekly() isa Timeframe
    end
end
