# ── Weights Functors ──

"""
    AttributionWeights{E<:AbstractExecutionBasis} <: AbstractWeights

Sample-weight functor that computes uniqueness-weighted attribution
weights with optional time decay and class-imbalance correction.

# Callable Signatures

- `(w::AttributionWeights)(d::NamedTuple) -> NamedTuple`: compute
    weights from `d.labels` and `d.bars`, return the input merged
    with `(; weights=Vector{T}(...))`.
- `(w::AttributionWeights)(labels::LabelResults, bars::PriceBars) -> Vector{T}`:
    compute and return the raw weight vector directly.

# Type Parameters
- `E<:AbstractExecutionBasis`: the execution basis type used during
    labelling.

# Fields
- `time_decay_start::Float64`: starting value for linear time decay.
    Ramps from this value to `1.0` across events in temporal order.
    `1.0` disables decay.
- `entry_basis::E`: execution basis used during labelling. Determines
    the exposure offset for attribution.

# Constructors
    AttributionWeights(; time_decay_start=1.0, entry_basis=NextOpen())

# Keywords
- `time_decay_start::Real = 1.0`: starting value for linear time
    decay (`1.0` disables decay).
- `entry_basis::AbstractExecutionBasis = NextOpen()`: execution basis
    used during labelling.

# Examples
```jldoctest
julia> using Backtest

julia> w = AttributionWeights();

julia> w isa AbstractWeights
true

julia> w.time_decay_start
1.0

julia> w_decay = AttributionWeights(time_decay_start=0.5);

julia> w_decay.time_decay_start
0.5
```

# Pipeline Data Flow

## Input (NamedTuple overload)
Expects a `NamedTuple` with at least:
- `labels::LabelResults`: from an upstream [`Label`](@ref).
- `bars::PriceBars`: the price data.

## Input (direct overload)
- `labels::LabelResults`: label results.
- `bars::PriceBars`: the price data.

## Output
- NamedTuple overload: return the input merged with
  `weights::Vector{T}`.
- Direct overload: return `Vector{T}` of sample weights.

In both cases `sum(weights) ≈ n` and each label class contributes
roughly equal total weight (class-imbalance correction).

# See also
- [`AbstractWeights`](@ref): parent abstract type.
- [`compute_weights`](@ref): the underlying computation function.
"""
struct AttributionWeights{E<:AbstractExecutionBasis} <: AbstractWeights
    time_decay_start::Float64
    entry_basis::E
end

function AttributionWeights(;
    time_decay_start::Real=1.0,
    entry_basis::AbstractExecutionBasis=NextOpen(),
)
    return AttributionWeights(float(time_decay_start), entry_basis)
end

function (w::AttributionWeights)(d::NamedTuple)
    weights = compute_weights(
        d.labels, d.bars;
        time_decay_start=w.time_decay_start,
        entry_basis=w.entry_basis,
    )
    return merge(d, (; weights=weights))
end

function (w::AttributionWeights)(labels::LabelResults, bars::PriceBars)
    return compute_weights(
        labels, bars;
        time_decay_start=w.time_decay_start,
        entry_basis=w.entry_basis,
    )
end

# ── Sample Weight Computation ──

"""
    compute_weights(labels::LabelResults, closes::AbstractVector{T}; kwargs...) -> Vector{T}
    compute_weights(labels::LabelResults, bars::PriceBars; kwargs...) -> Vector{T}

Compute sample weights for triple-barrier label results.

Weights are computed via uniqueness-weighted attribution returns,
optional linear time decay, and class-imbalance correction. This is
a post-processing step that operates on [`LabelResults`](@ref) and
the close price series used during labelling.

# Arguments
- `labels::LabelResults`: output from [`calculate_label`](@ref).
- `closes::AbstractVector{T}`: close price series (same series used
    for labelling).
- `bars::PriceBars`: alternatively pass the price bars directly.

# Keywords
- `time_decay_start::Real = 1.0`: starting value for linear time
    decay. Ramps from this value to `1.0` across events in temporal
    order. `1.0` disables decay.
- `entry_basis::AbstractExecutionBasis = NextOpen()`: execution basis
    used during labelling. Determines the exposure offset for
    attribution.

# Returns
- `Vector{T}`: sample weights with `sum(weights) ≈ n_labels`.
    Each label class contributes roughly equal total weight
    (class-imbalance correction).

# Examples
```jldoctest
julia> using Backtest, Dates

julia> n = 20;

julia> bars = PriceBars(
           [100.0 + 0.5i for i in 1:n],
           [102.0 + 0.5i for i in 1:n],
           [98.0 + 0.5i for i in 1:n],
           [101.0 + 0.5i for i in 1:n],
           fill(1000.0, n),
           [DateTime(2024, 1, 1) + Day(i-1) for i in 1:n],
           TimeBar(),
       );

julia> tb = TimeBarrier(d -> d.entry_ts + Day(3));

julia> labels = calculate_label([1, 5], bars, (tb,); side=zeros(Int8, n));

julia> w = compute_weights(labels, bars);

julia> length(w) == length(labels)
true

julia> sum(w) ≈ length(labels)
true
```

# See also
- [`AttributionWeights`](@ref): pipeline functor.
- [`LabelResults`](@ref): the input container.
- [`calculate_label`](@ref): produces label results.
"""
function compute_weights(
    labels::LabelResults,
    closes::AbstractVector{T};
    time_decay_start::Real=1.0,
    entry_basis::AbstractExecutionBasis=NextOpen(),
) where {T<:AbstractFloat}
    n_labels = length(labels)
    n_prices = length(closes)
    exposure_offset = _get_exposure_adj(entry_basis)

    entry_indices = [first(r) for r in labels.trade_idx_range]
    exit_indices = [last(r) for r in labels.trade_idx_range]

    return _attribution_weights(
        unique(labels.label),
        n_labels,
        n_prices,
        entry_indices,
        exit_indices,
        labels.label,
        closes,
        T(time_decay_start),
        exposure_offset,
    )
end

function compute_weights(
    labels::LabelResults,
    bars::PriceBars;
    kwargs...,
)
    return compute_weights(labels, bars.close; kwargs...)
end

# ── Internal ──

"""
    _attribution_weights(label_classes, n_labels, n_prices, entry_indices, exit_indices, labels, closes, time_decay_start, exposure_offset) -> Vector{T}

Compute sample weights via uniqueness-weighted attribution returns,
linear time decay, and class-imbalance correction.

The algorithm has three passes:
1. **Sweep-line attributed returns**: compute per-bar log returns
   weighted by `1/concurrency` where concurrency is the number of
   overlapping trades. Accumulated via `_cumulative_attributed_returns`.
2. **Time decay**: multiply each event's attribution weight by a
   linear ramp from `time_decay_start` to `1.0` across events in
   temporal order.
3. **Class-imbalance correction**: rebalance so each label class
   contributes equally to total weight, then normalise so
   `sum(weights) == n_labels`.
"""
@inline function _attribution_weights(
    label_classes::Vector{Int8},
    n_labels::Int,
    n_prices::Int,
    entry_indices::AbstractVector{Int},
    exit_indices::AbstractVector{Int},
    labels::AbstractVector{Int8},
    closes::AbstractVector{T},
    time_decay_start::T,
    exposure_offset::Int,
) where {T}
    weights = Vector{T}(undef, n_labels)
    n_labels == 0 && return weights

    n_label_classes = length(label_classes)

    # 1. Sweep-line cumulative attributed returns
    cum_attrib_rets = _cumulative_attributed_returns(
        n_prices, entry_indices, exit_indices, closes, exposure_offset, T
    )

    # 2. Linear time decay: ramps from time_decay_start → 1.0 across labels
    time_decay = time_decay_start
    time_decay_incr = n_labels > 1 ? (one(T) - time_decay_start) / T(n_labels - 1) : zero(T)

    classes_weights = zeros(T, n_label_classes)

    # ── Pass 1: Raw weight × decay, tallied per class ──
    @inbounds for i in 1:n_labels
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]
        label_number = findfirst(==(labels[i]), label_classes)

        start_lookup = entry_idx + exposure_offset
        weight =
            abs(cum_attrib_rets[exit_idx + 1] - cum_attrib_rets[start_lookup]) * time_decay

        weights[i] = weight
        classes_weights[label_number] += weight
        time_decay += time_decay_incr
    end

    # 3. Class imbalance correction
    total_decayed_weight = sum(classes_weights)
    target_class_weight = total_decayed_weight / n_label_classes

    class_multipliers = zeros(T, n_label_classes)
    for c in 1:n_label_classes
        class_multipliers[c] =
            classes_weights[c] > zero(T) ? target_class_weight / classes_weights[c] : one(T)
    end

    # ── Pass 2: Apply class balance & normalize so sum(weights) == n_labels ──
    sum_of_weights = zero(T)
    @inbounds for i in 1:n_labels
        label_number = findfirst(==(labels[i]), label_classes)
        weights[i] *= class_multipliers[label_number]
        sum_of_weights += weights[i]
    end

    if sum_of_weights > zero(T)
        norm_factor = T(n_labels) / sum_of_weights
        @inbounds for i in 1:n_labels
            weights[i] *= norm_factor
        end
    else
        fill!(weights, one(T))
    end

    return weights
end

"""
    _cumulative_attributed_returns(n_prices, entry_indices, exit_indices, closes, exposure_offset, ::Type{T}) -> Vector{T}

Compute a prefix-sum array of uniqueness-weighted log returns.

Use a sweep-line approach: increment a concurrency counter at each
entry and decrement at each exit. Each bar's log return is divided by
the number of concurrent trades to produce "attributed" returns. The
result is a cumulative sum array of length `n_prices + 1` where
`cum[t+1] - cum[s]` gives the total attributed return over bars
`s` through `t`.

The `+2` buffer on `concur_deltas` prevents out-of-bounds when
`exit_idx == n_prices`.
"""
@inline function _cumulative_attributed_returns(
    n_prices, entry_indices, exit_indices, closes, exposure_offset, ::Type{T}
) where {T}
    # +2 buffer: safely handles exit_idx + 1 decrement when exit_idx == n_prices
    # Int32 halves memory vs Int since this is sized to n_prices; concurrency
    # counts (overlapping trades per bar) won't approach the ~2.1B Int32 limit.
    concur_deltas = zeros(Int32, n_prices + 2)

    @inbounds for i in eachindex(entry_indices)
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]

        if entry_idx > 0 && exit_idx > 0
            start_idx = entry_idx + exposure_offset
            if start_idx <= n_prices
                concur_deltas[start_idx] += 1
                concur_deltas[exit_idx + 1] -= 1
            end
        end
    end

    # cum_attrib_rets[t+1] holds cumulative attributed return through bar t
    cum_attrib_rets = zeros(T, n_prices + 1)
    concur = 0
    current_cum_val = zero(T)

    @inbounds for t in 1:n_prices
        concur += concur_deltas[t]
        if t > 1
            bar_ret = log(closes[t] / closes[t - 1])
            if concur > 0
                current_cum_val += bar_ret / concur
            end
        end
        cum_attrib_rets[t + 1] = current_cum_val
    end

    return cum_attrib_rets
end
