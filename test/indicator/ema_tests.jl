using Backtest, Test, Dates

# Access internal functions for testing
const _sma_seed = Backtest._sma_seed
const _calculate_ema = Backtest._calculate_ema

"""
Naive scalar EMA for reference testing.
No optimizations — just the textbook recursive formula.
"""
function naive_ema(prices::Vector{T}, period::Int) where {T<:AbstractFloat}
    n = length(prices)
    result = fill(T(NaN), n)
    if period > n
        return result
    end
    result[period] = sum(prices[1:period]) / period
    α = T(2) / (period + 1)
    β = one(T) - α
    for i in (period + 1):n
        result[i] = α * prices[i] + β * result[i - 1]
    end
    return result
end

@testset "EMA Tests" begin

    # ── Construction & Validation ────────────────────────────────────────

    @testset "Construction & Validation" begin
        @testset "Valid construction" begin
            @test EMA(1) isa EMA{(1,)}
            @test EMA(5) isa EMA{(5,)}
            @test EMA(100) isa EMA{(100,)}
            @test EMA(5, 10) isa EMA{(5, 10)}
            @test EMA(1, 2, 3) isa EMA{(1, 2, 3)}
        end

        @testset "Invalid periods" begin
            @test_throws ArgumentError EMA(0)
            @test_throws ArgumentError EMA(-1)
            @test_throws ArgumentError EMA(-5)
            @test_throws ArgumentError EMA(5, 0, 10)
            @test_throws ArgumentError EMA(5, -1, 10)
            @test_throws ArgumentError EMA(-1, -2)
        end

        @testset "Non-integer types rejected" begin
            @test_throws MethodError EMA(3.5)
            @test_throws MethodError EMA(1.0)
        end

        @testset "Zero arguments — no periods" begin
            # EMA with no periods is meaningless and should be rejected
            @test_throws Exception EMA()
        end
    end

    # ── Mathematical Correctness ─────────────────────────────────────────

    @testset "Mathematical Correctness" begin
        @testset "Hand-calculated period=3" begin
            # α = 2/(3+1) = 0.5, β = 0.5
            prices = [1.0, 2.0, 3.0, 4.0, 5.0]
            result = calculate_indicator(EMA(3), prices)

            @test isnan(result[1])
            @test isnan(result[2])
            @test result[3] ≈ 2.0   # SMA(1,2,3) = 6/3
            @test result[4] ≈ 3.0   # 0.5×4 + 0.5×2.0
            @test result[5] ≈ 4.0   # 0.5×5 + 0.5×3.0
        end

        @testset "Hand-calculated period=2" begin
            # α = 2/3, β = 1/3
            prices = [1.0, 2.0, 3.0, 4.0, 5.0]
            result = calculate_indicator(EMA(2), prices)

            @test isnan(result[1])
            @test result[2] ≈ 1.5    # SMA(1,2)
            @test result[3] ≈ 2.5    # 2/3×3 + 1/3×1.5
            @test result[4] ≈ 3.5    # 2/3×4 + 1/3×2.5
            @test result[5] ≈ 4.5    # 2/3×5 + 1/3×3.5
        end

        @testset "Hand-calculated volatile series period=3" begin
            # α = 0.5, β = 0.5 — jagged prices to stress the calculation
            prices = [10.0, 11.0, 9.0, 13.0, 8.0, 15.0, 7.0, 14.0, 12.0, 6.0]
            result = calculate_indicator(EMA(3), prices)

            @test result[3] ≈ 10.0        # SMA(10,11,9)
            @test result[4] ≈ 11.5        # 0.5×13  + 0.5×10.0
            @test result[5] ≈ 9.75        # 0.5×8   + 0.5×11.5
            @test result[6] ≈ 12.375      # 0.5×15  + 0.5×9.75
            @test result[7] ≈ 9.6875      # 0.5×7   + 0.5×12.375
            @test result[8] ≈ 11.84375    # 0.5×14  + 0.5×9.6875
            @test result[9] ≈ 11.921875   # 0.5×12  + 0.5×11.84375
            @test result[10] ≈ 8.9609375   # 0.5×6   + 0.5×11.921875
        end
    end

    # ── SMA Seed ─────────────────────────────────────────────────────────

    @testset "SMA Seed" begin
        @testset "Seed equals mean of first p prices" begin
            prices = [10.0, 20.0, 30.0, 40.0, 50.0]

            result_p2 = calculate_indicator(EMA(2), prices)
            @test result_p2[2] ≈ (10.0 + 20.0) / 2

            result_p3 = calculate_indicator(EMA(3), prices)
            @test result_p3[3] ≈ (10.0 + 20.0 + 30.0) / 3

            result_p5 = calculate_indicator(EMA(5), prices)
            @test result_p5[5] ≈ (10.0 + 20.0 + 30.0 + 40.0 + 50.0) / 5
        end

        @testset "Internal _sma_seed" begin
            prices = [3.0, 7.0, 1.0, 9.0, 5.0]
            @test _sma_seed(prices, 1) ≈ 3.0
            @test _sma_seed(prices, 3) ≈ (3.0 + 7.0 + 1.0) / 3
            @test _sma_seed(prices, 5) ≈ (3.0 + 7.0 + 1.0 + 9.0 + 5.0) / 5
        end
    end

    # ── NaN Warmup Period ────────────────────────────────────────────────

    @testset "NaN Warmup Period" begin
        prices = collect(1.0:20.0)

        for period in [1, 2, 3, 5, 10]
            result = calculate_indicator(EMA(period), prices)

            # Exactly p-1 NaN values at the start
            nan_count = count(isnan, result)
            @test nan_count == period - 1

            # First p-1 positions are NaN
            for i in 1:(period - 1)
                @test isnan(result[i])
            end

            # Position p onward are all finite
            for i in period:length(prices)
                @test !isnan(result[i])
            end
        end
    end

    # ── Period = 1 (Identity) ────────────────────────────────────────────

    @testset "Period = 1 (Identity)" begin
        @testset "EMA(1) returns original prices" begin
            # α = 2/2 = 1.0, β = 0.0  →  EMA[i] = 1.0×price[i] + 0×prev
            prices = [5.0, 3.0, 8.0, 1.0, 9.0, 2.0, 7.0]
            result = calculate_indicator(EMA(1), prices)

            @test length(result) == length(prices)
            @test !any(isnan, result)
            for i in eachindex(prices)
                @test result[i] ≈ prices[i]
            end
        end

        @testset "Single element" begin
            result = calculate_indicator(EMA(1), [42.0])
            @test length(result) == 1
            @test result[1] ≈ 42.0
        end
    end

    # ── Edge Cases — Data Length ─────────────────────────────────────────

    @testset "Edge Cases — Data Length" begin
        @testset "Period > data length → all NaN" begin
            prices = [1.0, 2.0, 3.0]
            result = calculate_indicator(EMA(5), prices)
            @test length(result) == 3
            @test all(isnan, result)
        end

        @testset "Period == data length → one non-NaN (the SMA)" begin
            prices = [2.0, 4.0, 6.0, 8.0, 10.0]
            result = calculate_indicator(EMA(5), prices)
            @test count(!isnan, result) == 1
            @test result[5] ≈ sum(prices) / 5
        end

        @testset "Period == data length - 1 → two non-NaN values" begin
            prices = [1.0, 2.0, 3.0, 4.0, 5.0]
            result = calculate_indicator(EMA(4), prices)
            @test count(!isnan, result) == 2
            @test !isnan(result[4])
            @test !isnan(result[5])
        end

        @testset "Single element, period > 1 → all NaN" begin
            result = calculate_indicator(EMA(2), [99.0])
            @test length(result) == 1
            @test isnan(result[1])
        end

        @testset "Empty vector" begin
            result = calculate_indicator(EMA(3), Float64[])
            @test length(result) == 0
            @test result isa Vector{Float64}
        end
    end

    # ── Unrolled Kernel Consistency ──────────────────────────────────────

    @testset "Unrolled Kernel Consistency" begin
        # The optimized kernel processes 4 bars at a time.
        # Different data lengths hit different code paths:
        #   For period=2, kernel starts at i=3 and loops while i ≤ n-3
        #     n=6  → 1 chunk of 4, 0 scalar remainder
        #     n=7  → 1 chunk of 4, 1 scalar remainder
        #     n=8  → 1 chunk of 4, 2 scalar remainder
        #     n=9  → 1 chunk of 4, 3 scalar remainder
        #     n=10 → 2 chunks of 4, 0 scalar remainder
        #
        # We compare each against a naive reference implementation.

        prices_full = [
            10.0,
            7.0,
            13.0,
            5.0,
            11.0,
            8.0,
            14.0,
            3.0,
            12.0,
            6.0,
            9.0,
            15.0,
            4.0,
            11.0,
            7.0,
            13.0,
            2.0,
            10.0,
            8.0,
            16.0,
        ]

        for period in [2, 3, 5]
            for n in [
                period + 1,
                period + 3,
                period + 4,
                period + 5,
                period + 6,
                period + 7,
                period + 8,
                period + 12,
                20,
            ]
                n = min(n, length(prices_full))
                prices = prices_full[1:n]

                result = calculate_indicator(EMA(period), prices)
                reference = naive_ema(prices, period)

                @test length(result) == length(reference)
                for i in eachindex(result)
                    if isnan(reference[i])
                        @test isnan(result[i])
                    else
                        @test result[i] ≈ reference[i] atol = 1e-10
                    end
                end
            end
        end
    end

    # ── Constant Prices ──────────────────────────────────────────────────

    @testset "Constant Prices" begin
        for val in [0.0, 1.0, 100.0, -50.0]
            prices = fill(val, 20)
            for period in [1, 2, 5, 10]
                result = calculate_indicator(EMA(period), prices)
                for i in period:20
                    @test result[i] ≈ val atol = 1e-12
                end
            end
        end
    end

    # ── Monotonic Prices — EMA Lag Property ──────────────────────────────

    @testset "Monotonic Prices — EMA Lag Property" begin
        @testset "Increasing prices → EMA below price" begin
            prices = collect(1.0:0.5:20.0)
            for period in [3, 5, 10]
                result = calculate_indicator(EMA(period), prices)
                for i in (period + 1):length(prices)
                    @test result[i] < prices[i]
                end
            end
        end

        @testset "Decreasing prices → EMA above price" begin
            prices = collect(20.0:-0.5:1.0)
            for period in [3, 5, 10]
                result = calculate_indicator(EMA(period), prices)
                for i in (period + 1):length(prices)
                    @test result[i] > prices[i]
                end
            end
        end

        @testset "Longer period → more lag" begin
            prices = collect(1.0:1.0:50.0)
            ema_short = calculate_indicator(EMA(5), prices)
            ema_long = calculate_indicator(EMA(20), prices)

            # After both are warmed up, shorter EMA is closer to price
            for i in 21:50
                short_lag = prices[i] - ema_short[i]
                long_lag = prices[i] - ema_long[i]
                @test short_lag < long_lag
            end
        end
    end

    # ── Pathological Inputs ──────────────────────────────────────────────

    @testset "Pathological Inputs" begin
        @testset "NaN in prices propagates forward" begin
            prices = [1.0, 2.0, NaN, 4.0, 5.0, 6.0, 7.0, 8.0]
            result = calculate_indicator(EMA(2), prices)

            # Seed at position 2 is clean
            @test !isnan(result[2])
            # NaN at position 3 poisons every subsequent value (recursive)
            for i in 3:length(result)
                @test isnan(result[i])
            end
        end

        @testset "NaN in seed window" begin
            prices = [NaN, 2.0, 3.0, 4.0, 5.0]
            result = calculate_indicator(EMA(3), prices)

            # NaN in first 3 prices → SMA seed is NaN → everything NaN
            for i in 3:length(result)
                @test isnan(result[i])
            end
        end

        @testset "Inf in prices" begin
            prices = [1.0, 2.0, 3.0, Inf, 5.0, 6.0]
            result = calculate_indicator(EMA(2), prices)
            @test isinf(result[4]) || isnan(result[4])
        end

        @testset "Very large values — no overflow" begin
            prices = fill(1e300, 10)
            result = calculate_indicator(EMA(3), prices)
            for i in 3:10
                @test result[i] ≈ 1e300
                @test !isinf(result[i])
            end
        end

        @testset "Mixed positive and negative" begin
            prices = [10.0, -5.0, 3.0, -8.0, 7.0, -2.0, 4.0, -1.0, 6.0, -3.0]
            result = calculate_indicator(EMA(3), prices)
            reference = naive_ema(prices, 3)

            for i in 3:length(prices)
                @test result[i] ≈ reference[i] atol = 1e-10
            end
        end

        @testset "All zeros" begin
            prices = fill(0.0, 15)
            result = calculate_indicator(EMA(5), prices)
            for i in 5:15
                @test result[i] ≈ 0.0 atol = 1e-15
            end
        end
    end

    # ── Type Preservation ────────────────────────────────────────────────

    @testset "Type Preservation" begin
        @testset "Float64 in → Float64 out" begin
            result = calculate_indicator(EMA(2), Float64[1.0, 2.0, 3.0, 4.0, 5.0])
            @test eltype(result) == Float64
        end

        @testset "Float32 in → Float32 out" begin
            result = calculate_indicator(EMA(2), Float32[1.0, 2.0, 3.0, 4.0, 5.0])
            @test eltype(result) == Float32
        end

        @testset "Float32 values match Float64 values" begin
            prices_64 = Float64[10.0, 7.0, 13.0, 5.0, 11.0, 8.0, 14.0, 3.0]
            prices_32 = Float32.(prices_64)

            r64 = calculate_indicator(EMA(3), prices_64)
            r32 = calculate_indicator(EMA(3), prices_32)

            for i in 3:length(r64)
                @test r32[i] ≈ Float32(r64[i]) atol = 1e-5
            end
        end

        @testset "Integer input rejected" begin
            @test_throws MethodError calculate_indicator(EMA(2), [1, 2, 3, 4, 5])
        end
    end

    # ── Multiple EMAs ────────────────────────────────────────────────────

    @testset "Multiple EMAs" begin
        prices = [
            10.0,
            7.0,
            13.0,
            5.0,
            11.0,
            8.0,
            14.0,
            3.0,
            12.0,
            6.0,
            9.0,
            15.0,
            4.0,
            11.0,
            7.0,
            13.0,
            2.0,
            10.0,
            8.0,
            16.0,
        ]

        @testset "Multi-period matches independent single-period" begin
            single_5 = calculate_indicator(EMA(5), prices)
            single_10 = calculate_indicator(EMA(10), prices)
            multi = calculate_indicator(EMA(5, 10), prices)

            @test size(multi) == (length(prices), 2)

            for i in eachindex(single_5)
                if isnan(single_5[i])
                    @test isnan(multi[i, 1])
                else
                    @test multi[i, 1] ≈ single_5[i] atol = 1e-10
                end
            end

            for i in eachindex(single_10)
                if isnan(single_10[i])
                    @test isnan(multi[i, 2])
                else
                    @test multi[i, 2] ≈ single_10[i] atol = 1e-10
                end
            end
        end

        @testset "Three periods — dimensions" begin
            multi = calculate_indicator(EMA(3, 5, 10), prices)
            @test size(multi) == (20, 3)
        end

        @testset "Duplicate periods rejected at construction" begin
            @test_throws ArgumentError EMA(5, 5)
            @test_throws ArgumentError EMA(3, 10, 3)
        end
    end

    # ── Result Formatting ────────────────────────────────────────────────

    @testset "Result Formatting (_indicator_result)" begin
        @testset "Single period — field naming" begin
            prices = collect(1.0:10.0)
            result = Backtest._indicator_result(EMA(5), prices)

            @test result isa NamedTuple
            @test haskey(result, :ema_5)
            @test length(result.ema_5) == 10
        end

        @testset "Multiple period — field naming" begin
            prices = collect(1.0:20.0)
            result = Backtest._indicator_result(EMA(3, 7, 15), prices)

            @test result isa NamedTuple
            @test haskey(result, :ema_3)
            @test haskey(result, :ema_7)
            @test haskey(result, :ema_15)
        end

        @testset "Output length matches input length" begin
            for n in [5, 10, 50]
                prices = collect(1.0:Float64(n))
                result = calculate_indicator(EMA(3), prices)
                @test length(result) == n
            end
        end
    end

    # ── Pipeline Integration ─────────────────────────────────────────────

    @testset "Pipeline Integration" begin
        n = 30
        timestamps = [DateTime(2024, 1, 1) + Day(i) for i in 0:(n - 1)]
        close_prices = [100.0 + sin(i / 3.0) * 10 for i in 1:n]
        bars = PriceBars(
            close_prices,           # open
            close_prices .+ 1.0,    # high
            close_prices .- 1.0,    # low
            close_prices,           # close
            fill(1000.0, n),        # volume
            timestamps,
            TimeBar(),
        )

        @testset "Single EMA on PriceBars" begin
            result = EMA(5)(bars)

            @test result isa NamedTuple
            @test haskey(result, :bars)
            @test haskey(result, :ema_5)
            @test result.bars === bars
            @test length(result.ema_5) == n
        end

        @testset "Multiple EMA on PriceBars" begin
            result = EMA(5, 10)(bars)

            @test haskey(result, :bars)
            @test haskey(result, :ema_5)
            @test haskey(result, :ema_10)
        end

        @testset "EMA operates on close prices" begin
            result = EMA(5)(bars)
            direct = calculate_indicator(EMA(5), bars.close)

            for i in eachindex(direct)
                if isnan(direct[i])
                    @test isnan(result.ema_5[i])
                else
                    @test result.ema_5[i] ≈ direct[i]
                end
            end
        end

        @testset "Chaining EMAs on NamedTuple" begin
            first_result = EMA(5)(bars)
            second_result = EMA(10)(first_result)

            @test haskey(second_result, :bars)
            @test haskey(second_result, :ema_5)
            @test haskey(second_result, :ema_10)
        end
    end
end
