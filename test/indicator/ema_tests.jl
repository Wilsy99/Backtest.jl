using Backtest, Test, DataFrames, Dates

function make_test_df(closes::Vector{Float64})
    n = length(closes)
    return DataFrame(;
        ticker=fill("TEST", n),
        timestamp=Date(2020, 1, 1) .+ Day.(0:(n - 1)),
        open=closes,
        high=closes .+ 0.1,
        low=closes .- 0.1,
        close=closes,
        volume=fill(1000, n),
    )
end

function reference_ema(closes::Vector{Float64}, period::Int)
    n = length(closes)
    result = fill(NaN, n)
    if period > n
        return result
    end

    result[period] = sum(closes[1:period]) / period
    alpha = 2.0 / (period + 1)

    for i in (period + 1):n
        result[i] = (closes[i] * alpha) + (result[i - 1] * (1 - alpha))
    end
    return result
end

@testset "EMA Tests" begin
    @testset "Schema & Structure" begin
        df = make_test_df(collect(1.0:20.0))
        result = calculate_indicators!(df, EMA(5))

        @test result isa DataFrame
        @test "ema_5" ∈ names(result)
        @test eltype(result.ema_5) == Float64

        @test Set(["ticker", "timestamp", "open", "high", "low", "close", "volume"]) ⊆
            Set(names(result))
    end

    @testset "Column Naming" begin
        df = make_test_df(collect(1.0:20.0))
        result = calculate_indicators!(df, EMA(3), EMA(10), EMA(15))

        @test "ema_3" ∈ names(result)
        @test "ema_10" ∈ names(result)
        @test "ema_15" ∈ names(result)
    end

    @testset "NaN Placement" begin
        df = make_test_df(collect(1.0:20.0))
        result = calculate_indicators!(df, EMA(5))

        @test all(isnan.(result.ema_5[1:4]))
        @test !any(isnan.(result.ema_5[5:end]))
    end

    @testset "SMA Seed Correctness" begin
        closes = collect(1.0:10.0)
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(5))

        expected_sma = sum(closes[1:5]) / 5
        @test result.ema_5[5] ≈ expected_sma atol = 1e-10
    end

    @testset "EMA Formula Verification" begin
        closes = [10.0, 11.0, 12.0, 11.5, 13.0, 12.5, 14.0, 13.5, 15.0, 14.5]
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(3))

        expected = reference_ema(closes, 3)

        for i in 3:length(closes)
            @test result.ema_3[i] ≈ expected[i] atol = 1e-10
        end
    end

    @testset "Period = 1 Edge Case" begin
        closes = [5.0, 10.0, 15.0, 20.0, 25.0]
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(1))

        for i in eachindex(closes)
            @test result.ema_1[i] ≈ closes[i] atol = 1e-10
        end
    end

    @testset "Period > n_rows" begin
        closes = collect(1.0:5.0)
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(10))

        @test all(isnan.(result.ema_10))
    end

    @testset "Period = n_rows" begin
        closes = collect(1.0:5.0)
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(5))

        @test all(isnan.(result.ema_5[1:4]))
        @test result.ema_5[5] ≈ sum(closes) / 5 atol = 1e-10
    end

    @testset "Single Row Dataset" begin
        df = make_test_df([100.0])
        result = calculate_indicators!(df, EMA(1))

        @test result.ema_1[1] ≈ 100.0 atol = 1e-10
    end

    @testset "Unrolling Remainder Tests" begin
        # Test datasets where (n_rows - period) % 4 equals 0, 1, 2, 3
        # to verify the cleanup loop handles all remainder cases

        period = 3

        @testset "Remainder 0: (n-p) % 4 == 0" begin
            closes = collect(1.0:11.0)
            df = make_test_df(closes)
            result = calculate_indicators!(df, EMA(period))
            expected = reference_ema(closes, period)

            for i in period:length(closes)
                @test result.ema_3[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 1: (n-p) % 4 == 1" begin
            closes = collect(1.0:12.0)
            df = make_test_df(closes)
            result = calculate_indicators!(df, EMA(period))
            expected = reference_ema(closes, period)

            for i in period:length(closes)
                @test result.ema_3[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 2: (n-p) % 4 == 2" begin
            closes = collect(1.0:13.0)
            df = make_test_df(closes)
            result = calculate_indicators!(df, EMA(period))
            expected = reference_ema(closes, period)

            for i in period:length(closes)
                @test result.ema_3[i] ≈ expected[i] atol = 1e-10
            end
        end

        @testset "Remainder 3: (n-p) % 4 == 3" begin
            closes = collect(1.0:14.0)
            df = make_test_df(closes)
            result = calculate_indicators!(df, EMA(period))
            expected = reference_ema(closes, period)

            for i in period:length(closes)
                @test result.ema_3[i] ≈ expected[i] atol = 1e-10
            end
        end
    end

    @testset "Multiple Indicators Simultaneously" begin
        closes = collect(1.0:50.0)
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(5), EMA(10), EMA(20))

        expected_5 = reference_ema(closes, 5)
        expected_10 = reference_ema(closes, 10)
        expected_20 = reference_ema(closes, 20)

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

    @testset "EMA Bounded by Data Range" begin
        closes = [10.0, 15.0, 8.0, 20.0, 12.0, 18.0, 9.0, 14.0, 11.0, 16.0]
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(3))

        min_close = minimum(closes)
        max_close = maximum(closes)

        for i in 3:length(closes)
            @test min_close <= result.ema_3[i] <= max_close
        end
    end
end

@testset "Constant Prices" begin
    closes = fill(50.0, 20)
    df = make_test_df(closes)
    result = calculate_indicators!(df, EMA(5))

    # EMA of constant values should equal that constant
    for i in 5:20
        @test result.ema_5[i] ≈ 50.0 atol = 1e-10
    end
end

@testset "Monotonic Increasing Data" begin
    closes = collect(1.0:20.0)
    df = make_test_df(closes)
    result = calculate_indicators!(df, EMA(5))

    # For increasing data, EMA should lag below close (except at seed)
    for i in 6:20
        @test result.ema_5[i] < closes[i]
    end

    # EMA itself should be monotonically increasing
    for i in 6:20
        @test result.ema_5[i] > result.ema_5[i - 1]
    end
end

@testset "Monotonic Decreasing Data" begin
    closes = collect(20.0:-1.0:1.0)
    df = make_test_df(closes)
    result = calculate_indicators!(df, EMA(5))

    # For decreasing data, EMA should lag above close (except at seed)
    for i in 6:20
        @test result.ema_5[i] > closes[i]
    end

    # EMA itself should be monotonically decreasing
    for i in 6:20
        @test result.ema_5[i] < result.ema_5[i - 1]
    end
end

@testset "Type Coercion - Float32 Input" begin
    closes_f32 = Float32[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    df = DataFrame(;
        ticker=fill("TEST", 10),
        timestamp=Date(2020, 1, 1) .+ Day.(0:9),
        open=closes_f32,
        high=closes_f32 .+ 0.1f0,
        low=closes_f32 .- 0.1f0,
        close=closes_f32,
        volume=fill(1000, 10),
    )
    result = calculate_indicators!(df, EMA(3))

    @test eltype(result.ema_3) == Float64
    expected = reference_ema(Float64.(closes_f32), 3)
    for i in 3:10
        @test result.ema_3[i] ≈ expected[i] atol = 1e-6
    end

    @testset "Type Coercion - Integer Input" begin
        closes_int = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        df = DataFrame(;
            ticker=fill("TEST", 10),
            timestamp=Date(2020, 1, 1) .+ Day.(0:9),
            open=closes_int,
            high=closes_int .+ 1,
            low=closes_int .- 1,
            close=closes_int,
            volume=fill(1000, 10),
        )
        result = calculate_indicators!(df, EMA(3))

        @test eltype(result.ema_3) == Float64
        expected = reference_ema(Float64.(closes_int), 3)
        for i in 3:10
            @test result.ema_3[i] ≈ expected[i] atol = 1e-10
        end
    end

    @testset "Large Values - No Overflow" begin
        closes = fill(1e15, 20)
        closes[10] = 1.1e15
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(5))

        @test !any(isinf.(result.ema_5[5:end]))
        @test !any(isnan.(result.ema_5[5:end]))
    end

    @testset "Small Values - No Underflow" begin
        closes = fill(1e-15, 20)
        closes[10] = 1.1e-15
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(5))

        @test !any(isinf.(result.ema_5[5:end]))
        @test !any(isnan.(result.ema_5[5:end]))
        @test all(result.ema_5[5:end] .> 0)
    end

    @testset "Minimum Viable Dataset" begin
        # Period=2 with 3 rows - smallest useful case
        closes = [10.0, 20.0, 30.0]
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(2))

        expected = reference_ema(closes, 2)

        @test isnan(result.ema_2[1])
        @test result.ema_2[2] ≈ expected[2] atol = 1e-10
        @test result.ema_2[3] ≈ expected[3] atol = 1e-10
    end

    @testset "Longer Period EMA" begin
        closes = collect(1.0:100.0)
        df = make_test_df(closes)
        result = calculate_indicators!(df, EMA(50))

        expected = reference_ema(closes, 50)

        @test all(isnan.(result.ema_50[1:49]))
        for i in 50:100
            @test result.ema_50[i] ≈ expected[i] atol = 1e-9
        end
    end

    @testset "Many Indicators at Once" begin
        closes = collect(1.0:200.0)
        df = make_test_df(closes)

        indicators = ntuple(i -> EMA(i), 50)
        result = calculate_indicators!(df, indicators...)

        for period in [1, 10, 25, 50]
            expected = reference_ema(closes, period)
            col_name = "ema_$period"
            for i in period:200
                @test result[!, col_name][i] ≈ expected[i] atol = 1e-9
            end
        end
    end
end