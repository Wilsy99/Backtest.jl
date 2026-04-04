struct CPCV{M<:AbstractVector{Bool}} <: AbstractCrossValidation
    n_groups::Int
    n_test_groups::Int
    embargo::Int
    n_splits::Int
    n_paths::Int
    n_adj::Int
    k_adj::Int
    mask_type::Type{M}

    function CPCV(
        n_groups::Int,
        n_test_groups::Int,
        embargo::Int,
        mask_type::Type{M},
    ) where {M<:AbstractVector{Bool}}
        _natural(n_groups)
        _natural(n_test_groups)
        _natural(embargo)
        n_groups >= n_test_groups || throw(
            ArgumentError("n_groups ($n_groups) must be >= n_test_groups ($n_test_groups)"),
        )

        n_splits = binomial(n_groups, n_test_groups)

        n_adj = n_groups - 1
        k_adj = n_test_groups - 1
        n_paths = binomial(n_adj, k_adj)

        return new{M}(n_groups, n_test_groups, embargo, n_splits, n_paths, n_adj, k_adj, mask_type)
    end
end

function CPCV(embargo; n_groups=6, n_test_groups=2, mask_type::Type{<:AbstractVector{Bool}}=Vector{Bool})
    return CPCV(n_groups, n_test_groups, embargo, mask_type)
end

struct CPCVBuffers{T<:AbstractVector{Bool}}
    test_group_mask::BitVector
    test_data_mask::T
    train_data_mask::T
    test_ranges::Vector{UnitRange{Int}}
    purge_ranges::Vector{UnitRange{Int}}

    function CPCVBuffers(cpcv::CPCV, n_labels::Int, ::Type{Vector{Bool}})
        return new{Vector{Bool}}(
            falses(cpcv.n_groups),
            fill(true, n_labels),
            fill(true, n_labels),
            UnitRange{Int}[],
            UnitRange{Int}[],
        )
    end

    function CPCVBuffers(cpcv::CPCV, n_labels::Int, ::Type{BitVector})
        return new{BitVector}(
            falses(cpcv.n_groups),
            trues(n_labels),
            trues(n_labels),
            UnitRange{Int}[],
            UnitRange{Int}[],
        )
    end

    function CPCVBuffers(cpcv::CPCV, n_labels::Int)
        return CPCVBuffers(cpcv, n_labels, cpcv.mask_type)
    end
end

function _reset!(buf::CPCVBuffers)
    fill!(buf.test_group_mask, false)
    fill!(buf.test_data_mask, false)
    fill!(buf.train_data_mask, true)
    empty!(buf.test_ranges)
    empty!(buf.purge_ranges)
    return nothing
end

# ============================================================================
# Public API
# ============================================================================

function get_split_data_masks(cpcv::CPCV, labels::LabelResults, split_num::Int)
    n_labels = length(labels)
    buf = CPCVBuffers(cpcv, n_labels)
    return _get_split_data_masks!(cpcv, labels, buf, n_labels, split_num)
end

function get_path_id(cpcv::CPCV, split_num::Int, target_group::Int)
    test_group_mask = Vector{Bool}(undef, cpcv.n_groups)
    _get_split_test_group_mask!(test_group_mask, cpcv, split_num)

    if !test_group_mask[target_group]
        return 0
    end

    return _get_path_id(cpcv, target_group, test_group_mask)
end

# ============================================================================
# Internal
# ============================================================================

function _get_split_data_masks!(
    cpcv::CPCV, labels::LabelResults, buf::CPCVBuffers, n_labels::Int, split_num::Int
)

    # 1. Unrank split → test group mask
    _get_split_test_group_mask!(buf.test_group_mask, cpcv, split_num)

    # 2. Build test observation windows from test groups
    @inbounds for group_id in 1:(cpcv.n_groups)
        buf.test_group_mask[group_id] || continue

        label_idx_range = _get_group_idx_range(cpcv, n_labels, group_id)
        buf.test_data_mask[label_idx_range] .= true

        trade_idx_range = @view labels.trade_idx_ranges[label_idx_range]
        obs_start = minimum(r.start for r in trade_idx_range)
        obs_stop = maximum(r.stop for r in trade_idx_range)
        push!(buf.test_ranges, obs_start:obs_stop)
    end

    # 3. Merge test windows, then snapshot purge zones before embargo extension
    max_data_idx = maximum(r.stop for r in labels.trade_idx_ranges)
    _merge_intervals!(buf.test_ranges)

    # Snapshot: purge_ranges = merged test windows (no embargo)
    resize!(buf.purge_ranges, length(buf.test_ranges))
    copyto!(buf.purge_ranges, buf.test_ranges)

    # Extend test_ranges forward by embargo to create full forbidden zones
    _apply_embargo!(buf.test_ranges, cpcv.embargo, max_data_idx)

    # 4. Two-pointer sweep: classify each exclusion as purge or embargo
    embargo_count = 0
    purge_count = 0

    fi = 1
    pi = 1
    n_forbidden = length(buf.test_ranges)
    n_purge = length(buf.purge_ranges)

    @inbounds for i in 1:n_labels
        label_range = labels.trade_idx_ranges[i]

        while fi <= n_forbidden && buf.test_ranges[fi].stop < label_range.start
            fi += 1
        end

        if fi <= n_forbidden && label_range.stop >= buf.test_ranges[fi].start
            buf.train_data_mask[i] = false

            while pi <= n_purge && buf.purge_ranges[pi].stop < label_range.start
                pi += 1
            end

            if pi <= n_purge && label_range.stop >= buf.purge_ranges[pi].start
                purge_count += 1
            else
                embargo_count += 1
            end
        end
    end

    return (
        train=buf.train_data_mask,
        test=buf.test_data_mask,
        embargo_count=embargo_count,
        purge_count=purge_count,
    )
end

function _get_split_test_group_mask!(
    mask::M, cpcv::CPCV, split_num::Int
) where {M<:AbstractVector{Bool}}
    fill!(mask, false)

    n = cpcv.n_groups - 1
    k = cpcv.n_test_groups
    group_id = 1
    target_dist = cpcv.n_splits - split_num + 1

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
    _merge_intervals!(intervals)

Sort and merge overlapping/adjacent intervals in-place. No embargo extension.
"""
function _merge_intervals!(intervals::Vector{UnitRange{Int}})
    isempty(intervals) && return intervals

    sort!(intervals; by=r -> r.start)

    write_idx = 1
    merged_start = intervals[1].start
    merged_stop = intervals[1].stop

    @inbounds for i in 2:length(intervals)
        if intervals[i].start <= merged_stop + 1
            merged_stop = max(merged_stop, intervals[i].stop)
        else
            intervals[write_idx] = merged_start:merged_stop
            write_idx += 1
            merged_start = intervals[i].start
            merged_stop = intervals[i].stop
        end
    end

    intervals[write_idx] = merged_start:merged_stop
    resize!(intervals, write_idx)

    return intervals
end

"""
    _apply_embargo!(intervals, embargo, max_idx)

Extend each interval's stop forward by `embargo`, clamped to `max_idx`,
then re-merge any newly overlapping intervals in-place.
"""
function _apply_embargo!(intervals::Vector{UnitRange{Int}}, embargo::Int, max_idx::Int)
    isempty(intervals) && return intervals

    write_idx = 1
    merged_start = intervals[1].start
    merged_stop = min(max_idx, intervals[1].stop + embargo)

    @inbounds for i in 2:length(intervals)
        ext_stop = min(max_idx, intervals[i].stop + embargo)

        if intervals[i].start <= merged_stop + 1
            merged_stop = max(merged_stop, ext_stop)
        else
            intervals[write_idx] = merged_start:merged_stop
            write_idx += 1
            merged_start = intervals[i].start
            merged_stop = ext_stop
        end
    end

    intervals[write_idx] = merged_start:merged_stop
    resize!(intervals, write_idx)

    return intervals
end

function _get_path_id(cpcv::CPCV, target_group::Int, test_group_mask::AbstractVector{Bool})
    subtrahend = 0
    k_current = cpcv.k_adj

    for g in 1:(cpcv.n_groups)
        if test_group_mask[g] && g != target_group
            c_i = g < target_group ? g : g - 1

            subtrahend += binomial(cpcv.n_adj - c_i, k_current)
            k_current -= 1
        end
    end

    return cpcv.n_paths - subtrahend
end
