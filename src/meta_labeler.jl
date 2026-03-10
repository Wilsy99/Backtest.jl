struct MetaLabeler{M<:AbstractMLModel,CV<:AbstractCrossValidation}
    model::M
    cross_validation::CV
end

struct SingleSplitResults{M<:AbstractVector{Bool},T<:AbstractFloat}
    split_id::Int              # Which combinatoric split this is
    test_mask::M   # The exact chronological indices tested
    prob::Vector{T}               # P(bin==1) for these specific test_indices
    score::T                      # Validation score (e.g., log-loss) for this split
    purged_count::Int
    embargo_count::Int             # Diagnostics: How many rows were dropped?
end

struct MetaLabelResults{T<:AbstractFloat}
    # --- 1. CPCV Path Outputs (size = n_labels × n_paths) ---
    # Built by stitching together SingleSplitResultss along valid paths
    path_probs::Matrix{T}
    path_bet_sizes::Matrix{T}

    # --- 2. Consensus / Ensemble Outputs (length = n_labels) ---
    # Built by averaging overlapping predictions from SingleSplitResultss
    mean_prob::Vector{T}
    mean_bet_size::Vector{T}
    oos_counts::Vector{Int}

    # --- 3. Combinatorics & Diagnostics ---
    split_matrix::BitMatrix
    backtest_paths::Vector{Vector{Int}}
    mean_split_score::T                   # Average performance across all splits
end

function run(
    meta_labeler::MetaLabeler{<:Any,<:CPCV},
    labels::LabelResults,
    scoring_fn::F;
    multi_thread=false,
) where {F}
    cpcv = meta_labeler.cross_validation
    n_labels = length(labels)
    n_splits = cpcv.n_splits
    results_buf = Vector{SingleSplitResults}(undef, n_splits)

    n_adj = cpcv.n_groups - 1
    k_adj = cpcv.n_test_groups - 1
    total_paths = binomial(n_adj, k_adj)
    path_probs = Matrix{Float64}(undef, n_labels, total_paths)

    return _single_split_results!(
        meta_labeler.model,
        cpcv,
        labels,
        scoring_fn,
        n_labels,
        n_splits,
        cpcv.mask_type,
        results_buf,
        n_adj,
        k_adj,
        total_paths,
        path_probs,
        Val(multi_thread),
    )
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    n_splits::Int,
    mask_type::Type{<:AbstractVector{Bool}},
    results_buf::Vector{SingleSplitResults},
    n_adj::Int,
    k_adj::Int,
    total_paths::Int,
    path_probs::Matrix{T},
    Val{false},
) where {F,T<:AbstractFloat}
    cpcv_buf = CPCVBuffers(cpcv, n_labels, mask_type)

    @inbounds for split_num in 1:n_splits
        _reset!(cpcv_buf)
        _single_split_results!(
            model,
            cpcv,
            labels,
            scoring_fn,
            n_labels,
            cpcv_buf,
            results_buf,
            split_num,
            n_adj,
            k_adj,
            total_paths,
            path_probs,
        )
    end
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    n_splits::Int,
    mask_type::Type{<:AbstractVector{Bool}},
    results_buf::Vector{SingleSplitResults},
    n_adj::Int,
    k_adj::Int,
    total_paths::Int,
    path_probs::Matrix{T},
    ::Val{true},
) where {F,T<:AbstractFloat}
    nt = Threads.nthreads()
    cpcv_buf = [CPCVBuffers(cpcv, n_labels, mask_type) for _ in 1:nt]

    Threads.@threads :static for split_num in 1:n_splits
        cpcv_buf = cpcv_bufs[Threads.threadid()]
        _reset!(cpcv_buf)
        _single_split_results!(
            model,
            cpcv,
            labels,
            scoring_fn,
            n_labels,
            cpcv_buf,
            results_buf,
            split_num,
            n_adj,
            k_adj,
            total_paths,
            path_probs,
        )
    end
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    cpcv_buf::CPCVBuffers,
    results_buf::Vector{SingleSplitResults},
    split_num::Int,
    n_adj::Int,
    k_adj::Int,
    total_paths::Int,
    path_probs::Matrix{T},
) where {F,T<:AbstractFloat}
    cpcv_masks = _get_split_data_masks!(cpcv, labels, cpcv_buf, n_labels, split_num)
    mach = _train_model(model, labels, cpcv_masks.train)

    test_preds = _test_model(mach, labels, cpcv_masks.test)

    test_true = @view labels.bin[cpcv_masks.test]
    score = scoring_fn(test_true, test_preds)

    _fill_path_probs!(
        path_probs,
        cpcv,
        n_labels,
        n_adj,
        k_adj,
        total_paths,
        cpcv_buf.test_group_mask,
        test_preds,
    )

    return results_buf[split_num] = SingleSplitResults(
        split_num,
        cpcv_masks.test,
        test_preds,
        score,
        cpcv_masks.purged_count,
        cpcv_masks.embargo_count,
    )
end

function _train_model(
    model, labels::LabelResults, train_mask::M
) where {M<:AbstractVector{Bool}}
    train_feats = @view labels.feature[train_mask]
    train_bins = @view labels.bin[train_mask]
    train_weights = @view labels.weight[train_mask]
    mach = machine(model, train_feats, train_bins, train_weights)
    return fit!(mach)
end

@inline function _test_model(
    mach, labels::LabelResults, test_mask::M
) where {M<:AbstractVector{Bool}}
    test_feats = @view labels.feature[test_mask]
    return predict(mach, test_feats)
end

function _fill_path_probs!(
    path_probs::Matrix{T},
    cpcv::CPCV,
    n_labels::Int,
    n_adj::Int,
    k_adj::Int,
    total_paths::Int,
    test_group_mask::M,
    test_preds::AbstractVector{V},
) where {M<:AbstractVector{Bool},T<:AbstractFloat,V<:Real}
    test_preds_cur_idx = 1
    @inbounds for group in 1:(cpcv.n_groups)
        # Skip if this group isn't in the test set for this split
        test_group_mask[group] || continue

        # 1. Global row indices (i) for this group
        i = _get_group_idx_range(cpcv, n_labels, group)

        # 2. Global column index (j) for the path
        j = _get_path_id(cpcv.n_groups, n_adj, k_adj, total_paths, group, test_group_mask)

        # 3. Local range inside `test_preds` for this specific group
        group_len = length(i)
        test_preds_idx_rng = test_preds_cur_idx:(test_preds_cur_idx + group_len - 1)

        # 4. Safely assign the predictions in-place
        path_probs[i, j] .= @view test_preds[test_preds_idx_rng]

        # 5. Advance the pointer for the next active group
        test_preds_cur_idx += group_len
    end
end