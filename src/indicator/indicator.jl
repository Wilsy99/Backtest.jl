abstract type Indicator end

include("ema.jl")

calculate_indicators!(df::DataFrame, indicators::EMA...)::DataFrame =
    _calculate_ema!(df, indicators...)