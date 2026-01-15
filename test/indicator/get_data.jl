module TestGetData

using Backtest, Test, DataFrames, Dates

const TEST_TICKER = "SPY"
const TEST_START = "2020-01-02"
const TEST_END = "2020-01-31"

@testset "Schema & Structure" begin
    df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END)
    @test df isa DataFrame
    @test Set(names(df)) == Set(["timestamp", "open", "high", "low", "close", "volume"])
    @test "adjclose" ∉ names(df)

    @test eltype(df.timestamp) <: Union{Date,DateTime}
    @test eltype(df.open) <: AbstractFloat
    @test eltype(df.high) <: AbstractFloat
    @test eltype(df.low) <: AbstractFloat
    @test eltype(df.close) <: AbstractFloat
    @test eltype(df.volume) <: Real
end

@testset "Data Integrity" begin
    df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END)

    @test issorted(df.timestamp)

    @test length(unique(df.timestamp)) == nrow(df)

    @test all(df.high .>= max.(df.open, df.close))
    @test all(df.low .<= min.(df.open, df.close))
    @test all(df.high .>= df.low)

    @test all(df.volume .>= 0)

    @test !any(ismissing, df.timestamp)
    @test !any(isnan, df.open)
    @test !any(isnan, df.high)
    @test !any(isnan, df.low)
    @test !any(isnan, df.close)
end

@testset "Date Filtering" begin
    df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END)

    start_dt = Date(TEST_START)
    end_dt = Date(TEST_END)

    @test all(Date.(df.timestamp) .>= start_dt)
    @test all(Date.(df.timestamp) .<= end_dt)
end

end
