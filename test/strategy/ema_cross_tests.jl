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

@testset "Crossover Side" begin
    @testset "Constructor" begin
        @testset "Default parameters" begin
            c = Crossover(:fast, :slow)
            @test c isa Crossover{LongShort,:fast,:slow,true}
        end

        @testset "LongOnly direction" begin
            c = Crossover(:fast, :slow; direction=LongOnly)
            @test c isa Crossover{LongOnly,:fast,:slow,true}
        end

        @testset "ShortOnly direction" begin
            c = Crossover(:fast, :slow; direction=ShortOnly)
            @test c isa Crossover{ShortOnly,:fast,:slow,true}
        end

        @testset "wait_for_cross=false" begin
            c = Crossover(:fast, :slow; wait_for_cross=false)
            @test c isa Crossover{LongShort,:fast,:slow,false}
        end
    end

    @testset "calculate_side - Return Type and Shape" begin
        @testset "Returns Vector{Int8}" begin
            prices = collect(100.0:110.0)
            fast = reference_ema(prices, 2)
            slow = reference_ema(prices, 3)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test sides isa Vector{Int8}
        end

        @testset "Output length equals input length" begin
            prices = collect(1.0:50.0)
            fast = reference_ema(prices, 5)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test length(sides) == length(prices)
        end

        @testset "Values are only 0 or 1 for LongOnly" begin
            prices = 100.0 .+ 10.0 .* sin.(0.3 .* (1:100))
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test all(s -> s ∈ (Int8(0), Int8(1)), sides)
        end
    end

    @testset "calculate_side - Short Input Edge Cases" begin
        @testset "Empty vector returns empty" begin
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, Float64[], Float64[])
            @test sides == Int8[]
        end

        @testset "Single price returns zeros" begin
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, [100.0], [100.0])
            @test sides == Int8[0]
        end

        @testset "Length < slow period returns all zeros" begin
            prices = ones(9)
            fast = reference_ema(prices, 5)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test length(sides) == 9
            @test all(sides .== 0)
        end
    end

    @testset "calculate_side - Pre-Crossover Period" begin
        @testset "First slow_period - 1 bars are always zero" begin
            prices = collect(1.0:100.0)
            fast = reference_ema(prices, 5)
            slow = reference_ema(prices, 20)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test all(sides[1:19] .== 0)
        end
    end

    @testset "calculate_side - Crossover Fires Only at Transitions" begin
        @testset "Sustained uptrend produces only one signal at the cross" begin
            # Downtrend then strong sustained uptrend
            prices = [collect(100.0:-1.0:70.0); collect(70.0:1.0:130.0)]
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)

            # Should have exactly one signal for the single crossover
            @test sum(sides .== 1) == 1
        end

        @testset "Multiple oscillations produce one signal per upward cross" begin
            # Oscillating prices that cross multiple times
            prices = 100.0 .+ 15.0 .* sin.(0.2 .* (1:150))
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 15)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)

            # Count actual crossover points in the reference EMAs
            n_crosses = 0
            start = findfirst(!isnan, slow)
            # Find first cross (wait_for_cross=true)
            has_been_below = fast[start] <= slow[start]
            first_cross = -1
            for i in (start + 1):length(prices)
                if has_been_below && fast[i] > slow[i]
                    if first_cross == -1
                        first_cross = i
                    end
                    n_crosses += 1
                    has_been_below = false
                elseif fast[i] <= slow[i]
                    has_been_below = true
                end
            end

            @test sum(sides) == n_crosses
        end

        @testset "No crossover when fast starts and stays above slow" begin
            prices = exp.(0.05 .* (1:50))
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test all(sides .== 0)
        end

        @testset "Signal only at bar where fast crosses above slow" begin
            prices = Float64[10, 9, 8, 7, 6, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
            fast = reference_ema(prices, 2)
            slow = reference_ema(prices, 5)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)

            # Find actual cross in reference
            first_cross = -1
            was_below = fast[5] <= slow[5]
            for i in 6:length(prices)
                if was_below && fast[i] > slow[i]
                    first_cross = i
                    break
                elseif fast[i] <= slow[i]
                    was_below = true
                end
            end

            if first_cross != -1
                first_one = findfirst(==(Int8(1)), sides)
                @test first_one == first_cross
                # Should only have the one signal at the cross point
                # (subsequent bars where fast > slow should NOT be 1)
                @test sides[first_cross] == Int8(1)
                if first_cross < length(sides)
                    # Next bar should be 0 even if fast > slow (no new cross)
                    if fast[first_cross + 1] > slow[first_cross + 1]
                        @test sides[first_cross + 1] == Int8(0)
                    end
                end
            end
        end
    end

    @testset "calculate_side - LongShort Direction" begin
        @testset "Signals at both upward and downward crosses" begin
            prices = [collect(100.0:-1.0:70.0); collect(70.0:1.0:130.0); collect(130.0:-1.0:70.0)]
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongShort)
            sides = Backtest.calculate_side(c, fast, slow)

            @test any(sides .== 1)  # Should have upward cross
            @test any(sides .== -1)  # Should have downward cross
            # Most bars should be 0 (only transition points are non-zero)
            @test sum(sides .== 0) > length(sides) ÷ 2
        end

        @testset "Values are only -1, 0, or 1" begin
            prices = 100.0 .+ 10.0 .* sin.(0.3 .* (1:100))
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongShort)
            sides = Backtest.calculate_side(c, fast, slow)
            @test all(s -> s ∈ (Int8(-1), Int8(0), Int8(1)), sides)
        end
    end

    @testset "calculate_side - ShortOnly Direction" begin
        @testset "Signals only at downward crosses" begin
            prices = [collect(70.0:1.0:130.0); collect(130.0:-1.0:70.0)]
            fast = reference_ema(prices, 3)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=ShortOnly)
            sides = Backtest.calculate_side(c, fast, slow)

            @test any(sides .== -1)
            @test all(s -> s ∈ (Int8(-1), Int8(0)), sides)
        end
    end

    @testset "calculate_side - Constant Prices" begin
        @testset "Constant prices - no signal" begin
            prices = fill(100.0, 50)
            fast = reference_ema(prices, 5)
            slow = reference_ema(prices, 10)
            c = Crossover(:fast, :slow; direction=LongOnly)
            sides = Backtest.calculate_side(c, fast, slow)
            @test all(sides .== 0)
        end
    end

    @testset "Internal Functions" begin
        @testset "_find_first_cross LongOnly" begin
            fast = [5.0, 4.0, 3.0, 2.0, 3.0, 4.0, 5.0, 6.0]
            slow = [4.5, 4.4, 4.3, 4.2, 4.1, 4.0, 3.9, 3.8]

            cross_idx = Backtest._find_first_cross(fast, slow, 1, Val(LongOnly))
            @test cross_idx != -1
            @test fast[cross_idx] > slow[cross_idx]
            @test cross_idx > 1
        end

        @testset "_find_first_cross - no cross" begin
            fast = [1.0, 2.0, 3.0, 4.0, 5.0]
            slow = [10.0, 10.0, 10.0, 10.0, 10.0]

            cross_idx = Backtest._find_first_cross(fast, slow, 1, Val(LongOnly))
            @test cross_idx == -1
        end

        @testset "_find_first_cross - fast starts above, never below" begin
            fast = [10.0, 11.0, 12.0, 13.0, 14.0]
            slow = [5.0, 5.0, 5.0, 5.0, 5.0]

            cross_idx = Backtest._find_first_cross(fast, slow, 1, Val(LongOnly))
            @test cross_idx == -1
        end

        @testset "_fill_cross_transitions! LongOnly" begin
            sides = zeros(Int8, 10)
            # fast crosses above slow at index 4, stays above through 7, crosses back below at 8
            fast = [1.0, 1.0, 1.0, 5.0, 5.0, 5.0, 5.0, 1.0, 1.0, 5.0]
            slow = [3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0]

            Backtest._fill_cross_transitions!(sides, fast, slow, 1, Val(LongOnly))

            # No signal at 1-3 (fast below slow), signal at 4 (cross), no signal at 5-7 (still above but not a new cross)
            # No signal at 8-9 (fast below), signal at 10 (cross back up)
            @test sides == Int8[0, 0, 0, 1, 0, 0, 0, 0, 0, 1]
        end
    end
end
