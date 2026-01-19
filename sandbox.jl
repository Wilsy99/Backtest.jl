using Pkg
Pkg.activate(".")

using Backtest, DataFrames, DataFramesMeta, Chain

daily_data = get_data("SPY")
weekly_data = get_data("SPY"; timeframe=Weekly())

daily_data_ema = @chain copy(daily_data) begin
    calculate_indicators!(ntuple(i -> EMA(i), 200)...)
end

cpcv_config = generate_config(
    daily_data_ema, TimeBar, CPCV(; n_groups=10, n_test_sets=2, max_trade=20, embargo=20)
)
