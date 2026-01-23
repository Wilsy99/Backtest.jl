using YFinance, DataFrames, DataFramesMeta, Dates

abstract type Timeframe end
struct Daily <: Timeframe end
struct Weekly <: Timeframe end

function get_data(
    tickers::Union{AbstractString,AbstractVector{<:AbstractString}};
    start_date::Union{Date,DateTime,AbstractString}="1900-01-01",
    end_date::Union{Date,DateTime,AbstractString}=today(),
    timeframe::Timeframe=Daily(),
)::DataFrame
    return _get_data(tickers, start_date, end_date, timeframe)
end

function _get_data(tickers, start_date, end_date, ::Daily)::DataFrame
    raw_results = get_prices.(tickers, startdt=start_date, enddt=end_date, autoadjust=true)

    @chain vcat(DataFrame.(raw_results)...) begin
        vcat()
        @select!(Not(:close))
        @rename!(:close = :adjclose, :volume = :vol)
        @orderby(:ticker, :timestamp)
    end
end

function _get_data(tickers, start_date, end_date, ::Weekly)::DataFrame
    return transform_to_weekly(_get_data(tickers, start_date, end_date, Daily()))
end

function transform_to_weekly(daily_df::DataFrame)::DataFrame
    if isempty(daily_df)
        return daily_df
    end
    @chain daily_df begin
        @transform(:week_group = firstdayofweek.(:timestamp))
        @groupby(:ticker, :week_group)
        @combine(
            :timestamp = minimum(:timestamp),
            :open = first(:open),
            :high = maximum(:high),
            :low = minimum(:low),
            :close = last(:close),
            :volume = sum(:volume),
        )
        @select!(Not(:week_group))
        @orderby(:ticker, :timestamp)
    end
end