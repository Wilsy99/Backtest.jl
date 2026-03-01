struct CPCV
    n_labels::Int
    n_groups::Int
    n_test_groups::Int
    embargo::Int
    n_folds::Int
    base_length::Int
    remainder::Int

    function CPCV(n_labels::Int, n_groups::Int, n_test_groups::Int, embargo::Int)
        _natural(n_labels)
        _natural(n_groups)
        _natural(n_test_groups)
        _nonnegative(embargo)
        n_groups >= n_test_groups || throw(
            ArgumentError("n_groups ($n_groups) must be >= n_test_groups ($n_test_groups)"),
        )

        n_folds = binomial(n_groups, n_test_groups)
        base_length, remainder = divrem(n_labels, n_groups)

        return new(
            n_labels, n_groups, n_test_groups, embargo, n_folds, base_length, remainder
        )
    end
end

function CPCV(n_labels, embargo; n_groups=6, n_test_groups=2)
    return CPCV(n_labels, n_groups, n_test_groups, embargo)
end

struct CPCVBuffers
    test_group_mask::BitVector
    train_data_mask::Vector{Bool}
    test_ranges::Vector{UnitRange{Int}}

    function CPCVBuffers(cpcv::CPCV)
        return new(falses(cpcv.n_groups), ones(Bool, cpcv.n_labels), UnitRange{Int}[])
    end
end

function _reset!(buf::CPCVBuffers)
    fill!(buf.test_group_mask, false)
    fill!(buf.train_data_mask, true)
    empty!(buf.test_ranges)
    return nothing
end

# ============================================================================
# Public API
# ============================================================================

function (cpcv::CPCV)(labels::LabelResults, fold_num::Int)
    return get_fold_train_data_mask(cpcv::CPCV, labels::LabelResults, fold_num)
end

function (e::Event)(d::NamedTuple)
    indices = calculate_event(e, d)
    return merge(d, (; event_indices=indices))
end

function get_fold_train_data_mask(cpcv::CPCV, labels::LabelResults, fold_num)
    buf = CPCVBuffers(cpcv)
    return get_fold_train_data_mask!(buf, cpcv, fold_num, labels.trade_idx_range)
end

function get_fold_train_data_mask!(
    buf::CPCVBuffers,
    cpcv::CPCV,
    fold_num::Int,
    label_price_data_idx_ranges::AbstractVector{UnitRange{Int}},
)
    n_labels = cpcv.n_labels
    n_groups = cpcv.n_groups

    @assert length(label_price_data_idx_ranges) == n_labels "Expected $n_labels label ranges, got $(length(label_price_data_idx_ranges))"

    @debug "Checking label ranges are sorted" let
        for i in 2:n_labels
            label_price_data_idx_ranges[i].start >=
            label_price_data_idx_ranges[i - 1].start || error(
                "label_price_data_idx_ranges is not sorted by start index at position $i",
            )
        end
    end

    _reset!(buf)

    # 1. Unrank fold → test group mask
    _get_fold_test_group_mask!(buf.test_group_mask, cpcv, fold_num)

    # 2. Build test observation windows from test groups
    for group_id in 1:n_groups
        buf.test_group_mask[group_id] || continue

        label_idx_range = _get_group_idx_range(cpcv, group_id)
        price_data_ranges = @view label_price_data_idx_ranges[label_idx_range]

        obs_start = minimum(r.start for r in price_data_ranges)
        obs_stop = maximum(r.stop for r in price_data_ranges)

        push!(buf.test_ranges, obs_start:obs_stop)
    end

    # 3. Merge test windows and extend embargo forward into sorted forbidden zones
    max_data_idx = maximum(r.stop for r in label_price_data_idx_ranges)
    _merge_intervals_with_embargo!(buf.test_ranges, cpcv.embargo, max_data_idx)

    # 4. Single-pass sweep: both labels and forbidden intervals are sorted
    fi = 1
    n_forbidden = length(buf.test_ranges)

    for i in 1:n_labels
        label_range = label_price_data_idx_ranges[i]

        while fi <= n_forbidden && buf.test_ranges[fi].stop < label_range.start
            fi += 1
        end

        if fi <= n_forbidden && label_range.stop >= buf.test_ranges[fi].start
            buf.train_data_mask[i] = false
        end
    end

    return buf.train_data_mask
end

# ============================================================================
# Internal
# ============================================================================

@inline function _get_fold_test_group_mask!(mask::BitVector, cpcv::CPCV, fold_num::Int)
    fill!(mask, false)

    n = cpcv.n_groups - 1
    k = cpcv.n_test_groups
    group_id = 1
    target_dist = cpcv.n_folds - fold_num + 1

    for _ in 1:(cpcv.n_test_groups)
        binom = binomial(n, k)

        while binom >= target_dist
            n -= 1
            group_id += 1
            binom = binomial(n, k)
        end

        mask[group_id] = true

        target_dist -= binom
        n -= 1
        group_id += 1
        k -= 1
    end

    return mask
end

function _get_fold_test_group_mask(cpcv::CPCV, fold_num::Int)
    mask = falses(cpcv.n_groups)
    return _get_fold_test_group_mask!(mask, cpcv, fold_num)
end

@inline function _get_group_idx_range(cpcv::CPCV, group_num::Int)
    base_len = cpcv.base_length
    rem = cpcv.remainder

    rem_used_before = min(group_num - 1, rem)
    start_idx = (group_num - 1) * base_len + rem_used_before + 1

    extra = group_num <= rem
    end_idx = start_idx + base_len + extra - 1

    return start_idx:end_idx
end

"""
    _merge_intervals_with_embargo!(intervals, embargo, max_idx)

Sort intervals, extend each **forward only** by `embargo` (the purge sweep
already catches backward leakage), then merge overlapping or adjacent intervals
in-place.
"""
function _merge_intervals_with_embargo!(
    intervals::Vector{UnitRange{Int}}, embargo::Int, max_idx::Int
)
    isempty(intervals) && return intervals

    sort!(intervals; by=r -> r.start)

    write_idx = 1
    merged_start = intervals[1].start
    merged_stop = min(max_idx, intervals[1].stop + embargo)

    for i in 2:length(intervals)
        ext_start = intervals[i].start
        ext_stop = min(max_idx, intervals[i].stop + embargo)

        if ext_start <= merged_stop + 1
            merged_stop = max(merged_stop, ext_stop)
        else
            intervals[write_idx] = merged_start:merged_stop
            write_idx += 1
            merged_start = ext_start
            merged_stop = ext_stop
        end
    end

    intervals[write_idx] = merged_start:merged_stop
    resize!(intervals, write_idx)

    return intervals
end