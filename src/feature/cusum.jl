"""
    CUSUM{T<:AbstractFloat} <: AbstractFeature

Cumulative Sum (CUSUM) filter for detecting structural breaks in a
price series.

Monitor the cumulative sum of log-returns against an adaptive
threshold derived from a rolling EMA of squared returns. When the
accumulator exceeds the threshold, a structural break is signalled
(`+1` for upward, `-1` for downward) and the accumulator resets.

# Type Parameters
- `T<:AbstractFloat`: numeric precision, matching the `multiplier`
    and `expected_value` types.

# Fields
- `multiplier::T`: scaling factor applied to the adaptive threshold.
    Higher values produce fewer signals.
- `span::Int`: lookback window for the EMA of squared returns.
- `expected_value::T`: assumed expected return, subtracted from
    log-returns before accumulation.

# Constructors
    CUSUM(multiplier::Real; span=100, expected_value=0.0)

# Throws
- `ArgumentError`: if `multiplier` is non-positive or `span` is not
    a positive integer.

# Examples
```jldoctest
julia> using Backtest

julia> cusum = CUSUM(1.0);

julia> typeof(cusum)
CUSUM{Float64}

julia> CUSUM(0.5; span=50) isa AbstractFeature
true
```

# See also
- [`EMA`](@ref): a smoothing feature (contrast with CUSUM's
    change-detection approach).
- [`calculate_feature`](@ref): the dispatch point for all features.

# Extended help

## Theory

The CUSUM filter (Page, 1954) monitors the cumulative sum of
log-returns against a threshold `h`. When the cumulative sum exceeds
`h`, a structural break is signalled and the accumulator resets.

The filter maintains two accumulators:
- `S⁺`: detects upward shifts (positive cumulative sum).
- `S⁻`: detects downward shifts (negative cumulative sum).

The threshold adapts over time using an EMA of squared log-returns
as a volatility estimate, scaled by `multiplier`.

## Warmup

The first 101 bars are used to initialise the EMA of squared
log-returns. No signals are produced during this warmup period. If
the input has 101 or fewer bars, a warning is emitted and all-zeros
are returned.

## References

- Page, E. S. (1954). "Continuous Inspection Schemes."
  *Biometrika*, 41(1/2), 100–115.
- De Prado, M. L. (2018). *Advances in Financial Machine Learning*.
  Chapter 2: CUSUM Filter.

## Callable Interface

`CUSUM` instances are callable. When called with [`PriceBars`](@ref)
or a `NamedTuple` from a previous pipeline stage, they compute the
CUSUM on `bars.close` and merge the result:

```julia
bars = get_data("AAPL")
result = CUSUM(1.0)(bars)
# result is a NamedTuple with fields :bars, :cusum
```
"""
struct CUSUM{T<:AbstractFloat} <: AbstractFeature
    multiplier::T
    span::Int
    expected_value::T

    function CUSUM{T}(m, s, e) where {T<:AbstractFloat}
        return new{T}(_positive_float(T(m)), _natural(Int(s)), T(e))
    end
end

function CUSUM(multiplier::Real; span=100, expected_value=0.0)
    T = typeof(float(multiplier))
    return CUSUM{T}(multiplier, span, expected_value)
end

"""
    calculate_feature(feat::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat} -> Vector{Int8}

Compute CUSUM filter signals for `prices`.

Return a `Vector{Int8}` of length `length(prices)` where each entry
is `Int8(1)` (upward break), `Int8(-1)` (downward break), or
`Int8(0)` (no signal). The first 101 entries are always zero
(warmup period).

# Arguments
- `feat::CUSUM`: the CUSUM feature instance.
- `prices::AbstractVector{T}`: price series. Must contain strictly
    positive values (log-returns require `log(price)`).

# Returns
- `Vector{Int8}`: signal vector. Values are in `{-1, 0, 1}`.

# Throws
- `DomainError`: if any price is negative (from `log`).

# Examples
```jldoctest
julia> using Backtest

julia> prices = vcat(fill(100.0, 101), [200.0]);

julia> vals = calculate_feature(CUSUM(1.0), prices);

julia> vals[102]
1
```

# See also
- [`CUSUM`](@ref): constructor and type documentation.
"""
function calculate_feature(feat::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat}
    return _calculate_cusum(prices, feat.multiplier, feat.span, feat.expected_value)
end

"""
    _feature_result(feat::CUSUM, prices) -> NamedTuple

Wrap the CUSUM output in a `NamedTuple` with key `:cusum` for
pipeline composition.
"""
function _feature_result(feat::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat}
    vals = calculate_feature(feat, prices)
    return (cusum=vals,)
end

"""
    _calculate_cusum(prices, multiplier, span, expected_value) -> Vector{Int8}

Core CUSUM computation. Allocate a result vector and run the
two-accumulator filter with adaptive volatility threshold.

The first 101 bars initialise the EMA of squared log-returns. Post-
warmup, each bar updates the positive and negative accumulators. When
either exceeds the adaptive threshold (`sqrt(ema_sq_mean) * mult`),
a signal is recorded and the accumulator resets.

Assume all prices are strictly positive (caller must validate).
"""
function _calculate_cusum(
    prices::AbstractVector{T}, multiplier::T, span::Int, expected_value::T
) where {T<:AbstractFloat}
    n = length(prices)
    cusum_values = zeros(Int8, n)

    warmup_idx = 101
    if n <= warmup_idx
        return _warn_and_return_zeros(n, warmup_idx)
    end

    α = T(2.0) / (T(span) + one(T))
    β = one(T) - α
    expected = expected_value
    mult = multiplier

    # ── Warmup: accumulate squared log-returns for volatility seed ──
    sum_sq_ret = zero(T)
    prev_log = log(prices[1])

    @inbounds for k in 2:warmup_idx
        curr_log = log(prices[k])
        sum_sq_ret += (curr_log - prev_log)^2
        prev_log = curr_log
    end

    ema_sq_mean = sum_sq_ret / T(warmup_idx - 1)
    s_pos = zero(T)
    s_neg = zero(T)

    # ── Post-warmup: detect structural breaks ──
    @inbounds for i in (warmup_idx + 1):n
        curr_log = log(prices[i])
        log_return = curr_log - prev_log
        prev_log = curr_log

        # Floor prevents sqrt(0) when prices are flat during warmup
        threshold = sqrt(max(T(1e-16), ema_sq_mean)) * mult

        s_pos = max(zero(T), s_pos + log_return - expected)
        s_neg = min(zero(T), s_neg + log_return + expected)

        ema_sq_mean = α * log_return^2 + β * ema_sq_mean

        if s_pos > threshold
            cusum_values[i] = 1
            s_pos = zero(T)
        elseif s_neg < -threshold
            cusum_values[i] = -1
            s_neg = zero(T)
        end
    end

    return cusum_values
end

"""Return zeros and warn when data is shorter than the warmup period"""
# This helper is marked @noinline and separated from the main loop to prevent 
# the compiler from allocating memory for the warning infrastructure (string 
# formatting, etc.) during the nominal execution path of `_calculate_cusum`.
@noinline function _warn_and_return_zeros(n, warmup_idx)
    @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
    return zeros(Int8, n)
end