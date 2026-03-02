struct CPCV
    n_groups::Int
    n_test_groups::Int
    embargo::Int
    n_folds::Int

    function CPCV(n_groups::Int, n_test_groups::Int, embargo::Int)
        _natural(n_groups)
        _natural(n_test_groups)
        _natural(embargo)
        n_groups >= n_test_groups || throw(
            ArgumentError("n_groups ($n_groups) must be >= n_test_groups ($n_test_groups)"),
        )

        n_folds = binomial(n_groups, n_test_groups)

        return new(n_groups, n_test_groups, embargo, n_folds)
    end
end

function CPCV(embargo; n_groups=6, n_test_groups=2)
    return CPCV(n_groups, n_test_groups, embargo)
end

struct CPCVBuffers
    test_group_mask::BitVector
    train_data_mask::Vector{Bool}
    test_ranges::Vector{UnitRange{Int}}

    function CPCVBuffers(cpcv::CPCV, n_labels)
        return new(falses(cpcv.n_groups), ones(Bool, n_labels), UnitRange{Int}[])
    end
end

# ============================================================================
# Public API
# ============================================================================

function (cpcv::CPCV)(labels::LabelResults, fold_num::Int)
    return get_fold_train_data_mask(cpcv, labels, fold_num)
end

function get_fold_train_data_mask(cpcv::CPCV, labels::LabelResults, fold_num::Int)
    n_labels = length(labels)
    buf = CPCVBuffers(cpcv, n_labels)
    n_groups = cpcv.n_groups
    trade_idx_ranges = labels.trade_idx_range

    # 1. Unrank fold → test group mask
    _get_fold_test_group_mask!(buf.test_group_mask, cpcv, fold_num)

    # 2. Build test observation windows from test groups
    @inbounds for group_id in 1:n_groups
        buf.test_group_mask[group_id] || continue

        label_idx_range = _get_group_idx_range(cpcv, n_labels, group_id)
        trade_idx_range = @view trade_idx_ranges[label_idx_range]

        obs_start = minimum(r.start for r in trade_idx_range)
        obs_stop = maximum(r.stop for r in trade_idx_range)

        push!(buf.test_ranges, obs_start:obs_stop)
    end

    # 3. Merge test windows and extend embargo forward into sorted forbidden zones
    max_data_idx = maximum(r.stop for r in trade_idx_ranges)
    _merge_intervals_with_embargo!(buf.test_ranges, cpcv.embargo, max_data_idx)

    # 4. Single-pass sweep: both labels and forbidden intervals are sorted
    fi = 1
    n_forbidden = length(buf.test_ranges)

    @inbounds for i in 1:n_labels
        label_range = trade_idx_ranges[i]

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

    @inbounds for _ in 1:(cpcv.n_test_groups)
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

@inline function _get_group_idx_range(cpcv::CPCV, n_labels::Int, group_num::Int)
    base_len, rem = divrem(n_labels, cpcv.n_groups)

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

    @inbounds for i in 2:length(intervals)
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