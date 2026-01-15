abstract type Indicator end

struct EMA <: Indicator
    period::Int
end

calculate_indicators!(df::DataFrame, indicators::EMA...)::DataFrame =
    _calculate_ema!(df, indicators...)