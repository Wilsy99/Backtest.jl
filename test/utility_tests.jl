using Backtest, Test

@testset "_natural Validation" begin
    @testset "Valid inputs" begin
        @test Backtest._natural(1) == 1
        @test Backtest._natural(5) == 5
        @test Backtest._natural(100) == 100
        @test Backtest._natural(1000) == 1000
    end

    @testset "Zero - should throw" begin
        @test_throws ArgumentError Backtest._natural(0)
    end

    @testset "Negative integers - should throw" begin
        @test_throws ArgumentError Backtest._natural(-1)
        @test_throws ArgumentError Backtest._natural(-100)
    end

    @testset "Non-integers - should throw" begin
        @test_throws ArgumentError Backtest._natural(3.5)
        @test_throws ArgumentError Backtest._natural(1.0)
        @test_throws ArgumentError Backtest._natural(0.5)
    end
end
