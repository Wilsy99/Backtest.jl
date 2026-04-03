
struct SplitMetrics{T<:AbstractFloat}
    split_id::Int
    score::T
    purge_count::Int
    embargo_count::Int
end

struct MetaLabelResults{T<:AbstractFloat}
    path_probs::Matrix{T}
    split_metrics::Vector{SplitMetrics{T}}
end

struct MetaLabelValidation{MLJ<:MLJModelInterface.Probalistic,CV<:AbstractCrossValidation,F}
    model::MLJ
    cross_validation::CV
    scoring_fn::F
end

function (mlv::MetaLabelValidation)(d::NamedTuple; multi_thread::Bool=false)
    result = evaluate(
        mlv.model, mlv.cross_validation, d.features.d.labels, mlv.scoring_fn; multi_thread
    )
    return merge(d, (; meta_label_cv=result))
end

function evaluate(
    model::MLJ,
    cpcv::CPCV,
    feats::FeatureResults,
    labels::LabelResults,
    scoring_fn::F;
    multi_thread=false,
) where {MLJ<:MLJModelInterface.Probalistic,F}
    T = typeof(labels.log_ret)

    n_labels = length(labels)

    meta_label_results = MetaLabelResults{T}(
        Matrix{T}(undef, n_labels, cpcv.n_paths),
        Vector{SplitMetrics{T}}(undef, cpcv.n_splits),
    )

    _split_metrics!(
        model,
        cpcv,
        feats,
        labels,
        scoring_fn,
        n_labels,
        meta_label_results,
        Val(multi_thread),
    )

    return meta_label_results
end

function _split_metrics!(
    model::MLJ,
    cpcv::CPCV,
    feats::FeatureResults,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    meta_label_results::MetaLabelResults,
    ::Val{false},
) where {MLJ<:MLJModelInterface.Probalistic,F}
    cpcv_buf = CPCVBuffers(cpcv, n_labels)

    @inbounds for split_num in 1:(cpcv.n_splits)
        _reset!(cpcv_buf)
        _split_metrics!(
            model,
            cpcv,
            feats,
            labels,
            scoring_fn,
            n_labels,
            meta_label_results,
            cpcv_buf,
            split_num,
        )
    end
end

function _split_metrics!(
    model::MLJ,
    cpcv::CPCV,
    feats::FeatureResults,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    meta_label_results::MetaLabelResults,
    ::Val{true},
) where {MLJ<:MLJModelInterface.Probalistic,F}
    nt = nthreads()
    cpcv_bufs = [CPCVBuffers(cpcv, n_labels) for _ in 1:nt]

    @inbounds @threads :static for split_num in 1:(cpcv.n_splits)
        cpcv_buf = cpcv_bufs[threadid()]
        _reset!(cpcv_buf)
        _split_metrics!(
            model,
            cpcv,
            feats,
            labels,
            scoring_fn,
            n_labels,
            meta_label_results,
            cpcv_buf,
            split_num,
        )
    end
end

function _split_metrics!(
    model::MLJ,
    cpcv::CPCV,
    feats::FeatureResults,
    labels::LabelResults,
    scoring_fn::F,
    n_labels::Int,
    meta_label_results::MetaLabelResults,
    cpcv_buf::CPCVBuffers,
    split_num::Int,
) where {MLJ<:MLJModelInterface.Probalistic,F}
    cpcv_masks = _get_split_data_masks!(cpcv, labels, cpcv_buf, n_labels, split_num)
    mach = _train_model(model, labels, feats, cpcv_masks.train)

    test_preds = _test_model(mach, feats, cpcv_masks.test)

    test_true = @view labels.bin[cpcv_masks.test]
    score = scoring_fn(test_true, test_preds)

    _fill_path_probs!(
        meta_label_results.path_probs, cpcv, n_labels, cpcv_buf.test_group_mask, test_preds
    )

    meta_label_results.split_metrics[split_num] = SplitMetrics(
        split_num, score, cpcv_masks.purge_count, cpcv_masks.embargo_count
    )

    return nothing
end

function _train_model(
    model::MLJ, labels::LabelResults, feats::FeatureResults, train_mask::M
) where {MLJ<:MLJModelInterface.Probalistic,M<:AbstractVector{Bool}}
    train_feats = @view feats[train_mask]
    train_bins = @view labels.bin[train_mask]
    train_weights = @view labels.weight[train_mask]
    mach = machine(model, train_feats, train_bins, train_weights)
    return fit!(mach)
end

function _test_model(
    mach, feats::FeatureResults, test_mask::M
) where {M<:AbstractVector{Bool}}
    test_feats = @view feats[test_mask]
    preds = predict(mach, test_feats)
    return pdf.(preds, 1)
end

function _fill_path_probs!(
    path_probs::Matrix{T},
    cpcv::CPCV,
    n_labels::Int,
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
        j = _get_path_id(cpcv, group, test_group_mask)

        # 3. Local range inside `test_preds` for this specific group
        group_len = length(i)
        test_preds_idx_rng = test_preds_cur_idx:(test_preds_cur_idx + group_len - 1)

        # 4. Safely assign the predictions in-place
        path_probs[i, j] .= @view test_preds[test_preds_idx_rng]

        # 5. Advance the pointer for the next active group
        test_preds_cur_idx += group_len
    end
end