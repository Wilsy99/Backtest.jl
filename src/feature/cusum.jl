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
- `field::Symbol`: the [`PriceBars`](@ref) field to compute on
    (default `:close`).

# Constructors
    CUSUM(multiplier::Real; span=100, expected_value=0.0, field::Symbol=:close)

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
- [`Features`](@ref): named collection for pipeline composition.
- [`compute`](@ref): standalone computation function.
- [`compute!`](@ref): in-place computation function.

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

The first `span + 1` bars initialise the EMA of squared
log-returns. No signals are produced during this warmup period. If
the input has `span + 1` or fewer bars, a warning is emitted and
all-zeros are returned.

## Callable Interface

`CUSUM` instances are callable. When called with [`PriceBars`](@ref),
they extract the target field and return the raw signal vector:

```julia
bars = get_data("AAPL")
signals = CUSUM(1.0)(bars)  # Vector{Int8}
```

To compose into a pipeline, wrap in [`Features`](@ref):

```julia
job = bars >> Features(:cusum => CUSUM(1.0)) >> event >> label
result = job()
result.features.cusum  # access the signal vector
```

## References

- Page, E. S. (1954). "Continuous Inspection Schemes."
  *Biometrika*, 41(1/2), 100–115.
- De Prado, M. L. (2018). *Advances in Financial Machine Learning*.
  Chapter 2: CUSUM Filter.
"""
struct CUSUM{T<:AbstractFloat} <: AbstractFeature
    multiplier::T
    span::Int
    expected_value::T
    field::Symbol

    function CUSUM{T}(m, s, e, f) where {T<:AbstractFloat}
        return new{T}(_positive_float(T(m)), _natural(Int(s)), T(e), f)
    end
end

function CUSUM(multiplier::Real; span=100, expected_value=0.0, field::Symbol=:close)
    T = typeof(float(multiplier))
    return CUSUM{T}(multiplier, span, expected_value, field)
end

function (feat::CUSUM)(bars::PriceBars)
    series = getproperty(bars, feat.field)
    return feat(series)
end

"""
    compute(feat::CUSUM, prices::AbstractVector{T}) where {T<:Real} -> Vector{Int8}

Compute CUSUM filter signals for `prices`.

Return a `Vector{Int8}` of length `length(prices)` where each entry
is `Int8(1)` (upward break), `Int8(-1)` (downward break), or
`Int8(0)` (no signal). The first `span + 1` entries are always zero
(warmup period).

# Arguments
- `feat::CUSUM`: the CUSUM feature instance.
- `prices::AbstractVector{T}`: price series. Must contain strictly
    positive values (log-returns require `log(price)`).

# Returns
- `Vector{Int8}`: signal vector. Values are in `{-1, 0, 1}`.

# Examples
```jldoctest
julia> using Backtest

julia> prices = vcat(fill(100.0, 11), [200.0]);

julia> vals = compute(CUSUM(1.0; span=10), prices);

julia> vals[12]
1
```

# See also
- [`CUSUM`](@ref): constructor and type documentation.
- [`compute!`](@ref): in-place version.
"""
function compute(feat::CUSUM, prices::AbstractVector{T}) where {T<:Real}
    return feat(prices)
end

function (feat::CUSUM)(x::AbstractVector{T}) where {T<:Real}
    n = length(x)
    warmup_idx = feat.span + 1
    if n <= warmup_idx
        return _warn_and_return_zeros(n, warmup_idx)
    end
    dest = zeros(Int8, n)
    _compute_cusum!(feat, dest, x, warmup_idx)
    return dest
end

"""
    compute!(dest::AbstractVector{Int8}, feat::CUSUM, prices::AbstractVector{T}) where {T<:AbstractFloat} -> dest

Compute CUSUM filter signals in-place, writing results into the
pre-allocated vector `dest`.

`dest` is first zeroed, then filled with signals (`Int8(1)`,
`Int8(-1)`, or `Int8(0)`).

# Arguments
- `dest::AbstractVector{Int8}`: output vector, same length as
    `prices`.
- `feat::CUSUM`: the CUSUM feature instance.
- `prices::AbstractVector{T}`: the input price series.

# Returns
- `dest`: the mutated output vector (returned for convenience).

# Throws
- `DimensionMismatch`: if `length(dest) != length(prices)`.

# See also
- [`compute`](@ref): allocating version.
- [`CUSUM`](@ref): constructor and type documentation.
"""
function compute!(
    dest::AbstractVector{Int8}, feat::CUSUM, prices::AbstractVector{T}
) where {T<:AbstractFloat}
    length(dest) == length(prices) ||
        throw(DimensionMismatch("dest length $(length(dest)) != prices length $(length(prices))"))
    fill!(dest, Int8(0))
    n = length(prices)
    warmup_idx = feat.span + 1
    if n <= warmup_idx
        return dest
    end
    _compute_cusum!(feat, dest, prices, warmup_idx)
    return dest
end

"""
    _compute_cusum!(feat, dest, x, warmup_idx) -> Nothing

In-place CUSUM computation. `dest` must be pre-zeroed and have
length `>= warmup_idx + 1`.

The first `warmup_idx` bars initialise the EMA of squared
log-returns. Post-warmup, each bar updates the positive and negative
accumulators. When either exceeds the adaptive threshold
(`sqrt(ema_sq_mean) * multiplier`), a signal is recorded and the
accumulator resets.
"""
function _compute_cusum!(
    feat::CUSUM, dest::AbstractVector{Int8}, x::AbstractVector{T}, warmup_idx::Int
) where {T<:Real}
    n = length(x)
    @fastmath @inbounds begin
        alpha = T(2.0) / (T(feat.span) + one(T))
        beta = one(T) - alpha

        # ── Warmup: accumulate squared log-returns for volatility seed ──
        sum_sq_ret = zero(T)
        prev_log = log(x[1])

        for k in 2:warmup_idx
            curr_log = log(x[k])
            sum_sq_ret += (curr_log - prev_log)^2
            prev_log = curr_log
        end

        ema_sq_mean = sum_sq_ret / T(warmup_idx - 1)
        s_pos = zero(T)
        s_neg = zero(T)

        for i in (warmup_idx + 1):n
            curr_log = log(x[i])
            log_return = curr_log - prev_log
            prev_log = curr_log

            # Floor prevents sqrt(0) when prices are flat during warmup
            threshold = sqrt(max(T(1e-16), ema_sq_mean)) * feat.multiplier

            s_pos = max(zero(T), s_pos + log_return - feat.expected_value)
            s_neg = min(zero(T), s_neg + log_return + feat.expected_value)

            if s_pos > threshold
                dest[i] = 1
                s_pos = zero(T)
            elseif s_neg < -threshold
                dest[i] = -1
                s_neg = zero(T)
            end

            ema_sq_mean = alpha * log_return^2 + beta * ema_sq_mean
        end
        return nothing
    end
end

# Separated from the hot path to prevent the compiler from allocating
# memory for warning infrastructure (string formatting) during nominal
# execution of `_compute_cusum!`.
"""Return zeros and warn when data is shorter than the warmup period."""
@noinline function _warn_and_return_zeros(n, warmup_idx)
    @warn "Data length ($n) is less than warmup ($warmup_idx). Returning zeros."
    return zeros(Int8, n)
end
