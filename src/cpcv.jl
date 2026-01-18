function generate_group_indices(n_indices::Int, n_groups::Int)::Vector{UnitRange{Int}}
    base, rem = divrem(n_indices, n_groups)

    group_indices = Vector{UnitRange{Int}}(undef, n_groups)

    start_idx = 1
    for i in 1:n_groups
        end_idx = i <= rem ? start_idx + base : start_idx + base - 1
        group_indices[i] = start_idx:end_idx
        start_idx = end_idx + 1
    end

    return group_indices
end