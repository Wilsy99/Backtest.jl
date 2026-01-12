using YFinance

export get_data

"""
    get_data(symbol::String, start_date::String, end_date::String)

Fetches historical stock data from Yahoo Finance.
Example: get_data("AAPL", "2023-01-01", "2023-12-31")
"""

function get_data(symbol::String, start_date::String, end_date::String)
    return get_prices(symbol, startdt=start_date, enddt=end_date)
end

