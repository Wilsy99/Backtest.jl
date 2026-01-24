using Backtest, Test

# Reference implementation for verification
function reference_ema(prices::Vector{Float64}, period::Int)
    n = length(prices)
    result = fill(NaN, n)
    if period > n
        return result
    end

    result[period] = sum(prices[1:period]) / period
    alpha = 2.0 / (period + 1)

    for i in (period + 1):n
        result[i] = (prices[i] * alpha) + (result[i - 1] * (1 - alpha))
    end
    return result
end

@testset "EMA Calculation" begin
    @testset "Single EMA - Basic Functionality" begin
        @testset "Return type and length" begin
            prices = Float64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            result = calculate_indicators(prices, EMA(3))

            @test result isa Vector{Float64}
            @test length(result) == length(prices)
        end

        @testset "NaN placement" begin
            prices = Float64.(1:20)
            result = calculate_indicators(prices, EMA(5))

            @test all(isnan.(result[1:4]))
            @test !any(isnan.(result[5:end]))
        end

        @testset "Preserves input element type" begin
            prices_f64 = Float64[1, 2, 3, 4, 5]
            result_f64 = calculate_indicators(prices_f64, EMA(2))
            @test eltype(result_f64) == Float64

            prices_f32 = Float32[1, 2, 3, 4, 5]
            result_f32 = calculate_indicators(prices_f32, EMA(2))
            @test eltype(result_f32) == Float32
        end
    end

    @testset "Single EMA - Mathematical Correctness" begin
        @testset "SMA seed at position period" begin
            prices = Float64.(1:10)
            result = calculate_indicators(prices, EMA(5))

            expected_sma = sum(prices[1:5]) / 5
            @test result[5] ≈ expected_sma atol = 1e-10
        end

        @testset "EMA formula verification" begin
            prices = Float64[10, 11, 12, 11.5, 13, 12.5, 14, 13.5, 15, 14.5]
            result = calculate_indicators(prices, EMA(3))
            expected = reference_ema(prices, 3)

            for i in 3:length(prices)
                @test result[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Period = 1 equals input prices" begin
            prices = Float64[5, 10, 15, 20, 25]
            result = calculate_indicators(prices, EMA(1))

            for i in eachindex(prices)
                @test result[i] ≈ prices[i] atol = 1e-10
            end
        end

        @testset "Constant prices gives constant EMA" begin
            prices = fill(50.0, 20)
            result = calculate_indicators(prices, EMA(5))

            for i in 5:20
                @test result[i] ≈ 50.0 atol = 1e-10
            end
        end
    end

    @testset "Single EMA - Edge Cases" begin
        @testset "Period > length(prices)" begin
            prices = Float64.(1:5)
            result = calculate_indicators(prices, EMA(10))

            @test all(isnan.(result))
        end

        @testset "Period == length(prices)" begin
            prices = Float64.(1:5)
            result = calculate_indicators(prices, EMA(5))

            @test all(isnan.(result[1:4]))
            @test result[5] ≈ sum(prices) / 5 atol = 1e-10
        end

        @testset "Single element, period = 1" begin
            prices = Float64[100]
            result = calculate_indicators(prices, EMA(1))

            @test length(result) == 1
            @test result[1] ≈ 100.0 atol = 1e-10
        end

        @testset "Two elements, period = 2" begin
            prices = Float64[100, 200]
            result = calculate_indicators(prices, EMA(2))

            @test isnan(result[1])
            @test result[2] ≈ 150.0 atol = 1e-10  # SMA of [100, 200]
        end

        @testset "Minimum viable: period=2, length=3" begin
            prices = Float64[10, 20, 30]
            result = calculate_indicators(prices, EMA(2))
            expected = reference_ema(prices, 2)

            @test isnan(result[1])
            @test result[2] ≈ expected[2] atol = 1e-10
            @test result[3] ≈ expected[3] atol = 1e-10
        end

        @testset "Long period (50)" begin
            prices = Float64.(1:100)
            result = calculate_indicators(prices, EMA(50))
            expected = reference_ema(prices, 50)

            @test all(isnan.(result[1:49]))
            for i in 50:100
                @test result[i] ≈ expected[i] atol = 1e-9
            end
        end
    end

    @testset "Single EMA - Loop Unrolling Verification" begin
        period = 3

        @testset "Remainder 0: (n-p) % 4 == 0" begin
            prices = Float64.(1:11)  # n=11, n-p=8, 8%4=0
            result = calculate_indicators(prices, EMA(period))
            expected = reference_ema(prices, period)

            for i in period:length(prices)
                @test result[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 1: (n-p) % 4 == 1" begin
            prices = Float64.(1:12)  # n=12, n-p=9, 9%4=1
            result = calculate_indicators(prices, EMA(period))
            expected = reference_ema(prices, period)

            for i in period:length(prices)
                @test result[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 2: (n-p) % 4 == 2" begin
            prices = Float64.(1:13)  # n=13, n-p=10, 10%4=2
            result = calculate_indicators(prices, EMA(period))
            expected = reference_ema(prices, period)

            for i in period:length(prices)
                @test result[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 3: (n-p) % 4 == 3" begin
            prices = Float64.(1:14)  # n=14, n-p=11, 11%4=3
            result = calculate_indicators(prices, EMA(period))
            expected = reference_ema(prices, period)

            for i in period:length(prices)
                @test result[i] ≈ expected[i] atol = 1e-10
            end
        end
    end

    @testset "Single EMA - Numerical Stability" begin
        @testset "Large values - no overflow" begin
            prices = fill(1e15, 20)
            prices[10] = 1.1e15
            result = calculate_indicators(prices, EMA(5))

            @test !any(isinf.(result[5:end]))
            @test !any(isnan.(result[5:end]))
        end

        @testset "Small values - no underflow" begin
            prices = fill(1e-15, 20)
            prices[10] = 1.1e-15
            result = calculate_indicators(prices, EMA(5))

            @test !any(isinf.(result[5:end]))
            @test !any(isnan.(result[5:end]))
            @test all(result[5:end] .> 0)
        end

        @testset "Mixed scales" begin
            prices = Float64[1e-10, 1e10, 1e-10, 1e10, 1e-10, 1e10, 1e-10, 1e10, 1e-10, 1e10]
            result = calculate_indicators(prices, EMA(3))

            @test !any(isinf.(result[3:end]))
            @test !any(isnan.(result[3:end]))
        end
    end

    @testset "Single EMA - Mathematical Properties" begin
        @testset "Monotonic increasing: EMA lags below" begin
            prices = Float64.(1:20)
            result = calculate_indicators(prices, EMA(5))

            for i in 6:20
                @test result[i] < prices[i]
            end
        end

        @testset "Monotonic increasing: EMA itself increases" begin
            prices = Float64.(1:20)
            result = calculate_indicators(prices, EMA(5))

            for i in 6:20
                @test result[i] > result[i - 1]
            end
        end

        @testset "Monotonic decreasing: EMA lags above" begin
            prices = Float64.(20:-1:1)
            result = calculate_indicators(prices, EMA(5))

            for i in 6:20
                @test result[i] > prices[i]
            end
        end

        @testset "Monotonic decreasing: EMA itself decreases" begin
            prices = Float64.(20:-1:1)
            result = calculate_indicators(prices, EMA(5))

            for i in 6:20
                @test result[i] < result[i - 1]
            end
        end

        @testset "EMA bounded by data range" begin
            prices = Float64[10, 15, 8, 20, 12, 18, 9, 14, 11, 16]
            result = calculate_indicators(prices, EMA(3))

            min_price = minimum(prices)
            max_price = maximum(prices)

            for i in 3:length(prices)
                @test min_price <= result[i] <= max_price
            end
        end
    end

    @testset "Multiple EMAs" begin
        @testset "Returns NamedTuple" begin
            prices = Float64.(1:50)
            result = calculate_indicators(prices, EMA(5), EMA(10))

            @test result isa NamedTuple
            @test haskey(result, :ema_5)
            @test haskey(result, :ema_10)
        end

        @testset "Correct keys" begin
            prices = Float64.(1:50)
            result = calculate_indicators(prices, EMA(3), EMA(10), EMA(15))

            @test keys(result) == (:ema_3, :ema_10, :ema_15)
        end

        @testset "Each value is correct type and length" begin
            prices = Float64.(1:50)
            result = calculate_indicators(prices, EMA(5), EMA(10), EMA(20))

            @test result.ema_5 isa Vector{Float64}
            @test result.ema_10 isa Vector{Float64}
            @test result.ema_20 isa Vector{Float64}

            @test length(result.ema_5) == 50
            @test length(result.ema_10) == 50
            @test length(result.ema_20) == 50
        end

        @testset "Values match single EMA computation" begin
            prices = Float64.(1:50)
            result = calculate_indicators(prices, EMA(5), EMA(10), EMA(20))

            expected_5 = reference_ema(prices, 5)
            expected_10 = reference_ema(prices, 10)
            expected_20 = reference_ema(prices, 20)

            for i in 5:50
                @test result.ema_5[i] ≈ expected_5[i] atol = 1e-10
            end
            for i in 10:50
                @test result.ema_10[i] ≈ expected_10[i] atol = 1e-10
            end
            for i in 20:50
                @test result.ema_20[i] ≈ expected_20[i] atol = 1e-10
            end
        end

        @testset "Many indicators at once" begin
            prices = Float64.(1:200)
            indicators = ntuple(i -> EMA(i), 50)
            result = calculate_indicators(prices, indicators...)

            # Spot check a few
            for period in [1, 10, 25, 50]
                expected = reference_ema(prices, period)
                col = result[Symbol("ema_", period)]
                for i in period:200
                    @test col[i] ≈ expected[i] atol = 1e-9
                end
            end
        end
    end

    @testset "Type Handling" begin
        @testset "Float64 input" begin
            prices = Float64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            result = calculate_indicators(prices, EMA(3))
            @test eltype(result) == Float64
        end

        @testset "Float32 input" begin
            prices = Float32[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            result = calculate_indicators(prices, EMA(3))
            @test eltype(result) == Float32

            expected = reference_ema(Float64.(prices), 3)
            for i in 3:10
                @test result[i] ≈ expected[i] atol = 1e-5
            end
        end

        @testset "Integer input throws" begin
            prices = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            @test_throws MethodError calculate_indicators(prices, EMA(3))
        end
    end
end
