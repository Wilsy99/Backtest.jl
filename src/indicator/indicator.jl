abstract type Indicator end

struct EMA <: Indicator
    period::Int
    EMA(period) = new(_natural(period))
end

function calculate_indicators!(df::DataFrame, indicators::Indicator...)::DataFrame
    if isempty(df) || isempty(indicators)
        return df
    end

    if !hasproperty(df, :close)
        throw(ArgumentError("DataFrame must have a :close column"))
    end

    if !hasproperty(df, :timestamp)
        throw(ArgumentError("DataFrame must have a :timestamp column"))
    end

    if eltype(df.close) >: Missing && any(ismissing, df.close)
        throw(ArgumentError("Input 'close' column contains Missing values."))
    end

    if eltype(df.timestamp) >: Missing && any(ismissing, df.timestamp)
        throw(ArgumentError("Input 'timestamp' column contains Missing values."))
    end

    if nonmissingtype(eltype(df.close)) <: AbstractFloat && any(!isfinite, df.close)
        throw(ArgumentError("Input 'close' column contains NaN or Inf values."))
    end

    return _calculate_indicators!(df, indicators...)
end
_calculate_indicators!(df::DataFrame, indicators::EMA...)::DataFrame =
    _calculate_ema!(df, indicators...)