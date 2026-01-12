"""
    get_data(ticker::String, start_date::String, end_date::String)

Fetches historical stock data and adjusts OHLC values based on the adjustment factor.
Example: `get_data("AAPL", "2023-01-01", "2023-12-31")`
"""
function get_data(ticker::String, start_date::String, end_date::String)
    df = @chain get_prices(ticker, startdt=start_date, enddt=end_date) begin
        DataFrame()
        @transform @astable begin
            adj_factor = :adjclose ./ :close
            :open = :open .* adj_factor
            :high = :high .* adj_factor
            :low = :low .* adj_factor
            :close = :adjclose
        end
        @select(Not(:adjclose))
        @orderby(:timestamp) 
    end
    return df
end

"""
    transform_to_weekly(daily_df::DataFrame)

Aggregates daily OHLC data into weekly bars starting on Monday.
"""
function transform_to_weekly(daily_df::DataFrame)
    weekly_df = @chain daily_df begin
        @transform(:week_group = firstdayofweek.(:timestamp))
        @groupby(:week_group)
        @combine(
            :timestamp = minimum(:timestamp),
            :open = first(:open),
            :high = maximum(:high),
            :low = minimum(:low),
            :close = last(:close),
            :vol = sum(:vol)
        )
        @select(Not(:week_group)) # Optional: remove the helper column
    end
    return weekly_df
end