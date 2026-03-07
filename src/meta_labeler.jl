struct MetaLabeler{M<:AbstractMLModel,CV<:AbstractCrossValidation}
    model::M
    cross_validation::CV
end

struct SingleSplitResult{M<:AbstractVector{Bool},T<:AbstractFloat}
    split_id::Int                 # Which combinatoric split this is
    test_mask::M   # The exact chronological indices tested
    prob::Vector{T}               # P(bin==1) for these specific test_indices
    score::T                      # Validation score (e.g., log-loss) for this split
    purged_count::Int
    embargo_count::Int             # Diagnostics: How many rows were dropped?
end

struct MetaLabelResults{T<:AbstractFloat}
    # --- 1. CPCV Path Outputs (size = n_labels × n_paths) ---
    # Built by stitching together SingleSplitResults along valid paths
    path_probs::Matrix{T}
    path_bet_sizes::Matrix{T}

    # --- 2. Consensus / Ensemble Outputs (length = n_labels) ---
    # Built by averaging overlapping predictions from SingleSplitResults
    mean_prob::Vector{T}
    mean_bet_size::Vector{T}
    oos_counts::Vector{Int}

    # --- 3. Combinatorics & Diagnostics ---
    split_matrix::BitMatrix
    backtest_paths::Vector{Vector{Int}}
    mean_split_score::T                   # Average performance across all splits
end

function (meta_labeler::MetaLabeler)(labels::LabelResults; multi_thread=false)
    results = run(meta_labeler, labels; multi_thread)

    return (; meta_labeler_results=results)
end

function (meta_labeler::MetaLabeler)(d::NamedTuple; multi_thread=false)
    labels = d.labels
    results = run(meta_labeler, labels; multi_thread)

    return merge(d, (; meta_labeler_results=results))
end

function run(
    meta_labeler::Union{MetaLabeler{<:Any,<:CPCV},MetaLabeler!{<:Any,<:CPCV}},
    labels,
    scoring_fn::Function;
    multi_thread=false,
)
    model = meta_labeler.model
    cpcv = meta_labeler.cross_validation
    n_labels = length(labels)
    n_splits = cpcv.n_splits
    mask_type = cpcv.mask_type
    results_buf = Vector{SingleSplitResult}(undef, n_splits)

    return single_split_results = _single_split_results!(
        model,
        cpcv,
        labels,
        scoring_fn,
        n_labels,
        n_splits,
        mask_type,
        results_buf,
        Val(multi_thread),
    )
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels,
    scoring_fn,
    n_labels,
    n_splits,
    mask_type,
    results_buf,
    ::Val{false},
)
    cpcv_buf = CPCVBuffers(cpcv, n_labels, mask_type)

    for split_num in 1:n_splits
        _reset!(cpcv_buf)
        _single_split_results!(
            model, cpcv, labels, scoring_fn, n_labels, cpcv_buf, results_buf, split_num
        )
    end
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels,
    scoring_fn,
    n_labels,
    n_splits,
    mask_type,
    results_buf,
    ::Val{true},
)
    nt = Threads.nthreads()
    cpcv_buf = [CPCVBuffers(cpcv, n_labels, mask_type) for _ in 1:nt]

    Threads.@threads :static for split_num in 1:n_splits
        cpcv_buf = cpcv_bufs[Threads.threadid()]
        _reset!(cpcv_buf)
        _single_split_results!(
            model, cpcv, labels, scoring_fn, n_labels, cpcv_buf, results_buf, split_num
        )
    end
end

function _single_split_results!(
    model,
    cpcv::CPCV,
    labels::LabelResults,
    scoring_fn::Function,
    n_labels::Int,
    cpcv_buf::CPCVBuffers,
    results_buf::Vector{SingleSplitResult},
    split_num::Int,
)
    cpcv_masks = _get_cpcv_masks(cpcv, labels, cpcv_buf, n_labels, split_num)
    train_mask = cpcv_masks.train
    test_mask = cpcv_masks.test
    purged_count = cpcv_masks.purged_count
    embargo_count = cpcv_masks.embargo_count

    train_feats = @view labels.feature[train_mask]
    train_bins = @view lables.bin[train_mask]
    train_weights = @view labels.weight[train_mask]
    mach = machine(model, train_feats, train_bins, train_weights)
    fit!(mach)

    test_feats = @view labels.feature[test_mask]
    test_true = @view label.bin[test_mask]
    test_preds = predict(mach, test_feats)

    score = scoring_fn(test_true, test_preds)

    return results_buf[split_num] = SingleSplitResult(
        split_num, test_mask, probs, score, purged_count, embargo_count
    )
end
