function _calculate_cumulative_inverse_concurrency(
    n_timestamps::Int, entry_indices::Vector{Int}, exit_indices::Vector{Int}
)
    concur_deltas = zeros(Int32, n_timestamps + 1)

    @inbounds for i in eachindex(entry_indices)
        entry_idx = entry_indices[i]
        exit_idx = exit_indices[i]

        concur_deltas[entry_idx] += 1
        concur_deltas[exit_idx + 1] -= 1
    end

    cum_inv_concurs = Vector{Float64}(undef, n_timestamps)

    concur = 0
    cum_inv_concur = 0.0

    @inbounds for i in 1:n_timestamps
        concur += concur_deltas[i]

        if concur > 0
            cum_inv_concur += 1.0 / concur
        end

        cum_inv_concurs[i] = cum_inv_concur
    end

    return cum_inv_concurs
end