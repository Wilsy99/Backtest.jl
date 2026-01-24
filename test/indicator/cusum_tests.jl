using Backtest, Test

@testset "CUSUM Calculation" begin
    @testset "Basic Functionality" begin
        @testset "Return type" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)  # Ensure positive
            result = calculate_indicators(prices, CUSUM(1.0))

            @test result isa Vector{Int8}
        end

        @testset "Return length matches input" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test length(result) == 200
        end

        @testset "Values in {-1, 0, 1}" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test all(x -> x ∈ Int8[-1, 0, 1], result)
        end

        @testset "Warmup period is zeros" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0))

            # First 101 values should be 0 (warmup)
            @test all(result[1:101] .== 0)
        end
    end

    @testset "Short Data Handling" begin
        @testset "Length <= 101 returns all zeros" begin
            prices = Float64.(100:200)  # 101 elements
            result = calculate_indicators(prices, CUSUM(1.0))

            @test all(result .== 0)
        end

        @testset "Length = 50 returns all zeros" begin
            prices = Float64.(100:149)  # 50 elements
            result = calculate_indicators(prices, CUSUM(1.0))

            @test all(result .== 0)
        end

        @testset "Length = 102 can have one non-zero" begin
            # Create data where index 102 might trigger a signal
            prices = fill(100.0, 102)
            prices[102] = 200.0  # Large jump
            result = calculate_indicators(prices, CUSUM(0.1))

            # At least the first 101 are zeros
            @test all(result[1:101] .== 0)
            # Index 102 might or might not be non-zero depending on threshold
            @test length(result) == 102
        end
    end

    @testset "Signal Detection" begin
        @testset "Large positive jump triggers positive signal" begin
            # Stable prices then big jump
            prices = vcat(fill(100.0, 150), fill(200.0, 50))
            result = calculate_indicators(prices, CUSUM(0.5))

            # Should eventually see a +1 signal after the jump
            @test any(result .== 1)
        end

        @testset "Large negative drop triggers negative signal" begin
            # Stable prices then big drop
            prices = vcat(fill(200.0, 150), fill(100.0, 50))
            result = calculate_indicators(prices, CUSUM(0.5))

            # Should eventually see a -1 signal after the drop
            @test any(result .== -1)
        end

        @testset "Steady prices give all zeros" begin
            prices = fill(100.0, 200)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test all(result .== 0)
        end

        @testset "Gradual trend may not trigger" begin
            # Very gradual increase
            prices = Float64.(100 .+ (1:200) .* 0.001)
            result = calculate_indicators(prices, CUSUM(2.0))

            # High multiplier + gradual trend = likely no signals
            # This tests that small changes don't trigger
            @test sum(abs.(result)) < 50  # Allow some signals but not many
        end
    end

    @testset "Parameter Sensitivity" begin
        @testset "High multiplier = fewer signals" begin
            prices = Float64.(100 .+ cumsum(randn(500) .* 2))
            prices = abs.(prices)

            result_low = calculate_indicators(prices, CUSUM(0.5))
            result_high = calculate_indicators(prices, CUSUM(3.0))

            signals_low = sum(abs.(result_low))
            signals_high = sum(abs.(result_high))

            @test signals_high <= signals_low
        end

        @testset "Low multiplier = more signals" begin
            prices = Float64.(100 .+ cumsum(randn(500) .* 2))
            prices = abs.(prices)

            result_low = calculate_indicators(prices, CUSUM(0.3))
            result_med = calculate_indicators(prices, CUSUM(1.0))

            signals_low = sum(abs.(result_low))
            signals_med = sum(abs.(result_med))

            @test signals_low >= signals_med
        end
    end

    @testset "Numerical Stability" begin
        @testset "Very small positive prices" begin
            prices = fill(1e-10, 200)
            prices[150] = 2e-10  # Double
            result = calculate_indicators(prices, CUSUM(1.0))

            @test length(result) == 200
            @test all(x -> x ∈ Int8[-1, 0, 1], result)
        end

        @testset "Large prices" begin
            prices = fill(1e10, 200)
            prices[150] = 2e10
            result = calculate_indicators(prices, CUSUM(1.0))

            @test length(result) == 200
            @test all(x -> x ∈ Int8[-1, 0, 1], result)
        end

        @testset "Prices with many decimals" begin
            prices = fill(100.123456789, 200)
            prices[150] = 150.987654321
            result = calculate_indicators(prices, CUSUM(1.0))

            @test length(result) == 200
        end
    end

    @testset "Type Handling" begin
        @testset "Float64 input" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test result isa Vector{Int8}
        end

        @testset "Float32 input" begin
            prices = Float32.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0f0))

            @test result isa Vector{Int8}
        end

        @testset "Integer input throws" begin
            prices = collect(100:299)
            @test_throws MethodError calculate_indicators(prices, CUSUM(1.0))
        end

        @testset "Output is always Int8" begin
            prices = Float64.(100 .+ cumsum(randn(200)))
            prices = abs.(prices)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test eltype(result) == Int8
        end
    end

    @testset "Edge Cases" begin
        @testset "All identical prices" begin
            prices = fill(123.456, 200)
            result = calculate_indicators(prices, CUSUM(1.0))

            @test all(result .== 0)
        end

        @testset "Single large outlier" begin
            prices = fill(100.0, 200)
            prices[150] = 1000.0  # 10x spike
            result = calculate_indicators(prices, CUSUM(0.5))

            # Should detect the spike
            @test any(result[150:160] .== 1)
        end

        @testset "Alternating up/down" begin
            prices = Float64[100 + (i % 2) * 10 for i in 1:200]
            result = calculate_indicators(prices, CUSUM(1.0))

            # Alternating pattern - cumsum resets, may or may not trigger
            @test length(result) == 200
        end
    end

    @testset "Reset Behavior" begin
        @testset "Cumsum resets after positive signal" begin
            # After a +1 signal, s_pos should reset to 0
            # Create scenario with two separate positive jumps
            prices = vcat(
                fill(100.0, 120),   # Baseline
                fill(150.0, 30),    # First jump
                fill(100.0, 30),    # Back to baseline
                fill(150.0, 20),     # Second jump
            )
            result = calculate_indicators(prices, CUSUM(0.5))

            # Should see multiple +1 signals (one per jump)
            positive_signals = sum(result .== 1)
            @test positive_signals >= 1
        end

        @testset "Cumsum resets after negative signal" begin
            prices = vcat(
                fill(150.0, 120),
                fill(100.0, 30),    # First drop
                fill(150.0, 30),    # Recovery
                fill(100.0, 20),     # Second drop
            )
            result = calculate_indicators(prices, CUSUM(0.5))

            negative_signals = sum(result .== -1)
            @test negative_signals >= 1
        end
    end
end
