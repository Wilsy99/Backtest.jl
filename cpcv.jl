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
    train_data_mask::BitVector
    test_ranges::Vector{UnitRange{Int}}

    function CPCVBuffers(cpcv::CPCV, n_data::Int)
        return new(falses(cpcv.n_groups), trues(n_data), UnitRange{Int}[])
    end
end

function reset!(buf::CPCVBuffers, n_groups::Int, n_data::Int)
    fill!(buf.test_group_mask, false)
    fill!(buf.train_data_mask, true)
    empty!(buf.test_ranges)
    # Ensure lengths are still correct (defensive)
    if length(buf.test_group_mask) != n_groups
        resize!(buf.test_group_mask, n_groups)
        fill!(buf.test_group_mask, false)
    end
    if length(buf.train_data_mask) != n_data
        resize!(buf.train_data_mask, n_data)
        fill!(buf.train_data_mask, true)
    end
    return nothing
end

@inline function _get_group_idx_range(cpcv::CPCV, group_num::Int)
    # Groups 1..remainder get (base_length + 1) labels
    # Groups (remainder+1)..n_groups get base_length labels
    base_len = cpcv.base_length
    rem = cpcv.remainder

    rem_used_before = min(group_num - 1, rem)
    start_idx = (group_num - 1) * base_len + rem_used_before + 1

    extra = group_num <= rem
    end_idx = start_idx + base_len + extra - 1

    return start_idx:end_idx
end

# ============================================================================
# Fold → Test Group Mask (Combinatorial Number System Unranking)
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

# Allocating convenience method
function _get_fold_test_group_mask(cpcv::CPCV, fold_num::Int)
    mask = falses(cpcv.n_groups)
    return _get_fold_test_group_mask!(mask, cpcv, fold_num)
end

# ============================================================================
# Interval Merging (with embargo extension)
# ============================================================================

"""
    _merge_intervals!(intervals, embargo, max_idx)

Sort `intervals` in-place, extend each by `embargo` on both sides (clamped to
[1, max_idx]), then merge overlapping intervals. Returns the mutated vector
containing only the merged result.
"""
function _merge_intervals!(intervals::Vector{UnitRange{Int}}, embargo::Int, max_idx::Int)
    isempty(intervals) && return intervals

    # Sort by start index
    sort!(intervals; by=r -> r.start)

    # Extend by embargo and merge in a single pass
    write_idx = 1
    merged_start = max(1, intervals[1].start - embargo)
    merged_stop = min(max_idx, intervals[1].stop + embargo)

    for i in 2:length(intervals)
        ext_start = max(1, intervals[i].start - embargo)
        ext_stop = min(max_idx, intervals[i].stop + embargo)

        if ext_start <= merged_stop + 1
            # Overlapping or adjacent — extend the current merged interval
            merged_stop = max(merged_stop, ext_stop)
        else
            # Gap — write out the previous merged interval and start a new one
            intervals[write_idx] = merged_start:merged_stop
            write_idx += 1
            merged_start = ext_start
            merged_stop = ext_stop
        end
    end

    # Write the final merged interval
    intervals[write_idx] = merged_start:merged_stop
    resize!(intervals, write_idx)

    return intervals
end

# ============================================================================
# Train Mask (Purge + Embargo via Sorted Sweep)
# ============================================================================

"""
    get_fold_train_data_mask!(buf, cpcv, fold_num, label_price_data_idx_ranges)

Compute the training mask for a given fold. Labels whose observation window
overlaps with any test group's observation window (extended by `embargo`) are
purged.

Uses a single O(n_labels) sweep over sorted forbidden intervals.

# Arguments
- `buf::CPCVBuffers`: preallocated workspace (mutated in-place)
- `cpcv::CPCV`: the CPCV configuration
- `fold_num::Int`: which fold (1-indexed)
- `label_price_data_idx_ranges::AbstractVector{UnitRange{Int}}`: for each label,
  the range of price data indices it depends on

# Returns
- `BitVector`: the train mask (view into `buf.train_data_mask`)
"""
function get_fold_train_data_mask!(
    buf::CPCVBuffers,
    cpcv::CPCV,
    fold_num::Int,
    label_price_data_idx_ranges::AbstractVector{UnitRange{Int}},
)
    n_labels = cpcv.n_labels
    n_groups = cpcv.n_groups

    reset!(buf, n_groups, n_labels)

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

    # 3. Merge test windows (with embargo extension) into sorted forbidden zones
    max_data_idx = maximum(r.stop for r in label_price_data_idx_ranges)
    _merge_intervals!(buf.test_ranges, cpcv.embargo, max_data_idx)

    # 4. Single-pass sweep: both labels and forbidden intervals are sorted
    fi = 1
    n_forbidden = length(buf.test_ranges)

    for i in 1:n_labels
        label_range = label_price_data_idx_ranges[i]

        # Advance past forbidden intervals that end before this label starts
        while fi <= n_forbidden && buf.test_ranges[fi].stop < label_range.start
            fi += 1
        end

        # Check overlap with current forbidden interval
        if fi <= n_forbidden && label_range.stop >= buf.test_ranges[fi].start
            buf.train_data_mask[i] = false
        end
    end

    return buf.train_data_mask
end

# Allocating convenience method
function get_fold_train_data_mask(
    cpcv::CPCV, fold_num::Int, label_price_data_idx_ranges::AbstractVector{UnitRange{Int}}
)
    n_data = if isempty(label_price_data_idx_ranges)
        0
    else
        maximum(r.stop for r in label_price_data_idx_ranges)
    end
    buf = CPCVBuffers(cpcv, n_data)
    return get_fold_train_data_mask!(buf, cpcv, fold_num, label_price_data_idx_ranges)
end