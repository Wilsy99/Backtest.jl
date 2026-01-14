abstract type Indicator end

calculate_indicators!(df::DataFrame, indicators::EMA...)::DataFrame =
    _calculate_ema!(df, indicators...)