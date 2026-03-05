struct MetaLabeler{M<:AbstractMLModel,CV<:AbstractCrossValidation}
    model::M
    cross_validation::CV
end

struct MetaLabeler!{M<:AbstractMLModel,CV<:AbstractCrossValidation}
    model::ML
    cross_validation::CV
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

function (meta_labeler::MetaLabeler!)(labels::LabelResults; multi_thread=false)
    return run(meta_labeler, labels; multi_thread)
end

function (meta_labeler::MetaLabeler!)(d::NamedTuple; multi_thread=false)
    labels = d.labels

    return run(meta_labeler, labels; multi_thread)
end

function run(
    meta_labeler::Union{MetaLabeler{<:Any,<:CPCV},MetaLabeler!{<:Any,<:CPCV}},
    labels;
    multi_thread,
) where {M,CV<:CPCV}
    model = meta_labeler.model
    cpcv = meta_labeler.cpcv

    n_labels = length(labels)
    n_folds = cpcv.n_folds
    mask_type = cpcv.mask_type

    nt = Threads.nthreads()
    bufs = [CPCVBuffers(cpcv, n_labels, mask_type) for _ in 1:nt]
    results = Vector{Any}(undef, cpcv.n_folds)

    Threads.@threads :static for fold_num in 1:n_folds
        buf = bufs[Threads.threadid()]
        _reset!(buf)
        masks = _get_fold_data_masks!(cpcv, labels, buf, n_labels, fold_num)
        results[fold_num] = train_and_test(model, data, masks.train, masks.test)
    end

    return results
end