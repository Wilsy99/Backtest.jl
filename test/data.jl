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

@testset "Date Input Formats" begin
    df_string = get_data(TEST_TICKER; start_date="2020-01-02", end_date="2020-01-10")
    @test nrow(df_string) > 0

    df_date = get_data(TEST_TICKER; start_date=Date(2020, 1, 2), end_date=Date(2020, 1, 10))
    @test nrow(df_date) > 0

    df_datetime = get_data(
        TEST_TICKER; start_date=DateTime(2020, 1, 2), end_date=DateTime(2020, 1, 10)
    )
    @test nrow(df_datetime) > 0

    @test nrow(df_string) == nrow(df_date) == nrow(df_datetime)
end

@testset "Timeframe - Daily" begin
    df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily())

    @test 15 <= nrow(df) <= 25

    timestamps = sort(df.timestamp)
    gaps = diff(Date.(timestamps))
    @test all(g -> g <= Day(4), gaps)
end

@testset "Timeframe - Daily" begin
    df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily())

    @test 15 <= nrow(df) <= 25

    timestamps = sort(df.timestamp)
    gaps = diff(Date.(timestamps))
    @test all(g -> g <= Day(4), gaps)
end

@testset "Timeframe - Weekly" begin
    daily_df = get_data(
        TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily()
    )
    weekly_df = get_data(
        TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Weekly()
    )

    @test nrow(weekly_df) < nrow(daily_df)

    @test 3 <= nrow(weekly_df) <= 6

    @test all(weekly_df.high .>= max.(weekly_df.open, weekly_df.close))
    @test all(weekly_df.low .<= min.(weekly_df.open, weekly_df.close))
end

@testset "Weekly Aggregation Logic" begin
    daily_df = get_data(
        TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily()
    )
    weekly_df = get_data(
        TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Weekly()
    )

    first_week_start = minimum(weekly_df.timestamp)
    first_week_end = first_week_start + Day(6)
    first_week_daily = filter(
        row ->
            Date(row.timestamp) >= Date(first_week_start) &&
                Date(row.timestamp) <= Date(first_week_end),
        daily_df,
    )
    first_week_row = filter(row -> row.timestamp == first_week_start, weekly_df)

    @test first_week_row.open[1] ≈ first(first_week_daily.open) atol = 0.01

    @test first_week_row.high[1] ≈ maximum(first_week_daily.high) atol = 0.01

    @test first_week_row.low[1] ≈ minimum(first_week_daily.low) atol = 0.01

    @test first_week_row.close[1] ≈ last(first_week_daily.close) atol = 0.01

    @test first_week_row.volume[1] ≈ sum(first_week_daily.volume) rtol = 0.01
end

@testset "Default Parameters" begin
    df = get_data(TEST_TICKER)
    @test df isa DataFrame
    @test nrow(df) > 0
end

@testset "transform_to_weekly" begin
    daily_df = get_data(
        TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily()
    )
    weekly_df = transform_to_weekly(daily_df)

    @test nrow(weekly_df) < nrow(daily_df)
    @test Set(names(weekly_df)) ==
        Set(["timestamp", "open", "high", "low", "close", "volume"])
    @test issorted(weekly_df.timestamp)
end