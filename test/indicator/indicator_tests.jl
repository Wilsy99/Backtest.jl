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

@testset "EMA Constructor" begin
    @testset "Valid periods" begin
        @test EMA(1).period == 1
        @test EMA(5).period == 5
        @test EMA(200).period == 200
    end

    @testset "Invalid periods - should throw" begin
        @test_throws ArgumentError EMA(0)
        @test_throws ArgumentError EMA(-1)
        @test_throws ArgumentError EMA(-100)
        @test_throws ArgumentError EMA(3.5)
        @test_throws ArgumentError EMA(1.5)
    end
end

@testset "Type Hierarchy" begin
    @test EMA <: Indicator
    @test EMA(5) isa Indicator
    @test Daily <: Timeframe
    @test Weekly <: Timeframe
    @test Daily() isa Timeframe
    @test Weekly() isa Timeframe
end

@testset "calculate_indicators! Validation" begin
    @testset "Empty DataFrame returns unchanged" begin
        empty_df = DataFrame(; timestamp=Date[], close=Float64[])
        result = calculate_indicators!(empty_df, EMA(5))
        @test result === empty_df
        @test nrow(result) == 0
    end

    @testset "No indicators returns unchanged" begin
        df = make_test_df(collect(1.0:10.0))
        original_cols = names(df)
        result = calculate_indicators!(df)
        @test result === df
        @test names(result) == original_cols
    end

    @testset "Missing :close column - should throw" begin
        df_no_close = DataFrame(;
            timestamp=Date(2020, 1, 1) .+ Day.(0:4),
            open=collect(1.0:5.0),
            high=collect(1.0:5.0),
            low=collect(1.0:5.0),
            volume=fill(1000, 5),
        )
        @test_throws ArgumentError calculate_indicators!(df_no_close, EMA(3))
    end

    @testset "Missing :timestamp column - should throw" begin
        df_no_timestamp = DataFrame(; close=collect(1.0:5.0), open=collect(1.0:5.0))
        @test_throws ArgumentError calculate_indicators!(df_no_timestamp, EMA(3))
    end

    @testset "Missing values in :close - should throw" begin
        df_missing_close = DataFrame(;
            timestamp=Date(2020, 1, 1) .+ Day.(0:4),
            close=Union{Float64,Missing}[1.0, missing, 3.0, 4.0, 5.0],
        )
        @test_throws ArgumentError calculate_indicators!(df_missing_close, EMA(3))
    end

    @testset "Missing values in :timestamp - should throw" begin
        df_missing_timestamp = DataFrame(;
            timestamp=Union{Date,Missing}[Date(2020, 1, 1), missing, Date(2020, 1, 3)],
            close=[1.0, 2.0, 3.0],
        )
        @test_throws ArgumentError calculate_indicators!(df_missing_timestamp, EMA(2))
    end

    @testset "NaN in :close - should throw" begin
        df_nan = DataFrame(;
            timestamp=Date(2020, 1, 1) .+ Day.(0:4), close=[1.0, NaN, 3.0, 4.0, 5.0]
        )
        @test_throws ArgumentError calculate_indicators!(df_nan, EMA(3))
    end

    @testset "Inf in :close - should throw" begin
        df_inf = DataFrame(;
            timestamp=Date(2020, 1, 1) .+ Day.(0:4), close=[1.0, Inf, 3.0, 4.0, 5.0]
        )
        @test_throws ArgumentError calculate_indicators!(df_inf, EMA(3))
    end

    @testset "-Inf in :close - should throw" begin
        df_neg_inf = DataFrame(;
            timestamp=Date(2020, 1, 1) .+ Day.(0:4), close=[1.0, -Inf, 3.0, 4.0, 5.0]
        )
        @test_throws ArgumentError calculate_indicators!(df_neg_inf, EMA(3))
    end
end
