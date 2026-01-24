using Backtest, Test

# Access internal functions for testing
const _positive_float = Backtest._positive_float
const _natural = Backtest._natural

@testset "Utility Functions" begin
    @testset "_positive_float" begin
        @testset "Valid inputs" begin
            # Positive integers
            @test _positive_float(1) == 1
            @test _positive_float(5) == 5
            @test _positive_float(100) == 100

            # Positive floats
            @test _positive_float(0.5) == 0.5
            @test _positive_float(1.5) == 1.5
            @test _positive_float(3.14159) == 3.14159

            # Very small positive
            @test _positive_float(1e-10) == 1e-10
            @test _positive_float(1e-100) == 1e-100

            # Large values
            @test _positive_float(1e10) == 1e10
            @test _positive_float(1e100) == 1e100
        end

        @testset "Zero throws ArgumentError" begin
            @test_throws ArgumentError _positive_float(0)
            @test_throws ArgumentError _positive_float(0.0)
            @test_throws ArgumentError _positive_float(-0.0)
        end

        @testset "Negative values throw ArgumentError" begin
            @test_throws ArgumentError _positive_float(-1)
            @test_throws ArgumentError _positive_float(-100)
            @test_throws ArgumentError _positive_float(-0.5)
            @test_throws ArgumentError _positive_float(-1.5)
            @test_throws ArgumentError _positive_float(-1e-10)
        end

        @testset "Type preservation" begin
            @test typeof(_positive_float(1)) == Int
            @test typeof(_positive_float(1.0)) == Float64
            @test typeof(_positive_float(1.0f0)) == Float32
        end

        @testset "Special float values" begin
            # Inf is positive, so it should pass
            @test _positive_float(Inf) == Inf

            # NaN comparisons are false, so NaN > 0 is false
            @test_throws ArgumentError _positive_float(NaN)

            # Negative Inf
            @test_throws ArgumentError _positive_float(-Inf)
        end
    end

    @testset "_natural" begin
        @testset "Valid inputs" begin
            @test _natural(1) == 1
            @test _natural(5) == 5
            @test _natural(100) == 100
            @test _natural(1000000) == 1000000
        end

        @testset "Zero throws ArgumentError" begin
            @test_throws ArgumentError _natural(0)
        end

        @testset "Negative integers throw ArgumentError" begin
            @test_throws ArgumentError _natural(-1)
            @test_throws ArgumentError _natural(-100)
        end

        @testset "Non-integer types throw MethodError" begin
            # _natural only accepts Int, so floats cause MethodError
            @test_throws MethodError _natural(3.5)
            @test_throws MethodError _natural(1.0)
            @test_throws MethodError _natural(0.5)
        end
    end
end
