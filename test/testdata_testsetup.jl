@testsetup module TestData
using Dates, Backtest

function make_pricebars(;
    n::Int=200,
    start_price::Float64=100.0,
    start_date::DateTime=DateTime(2024, 1, 1),
    volatility::Float64=2.0,
)
    timestamps = [start_date + Day(i - 1) for i in 1:n]
    close = [start_price + 0.05 * i + volatility * sin(2π * i / 20) for i in 1:n]

    # Guard against negative prices — the trend term (0.05 * i) grows slowly
    # relative to the sine amplitude (volatility).
    close = max.(close, 0.01)

    open = vcat([start_price], close[1:(end - 1)])
    spread = [0.5 + 0.3 * abs(sin(0.7 * i)) for i in 1:n]
    high = max.(open, close) .+ spread
    low = min.(open, close) .- spread
    volume = [1000.0 + 100.0 * abs(sin(0.3 * i)) for i in 1:n]
    return PriceBars(open, high, low, close, volume, timestamps, TimeBar())
end

function make_trending_prices(
    direction::Symbol; n::Int=100, start::Float64=100.0, step::Float64=0.5
)
    if direction === :up
        return [start + step * i for i in 0:(n - 1)]
    elseif direction === :down
        return [start - step * i for i in 0:(n - 1)]
    else
        error("direction must be :up or :down")
    end
end

make_flat_prices(; n::Int=200, price::Float64=100.0) = fill(price, n)

function make_step_prices(;
    n::Int=200, low::Float64=100.0, high::Float64=120.0, step_at::Int=101
)
    prices = Vector{Float64}(undef, n)
    prices[1:(step_at - 1)] .= low
    prices[step_at:end] .= high
    return prices
end
end
