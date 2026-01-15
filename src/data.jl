abstract type Timeframe end
struct Daily <: Timeframe end
struct Weekly <: Timeframe end

"""
    get_data(ticker::String, start_date::String, end_date::String)

Fetches historical stock data and adjusts OHLC values based on the adjustment factor.
Example: `get_data("AAPL", "2023-01-01", "2023-12-31")`
"""
function get_data(
    ticker::String;
    start_date::Union{Date,DateTime,AbstractString}="1900-01-01",
    end_date::Union{Date,DateTime,AbstractString}=today(),
    timeframe::Timeframe=Daily(),
)::DataFrame
    return _get_data(ticker, start_date, end_date, timeframe)
end

function _get_data(ticker, start_date, end_date, ::Daily)::DataFrame
    @chain get_prices(ticker, startdt=start_date, enddt=end_date, autoadjust=true) begin
        DataFrame()
        @select!(Not(:close))
        @rename!(:close = :adjclose, :volume = :vol)
        @orderby(:timestamp)
    end
end

function _get_data(ticker, start_date, end_date, ::Weekly)::DataFrame
    return transform_to_weekly(_get_data(ticker, start_date, end_date, Daily()))
end

"""
    transform_to_weekly(daily_df::DataFrame)

Aggregates daily OHLC data into weekly bars starting on first trading day of the week.
"""
function transform_to_weekly(daily_df::DataFrame)::DataFrame
    @chain daily_df begin
        @transform(:week_group = firstdayofweek.(:timestamp))
        @groupby(:week_group)
        @combine(
            :timestamp = minimum(:timestamp),
            :open = first(:open),
            :high = maximum(:high),
            :low = minimum(:low),
            :close = last(:close),
            :volume = sum(:volume),
        )
        @select!(Not(:week_group))
    end
end
