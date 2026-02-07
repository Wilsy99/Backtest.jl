using Backtest, Test

# Reference EMA implementation for verification
function reference_ema(prices::Vector{<:AbstractFloat}, period::Int)
    n = length(prices)
    T = eltype(prices)
    result = fill(T(NaN), n)
    if period > n
        return result
    end

    result[period] = sum(prices[1:period]) / period
    alpha = T(2) / (period + 1)

    for i in (period + 1):n
        result[i] = (prices[i] * alpha) + (result[i - 1] * (1 - alpha))
    end
    return result
end

@testset "EMACross Strategy" begin
    @testset "EMACross Constructor" begin
        @testset "Default parameters (long=true, short=false)" begin
            strategy = EMACross(EMA(5), EMA(10))
            @test strategy isa EMACross{true,false}
            @test strategy.fast_ema.period == 5
            @test strategy.slow_ema.period == 10
        end

        @testset "Explicit long=true, short=false" begin
            strategy = EMACross(EMA(5), EMA(10); long=true, short=false)
            @test strategy isa EMACross{true,false}
        end

        @testset "Fast period < slow period (allowed)" begin
            strategy = EMACross(EMA(5), EMA(10))
            @test strategy.fast_ema.period == 5
            @test strategy.slow_ema.period == 10
        end

        @testset "Fast period = slow period (not allowed)" begin
            @test_throws ArgumentError EMACross(EMA(5), EMA(5))
        end

        @testset "Fast period > slow period (not allowed)" begin
            @test_throws ArgumentError EMACross(EMA(10), EMA(5))
        end
    end

    @testset "calculate_strategy_sides - Return Type and Shape" begin
        @testset "Returns Vector{Int8}" begin
            prices = collect(100.0:110.0)
            strategy = EMACross(EMA(2), EMA(3))
            sides = calculate_strategy_sides(prices, strategy)

            @test sides isa Vector{Int8}
        end

        @testset "Output length equals input length" begin
            prices = collect(1.0:50.0)
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test length(sides) == length(prices)
        end

        @testset "Values are only 0 or 1 for long-only strategy" begin
            prices = 100.0 .+ 10.0 .* sin.(0.3 .* (1:100))
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test all(s -> s ∈ (Int8(0), Int8(1)), sides)
        end
    end

    @testset "calculate_strategy_sides - Short Input Edge Cases" begin
        @testset "Empty vector returns empty" begin
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(Float64[], strategy)

            @test sides == Int8[]
        end

        @testset "Single price returns zeros" begin
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides([100.0], strategy)

            @test sides == Int8[0]
        end

        @testset "Length < slow_ema.period returns all zeros" begin
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(ones(9), strategy)

            @test length(sides) == 9
            @test all(sides .== 0)
        end

        @testset "Length == slow_ema.period" begin
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(collect(1.0:10.0), strategy)

            @test length(sides) == 10
        end

        @testset "Length == slow_ema.period + 1" begin
            strategy = EMACross(EMA(5), EMA(10))
            prices = collect(1.0:11.0)
            sides = calculate_strategy_sides(prices, strategy)

            @test length(sides) == 11
        end
    end

    @testset "calculate_strategy_sides - Pre-Crossover Period" begin
        @testset "First slow_period - 1 bars are always zero" begin
            prices = collect(1.0:100.0)
            strategy = EMACross(EMA(5), EMA(20))
            sides = calculate_strategy_sides(prices, strategy)

            @test all(sides[1:19] .== 0)
        end

        @testset "Zeros before slow period for various periods" begin
            for slow_period in [5, 10, 15, 25]
                prices = collect(1.0:50.0)
                strategy = EMACross(EMA(3), EMA(slow_period))
                sides = calculate_strategy_sides(prices, strategy)

                @test all(sides[1:(slow_period - 1)] .== 0)
            end
        end
    end

    @testset "calculate_strategy_sides - Crossover Detection" begin
        @testset "No crossover when fast starts and stays above slow" begin
            # Exponential growth - fast EMA always leads slow EMA
            # Fast never goes below slow, so no crossover detected
            prices = exp.(0.05 .* (1:50))
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # No signal because fast never crossed from below
            @test all(sides .== 0)
        end

        @testset "Crossover detected after downtrend then uptrend" begin
            # Clear pattern: downtrend then uptrend guarantees crossover
            prices = [collect(100.0:-1.0:70.0); collect(70.0:1.0:110.0)]
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # Should have some 1s after crossover
            @test any(sides .== 1)

            # First signal should occur after slow period
            first_one = findfirst(==(Int8(1)), sides)
            @test first_one !== nothing
            @test first_one >= 10
        end

        @testset "Crossover requires fast to be below slow first" begin
            # Start with fast below slow (downtrend), then cross up
            prices = [collect(50.0:-0.5:30.0); collect(30.0:1.0:80.0)]
            strategy = EMACross(EMA(3), EMA(15))
            sides = calculate_strategy_sides(prices, strategy)

            # Verify crossover was detected
            @test any(sides .== 1)
        end
    end

    @testset "calculate_strategy_sides - Signal Behavior After Crossover" begin
        @testset "Signal tracks fast > slow condition after first crossover" begin
            # Oscillating prices that will cross multiple times
            prices = 100.0 .+ 15.0 .* sin.(0.2 .* (1:150))
            strategy = EMACross(EMA(3), EMA(15))
            sides = calculate_strategy_sides(prices, strategy)

            # Calculate EMAs for verification
            fast_vals = reference_ema(prices, 3)
            slow_vals = reference_ema(prices, 15)

            first_one = findfirst(==(Int8(1)), sides)
            if first_one !== nothing
                for i in first_one:length(sides)
                    expected = fast_vals[i] > slow_vals[i] ? Int8(1) : Int8(0)
                    @test sides[i] == expected
                end
            end
        end

        @testset "Signal becomes 0 when fast crosses back below slow" begin
            # Create prices that cross up then down
            prices = [
                collect(100.0:-1.0:80.0)   # Downtrend
                collect(80.0:2.0:120.0)    # Strong uptrend (cross up)
                collect(120.0:-1.5:70.0)   # Downtrend (cross down)
            ]
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # Should have both 0s and 1s after the initial crossover
            first_one = findfirst(==(Int8(1)), sides)
            if first_one !== nothing
                subsequent = sides[first_one:end]
                # After crossover, we should see signal go back to 0
                @test any(subsequent .== 0)
                @test any(subsequent .== 1)
            end
        end
    end

    @testset "calculate_strategy_sides - Constant Prices" begin
        @testset "Constant prices - EMAs equal, no signal" begin
            prices = fill(100.0, 50)
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # EMAs converge to same value, fast == slow, not >
            @test all(sides .== 0)
        end

        @testset "Nearly constant prices" begin
            prices = fill(100.0, 50)
            prices[25] = 100.001  # Tiny perturbation
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # Still should be mostly zeros
            @test sum(sides) <= 5  # At most a few 1s
        end
    end

    @testset "calculate_strategy_sides - Boundary Conditions" begin
        @testset "Fast equals slow exactly is not a cross (uses >)" begin
            prices = fill(100.0, 30)
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            # When fast == slow, condition is false (not >)
            @test all(sides .== 0)
        end

        @testset "Minimum periods (fast=1, slow=2)" begin
            prices = [10.0, 5.0, 15.0, 10.0, 20.0]
            strategy = EMACross(EMA(1), EMA(2))
            sides = calculate_strategy_sides(prices, strategy)

            @test length(sides) == 5
            @test sides isa Vector{Int8}
        end

        @testset "Large period difference" begin
            prices = collect(1.0:100.0)
            strategy = EMACross(EMA(3), EMA(50))
            sides = calculate_strategy_sides(prices, strategy)

            @test length(sides) == 100
            @test all(sides[1:49] .== 0)
        end
    end

    @testset "calculate_strategy_sides - Float Type Handling" begin
        @testset "Float64 input" begin
            prices = Float64.(collect(100.0:-0.5:50.0))
            prices = [prices; Float64.(collect(50.0:1.0:120.0))]
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test sides isa Vector{Int8}
            @test length(sides) == length(prices)
        end

        @testset "Float32 input" begin
            prices = Float32.(collect(100.0:-0.5:50.0))
            prices = [prices; Float32.(collect(50.0:1.0:120.0))]
            strategy = EMACross(EMA(3), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test sides isa Vector{Int8}
            @test length(sides) == length(prices)
        end
    end

    @testset "calculate_strategy_sides - Numerical Edge Cases" begin
        @testset "Large price values" begin
            prices = fill(1e10, 50)
            prices[1:25] .= 1e10 * 0.99
            prices[26:50] .= 1e10 * 1.01
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test sides isa Vector{Int8}
            @test !any(isnan, sides)
        end

        @testset "Small price values" begin
            prices = fill(1e-10, 50)
            prices[1:25] .= 1e-10 * 0.99
            prices[26:50] .= 1e-10 * 1.01
            strategy = EMACross(EMA(5), EMA(10))
            sides = calculate_strategy_sides(prices, strategy)

            @test sides isa Vector{Int8}
            @test !any(isnan, sides)
        end
    end

    @testset "calculate_strategy_sides - Manual Verification" begin
        @testset "Small dataset manual check" begin
            # Create a clear crossover scenario
            # Prices: downtrend then uptrend
            prices = Float64[100, 95, 90, 85, 80, 85, 90, 95, 100, 105, 110, 115, 120]
            strategy = EMACross(EMA(2), EMA(4))
            sides = calculate_strategy_sides(prices, strategy)

            # First 3 bars (before slow period 4) should be 0
            @test sides[1:3] == Int8[0, 0, 0]

            # Calculate EMAs manually
            fast_ema = reference_ema(prices, 2)
            slow_ema = reference_ema(prices, 4)

            # Verify the logic: find where fast goes below slow, then crosses above
            # After that point, sides should follow fast > slow
        end

        @testset "Verify crossover index is correct" begin
            # Construct prices where we know exactly when crossover happens
            prices = Float64[10, 9, 8, 7, 6, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
            strategy = EMACross(EMA(2), EMA(5))
            sides = calculate_strategy_sides(prices, strategy)

            fast_ema = reference_ema(prices, 2)
            slow_ema = reference_ema(prices, 5)

            # Find first actual crossover in EMAs
            first_cross = -1
            was_below = fast_ema[5] < slow_ema[5]
            for i in 6:length(prices)
                if was_below && fast_ema[i] > slow_ema[i]
                    first_cross = i
                    break
                elseif fast_ema[i] <= slow_ema[i]
                    was_below = true
                end
            end

            if first_cross != -1
                # Verify first 1 appears at crossover
                first_one = findfirst(==(Int8(1)), sides)
                @test first_one == first_cross
            end
        end
    end

    @testset "calculate_strategy_sides - Price Patterns" begin
        @testset "Monotonically increasing prices" begin
            prices = collect(1.0:0.5:100.0)
            strategy = EMACross(EMA(5), EMA(20))
            sides = calculate_strategy_sides(prices, strategy)

            # In pure uptrend, fast > slow after warmup
            # But need to check if fast was below slow first
            @test sides isa Vector{Int8}
        end

        @testset "Monotonically decreasing prices" begin
            prices = collect(100.0:-0.5:1.0)
            strategy = EMACross(EMA(5), EMA(20))
            sides = calculate_strategy_sides(prices, strategy)

            # In pure downtrend, fast < slow, no signal after any initial period
            # All zeros expected (fast always lags below)
            @test all(sides .== 0)
        end

        @testset "V-shaped recovery" begin
            prices = [collect(100.0:-2.0:50.0); collect(52.0:2.0:150.0)]
            strategy = EMACross(EMA(5), EMA(15))
            sides = calculate_strategy_sides(prices, strategy)

            # Should detect crossover during recovery
            @test any(sides .== 1)
        end

        @testset "Oscillating prices - multiple crosses" begin
            prices = 100.0 .+ 20.0 .* sin.(0.5 .* (1:80))
            strategy = EMACross(EMA(3), EMA(12))
            sides = calculate_strategy_sides(prices, strategy)

            # Should have both 0s and 1s due to oscillation
            @test any(sides .== 0)
            @test any(sides .== 1)
        end
    end

    @testset "calculate_strategy_sides - Unimplemented Strategy Variants" begin
        @testset "Long=false, Short=true throws MethodError" begin
            prices = collect(1.0:50.0)
            strategy = EMACross(EMA(5), EMA(10); long=false, short=true)

            @test_throws MethodError calculate_strategy_sides(prices, strategy)
        end

        @testset "Long=true, Short=true throws MethodError" begin
            prices = collect(1.0:50.0)
            strategy = EMACross(EMA(5), EMA(10); long=true, short=true)

            @test_throws MethodError calculate_strategy_sides(prices, strategy)
        end

        @testset "Long=false, Short=false throws MethodError" begin
            prices = collect(1.0:50.0)
            strategy = EMACross(EMA(5), EMA(10); long=false, short=false)

            @test_throws MethodError calculate_strategy_sides(prices, strategy)
        end
    end

    @testset "Internal Functions" begin
        @testset "_find_first_long_cross" begin
            # Create EMAs with known crossover
            fast = [5.0, 4.0, 3.0, 2.0, 3.0, 4.0, 5.0, 6.0]
            slow = [4.5, 4.4, 4.3, 4.2, 4.1, 4.0, 3.9, 3.8]
            # Fast starts above slow at idx 1, goes below, then crosses back above

            start_idx = 1
            cross_idx = Backtest._find_first_long_cross(fast, slow, start_idx)

            # Fast crosses above slow somewhere around idx 5-7
            @test cross_idx != -1
            @test fast[cross_idx] > slow[cross_idx]
            @test cross_idx > 1
        end

        @testset "_find_first_long_cross - no cross" begin
            # Fast always below slow
            fast = [1.0, 2.0, 3.0, 4.0, 5.0]
            slow = [10.0, 10.0, 10.0, 10.0, 10.0]

            cross_idx = Backtest._find_first_long_cross(fast, slow, 1)
            @test cross_idx == -1
        end

        @testset "_find_first_long_cross - immediate cross without being below" begin
            # Fast starts above slow and stays above
            fast = [10.0, 11.0, 12.0, 13.0, 14.0]
            slow = [5.0, 5.0, 5.0, 5.0, 5.0]

            cross_idx = Backtest._find_first_long_cross(fast, slow, 1)
            # Should return -1 because fast was never below slow
            @test cross_idx == -1
        end

        @testset "_fill_sides_generic!" begin
            sides = zeros(Int8, 10)
            condition = i -> i > 5

            Backtest._fill_sides_generic!(sides, 3, condition)

            @test sides[1:2] == Int8[0, 0]  # Before from_idx
            @test sides[3:5] == Int8[0, 0, 0]  # condition false
            @test sides[6:10] == Int8[1, 1, 1, 1, 1]  # condition true
        end
    end
end
