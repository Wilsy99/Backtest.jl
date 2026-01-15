abstract type Timeframe end
struct Daily <: Timeframe end
struct Weekly <: Timeframe end

const TIMEFRAMES = (D=Daily(), W=Weekly())

"""
    get_data(ticker::String, start_date::String, end_date::String)

Fetches historical stock data and adjusts OHLC values based on the adjustment factor.
Example: `get_data("AAPL", "2023-01-01", "2023-12-31")`
"""
function get_data(
    ticker::String;
    start_date::Union{Date,DateTime,AbstractString}="1900-01-01",
    end_date::Union{Date,DateTime,AbstractString}=today(),
    timeframe::String="D",
)::DataFrame
    return get_data(ticker, start_date, end_date, TIMEFRAMES[Symbol(timeframe)])
end

function get_data(
    ticker::String,
    start_date::Union{Date,DateTime,AbstractString},
    end_date::Union{Date,DateTime,AbstractString},
    timeframe::Daily,
)::DataFrame
    @chain get_prices(ticker, startdt=start_date, enddt=end_date) begin
        DataFrame()
        @rename!(:volume = :vol)
        @transform! @astable begin
            adj_factor = :adjclose ./ :close
            :open .= :open .* adj_factor
            :high .= :high .* adj_factor
            :low .= :low .* adj_factor
            :close .= :adjclose
        end
        @select!(Not(:adjclose))
        @orderby(:timestamp)
    end
end

function get_data(
    ticker::String,
    start_date::Union{Date,DateTime,AbstractString},
    end_date::Union{Date,DateTime,AbstractString},
    timeframe::Weekly,
)::DataFrame
    return transform_to_weekly!(get_data(ticker, start_date, end_date, Daily()))
end

"""
    transform_to_weekly(daily_df::DataFrame)

Aggregates daily OHLC data into weekly bars starting on first trading day of the week.
"""
function transform_to_weekly!(daily_df::DataFrame)::DataFrame
    @chain daily_df begin
        @transform!(:week_group = firstdayofweek.(:timestamp))
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
