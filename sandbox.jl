using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain, BenchmarkTools

daily_data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
weekly_data = get_data("SPY"; timeframe=Weekly())

big_data = reduce(
    vcat, repeat([get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])], 50)
)

strategy = EMACross(EMA(10), EMA(20); long=true, short=false)

diff_series(x) = [i == 1 ? 0 : x[i] - x[i - 1] for i in eachindex(x)]

@chain daily_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    @transform(
        :side = calculate_sides(strategy, :close; wait_for_cross=false),
        :cusum = calculate_indicators(:close, CUSUM(1)),
    )
    @subset(:cusum .!= 0)
    @transform(:signal = diff_series(:side))
    @subset(:signal .== 1)
end

@btime @chain $big_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    combine(_) do gdf
        fast_ema_vals, slow_ema_vals = calculate_indicators(gdf.close, strategy)
        cusum = calculate_indicators(gdf.close, CUSUM(1))
        signals = calculate_signals(
            strategy, fast_ema_vals[cusum .!= 0], slow_ema_vals[cusum .!= 0]
        )
        event_indices = findall(x -> x != 0, signals)
        res = calculate_labels(
            event_indices,
            gdf.open,
            gdf.high,
            gdf.low,
            gdf.close,
            TripleBarrier(0.02, 0.01, 5),
        )
        DataFrame(;
            t₀_idx=res.event_indices,
            t₁_idx=res.t₁,
            label=res.label,
            log_return=res.log_return,
        )
    end
end

test = @chain weekly_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    combine(_) do gdf
        fast_ema_vals, slow_ema_vals = calculate_indicators(gdf.close, strategy)
        cusum = calculate_indicators(gdf.close, CUSUM(1))
        signals = calculate_signals(
            strategy, fast_ema_vals[cusum .!= 0], slow_ema_vals[cusum .!= 0]
        )
        event_indices = findall(x -> x != 0, signals)
        res = calculate_labels(
            TripleBarrier(0.3, 0.1, 100),
            event_indices,
            gdf.open,
            gdf.high,
            gdf.low,
            gdf.close,
        )
        DataFrame(;
            t₀_idx=res.event_indices,
            t₁_idx=res.t₁,
            label=res.label,
            log_return=res.log_return,
        )
    end
end