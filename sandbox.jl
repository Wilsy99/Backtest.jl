using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain, BenchmarkTools

daily_data = get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])
weekly_data = get_data("SPY"; timeframe=Weekly())

big_data = reduce(
    vcat, repeat([get_data(["SPY", "AAPL", "MSFT", "TSLA", "NVDA", "AMZN", "NFLX"])], 50)
)

strategy = EMACross(EMA(10), EMA(20); long=true, short=false)

@chain daily_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    @transform(
        :side = calculate_sides(strategy, :close; wait_for_cross=false),
        :cusum = calculate_indicators(:close, CUSUM(1)),
    )
    @subset(:cusum .!= 0)
    @groupby(:ticker)
    @transform(:signal = calculate_signals(:side))
    @groupby(:ticker)
    combine(_) do gdf
        event_indices = findall(x -> x == 1, gdf.signal)
        res = calculate_labels(
            TripleBarrier(0.02, 0.01, 5),
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

@chain daily_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    combine(_) do gdf
        fast_ema_vals, slow_ema_vals = calculate_indicators(strategy, gdf.close)
        cusum = calculate_indicators(gdf.close, CUSUM(1))

        # Get indices where cusum != 0
        valid_indices = findall(!=(0), cusum)

        # Calculate signals on filtered values
        signals = calculate_signals(
            strategy, fast_ema_vals[valid_indices], slow_ema_vals[valid_indices]
        )

        # Find events in the SHORT signals array
        event_positions_in_signals = findall(!=(0), signals)

        # Map back to ORIGINAL dataframe indices
        event_indices = valid_indices[event_positions_in_signals]

        # Now event_indices correctly refer to the full dataframe
        res = calculate_labels(
            TripleBarrier(0.02, 0.01, 5),
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

@chain weekly_data begin
    @select(:ticker, :timestamp, :open, :high, :low, :close)
    @groupby(:ticker)
    combine(_) do gdf
        fast_ema_vals, slow_ema_vals = calculate_indicators(strategy, gdf.close)
        cusum = calculate_indicators(gdf.close, CUSUM(1))

        # Get indices where cusum != 0
        valid_indices = findall(!=(0), cusum)

        # Calculate signals on filtered values
        signals = calculate_signals(
            strategy, fast_ema_vals[valid_indices], slow_ema_vals[valid_indices]
        )

        # Find events in the SHORT signals array
        event_positions_in_signals = findall(!=(0), signals)

        # Map back to ORIGINAL dataframe indices
        event_indices = valid_indices[event_positions_in_signals]

        # Now event_indices correctly refer to the full dataframe
        res = calculate_labels(
            TripleBarrier(0.02, 0.01, 5),
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

# Strategy is composed of indicators, tripple barrier etc
@chain data begin
    calculate_indicators(strategy, :close)
    calculate_events(strategy)
    calculate_signals(strategy)
    calculate_lables(strategy)
end

# Strategy also contains data
@chain strategy begin
    calculate_indicators(:close)
    calculate_events()
    calculate_signals()
    calculate_lables()
end

#each input is just the struct it dispatches on
@chain strategy begin
    calculate(indicators)
    calculate(events)
    calculate(signals)
    calculate(labels)
end