using Backtest, Test, DataFrames, DataFramesMeta, Chain, Dates

const TEST_TICKER = "SPY"
const TEST_START = "2020-01-02"
const TEST_END = "2020-01-31"

@testset "get_data Tests" begin
    @testset "Schema & Structure" begin
        df = get_data(TEST_TICKER; start_date=TEST_START, end_date=TEST_END)
        @test df isa DataFrame
        @test Set(names(df)) ==
            Set(["ticker", "timestamp", "open", "high", "low", "close", "volume"])
        @test "adjclose" ∉ names(df)

        @test eltype(df.ticker) <: AbstractString
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

        @test all(df.high .>= max.(df.open, df.close) .- 1e-9)
        @test all(df.low .<= min.(df.open, df.close) .+ 1e-9)
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

        df_date = get_data(
            TEST_TICKER; start_date=Date(2020, 1, 2), end_date=Date(2020, 1, 10)
        )
        @test nrow(df_date) > 0

        df_datetime = get_data(
            TEST_TICKER; start_date=DateTime(2020, 1, 2), end_date=DateTime(2020, 1, 10)
        )
        @test nrow(df_datetime) > 0

        @test nrow(df_string) == nrow(df_date) == nrow(df_datetime)
    end

    @testset "Timeframe - Daily" begin
        df = get_data(
            TEST_TICKER; start_date=TEST_START, end_date=TEST_END, timeframe=Daily()
        )

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

        first_full_week = @chain daily_df begin
            @orderby(:timestamp)
            @transform(
                :week_group = firstdayofweek.(:timestamp),
                :day_of_week = dayofweek.(:timestamp)
            )
            @groupby(:week_group)
            @combine(
                :timestamp_start_of_week = first(:timestamp),
                :timestamp_end_of_week = last(:timestamp),
                :first_day_of_week = first(:day_of_week),
                :last_day_of_week = last(:day_of_week),
            )
            @subset(:first_day_of_week .== 1 .&& :last_day_of_week .== 5)
            first
        end

        daily_first_full_week_df = daily_df[
            (daily_df.timestamp) .>= first_full_week.timestamp_start_of_week .&& (daily_df.timestamp) .<= first_full_week.timestamp_end_of_week,
            :,
        ]

        weekly_first_full_week_df = weekly_df[
            (weekly_df.timestamp) .== first_full_week.timestamp_start_of_week, :,
        ]

        @test weekly_first_full_week_df.open[1] ≈ first(daily_first_full_week_df.open) atol =
            0.01

        @test weekly_first_full_week_df.high[1] ≈ maximum(daily_first_full_week_df.high) atol =
            0.01

        @test weekly_first_full_week_df.low[1] ≈ minimum(daily_first_full_week_df.low) atol =
            0.01

        @test weekly_first_full_week_df.close[1] ≈ last(daily_first_full_week_df.close) atol =
            0.01

        @test weekly_first_full_week_df.volume[1] ≈ sum(daily_first_full_week_df.volume) atol =
            0.01
    end

    @testset "Default Parameters" begin
        df = get_data(TEST_TICKER)
        @test df isa DataFrame
        @test nrow(df) > 0
    end
end

@testset "transform_to_weekly Tests" begin
    # Note: transform_to_weekly expects raw column names (adjclose, vol) not renamed ones (close, volume)
    # Output includes week_group column and is NOT sorted

    @testset "Basic weekly aggregation" begin
        daily_df = DataFrame(;
            ticker=fill("TEST", 10),
            timestamp=Date(2024, 1, 1) .+ Day.(0:9),
            open=Float64[100, 101, 102, 103, 104, 105, 106, 107, 108, 109],
            high=Float64[105, 106, 107, 108, 109, 110, 111, 112, 113, 114],
            low=Float64[95, 96, 97, 98, 99, 100, 101, 102, 103, 104],
            adjclose=Float64[102, 103, 104, 105, 106, 107, 108, 109, 110, 111],
            vol=[1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900],
        )

        weekly = transform_to_weekly(daily_df)

        @test weekly isa DataFrame
        @test nrow(weekly) < nrow(daily_df)
    end

    @testset "OHLCV aggregation logic" begin
        # One complete week: Mon-Fri (Jan 1 2024 is Monday)
        daily_df = DataFrame(;
            ticker=fill("TEST", 5),
            timestamp=[
                Date(2024, 1, 1),
                Date(2024, 1, 2),
                Date(2024, 1, 3),
                Date(2024, 1, 4),
                Date(2024, 1, 5),
            ],
            open=Float64[100, 102, 104, 103, 105],
            high=Float64[110, 112, 114, 113, 115],
            low=Float64[90, 92, 94, 93, 95],
            adjclose=Float64[102, 104, 103, 105, 108],
            vol=[1000, 1100, 1200, 1300, 1400],
        )

        weekly = transform_to_weekly(daily_df)

        @test nrow(weekly) == 1
        @test weekly.open[1] == 100.0          # First open
        @test weekly.high[1] == 115.0          # Max high
        @test weekly.low[1] == 90.0            # Min low
        @test weekly.adjclose[1] == 108.0      # Last adjclose
        @test weekly.vol[1] == 6000            # Sum of volumes
    end

    @testset "Empty DataFrame" begin
        empty_df = DataFrame(;
            ticker=String[],
            timestamp=Date[],
            open=Float64[],
            high=Float64[],
            low=Float64[],
            adjclose=Float64[],
            vol=Int[],
        )

        result = transform_to_weekly(empty_df)
        @test result isa DataFrame
        @test nrow(result) == 0
    end

    @testset "Single day" begin
        single_df = DataFrame(;
            ticker=["TEST"],
            timestamp=[Date(2024, 1, 1)],
            open=[100.0],
            high=[110.0],
            low=[90.0],
            adjclose=[105.0],
            vol=[1000],
        )

        weekly = transform_to_weekly(single_df)
        @test nrow(weekly) == 1
        @test weekly.open[1] == 100.0
        @test weekly.adjclose[1] == 105.0
    end

    @testset "Multi-ticker aggregation" begin
        daily_df = DataFrame(;
            ticker=["AAPL", "AAPL", "AAPL", "MSFT", "MSFT", "MSFT"],
            timestamp=repeat([Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)], 2),
            open=Float64[100, 101, 102, 200, 201, 202],
            high=Float64[110, 111, 112, 210, 211, 212],
            low=Float64[90, 91, 92, 190, 191, 192],
            adjclose=Float64[105, 106, 107, 205, 206, 207],
            vol=[1000, 1100, 1200, 2000, 2100, 2200],
        )

        weekly = transform_to_weekly(daily_df)

        @test nrow(weekly) == 2
        @test Set(weekly.ticker) == Set(["AAPL", "MSFT"])

        aapl = filter(r -> r.ticker == "AAPL", weekly)
        @test aapl.open[1] == 100.0
        @test aapl.adjclose[1] == 107.0
        @test aapl.vol[1] == 3300

        msft = filter(r -> r.ticker == "MSFT", weekly)
        @test msft.open[1] == 200.0
        @test msft.adjclose[1] == 207.0
        @test msft.vol[1] == 6300
    end

    @testset "Output schema" begin
        daily_df = DataFrame(;
            ticker=fill("TEST", 5),
            timestamp=Date(2024, 1, 1) .+ Day.(0:4),
            open=Float64[100, 101, 102, 103, 104],
            high=Float64[110, 111, 112, 113, 114],
            low=Float64[90, 91, 92, 93, 94],
            adjclose=Float64[105, 106, 107, 108, 109],
            vol=[1000, 1100, 1200, 1300, 1400],
        )

        weekly = transform_to_weekly(daily_df)

        # Output includes week_group column
        expected_cols = Set([
            "ticker", "timestamp", "open", "high", "low", "adjclose", "vol", "week_group"
        ])
        @test Set(names(weekly)) == expected_cols
    end

    @testset "Two days same week" begin
        two_day_df = DataFrame(;
            ticker=fill("TEST", 2),
            timestamp=[Date(2020, 1, 6), Date(2020, 1, 7)],  # Mon, Tue
            open=[100.0, 102.0],
            high=[105.0, 108.0],
            low=[95.0, 99.0],
            adjclose=[102.0, 106.0],
            vol=[1000, 1500],
        )
        result = transform_to_weekly(two_day_df)
        @test nrow(result) == 1
        @test result.open[1] == 100.0      # First open
        @test result.high[1] == 108.0      # Max high
        @test result.low[1] == 95.0        # Min low
        @test result.adjclose[1] == 106.0  # Last adjclose
        @test result.vol[1] == 2500        # Sum volume
    end

    @testset "Two separate weeks" begin
        two_week_df = DataFrame(;
            ticker=fill("TEST", 2),
            timestamp=[Date(2020, 1, 6), Date(2020, 1, 13)],  # Mon week 1, Mon week 2
            open=[100.0, 110.0],
            high=[105.0, 115.0],
            low=[95.0, 105.0],
            adjclose=[102.0, 112.0],
            vol=[1000, 2000],
        )
        result = transform_to_weekly(two_week_df)
        @test nrow(result) == 2
    end
end

@testset "Timeframe Types" begin
    @test Daily() isa Timeframe
    @test Weekly() isa Timeframe
    @test Daily <: Timeframe
    @test Weekly <: Timeframe
end
