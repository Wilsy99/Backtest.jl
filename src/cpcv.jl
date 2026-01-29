# abstract type BarType end
# struct TimeBar <: BarType end

# abstract type Config end
# struct CPCV <: Config
#     n_groups::Int
#     n_test_sets::Int
#     max_trade::Int
#     embargo::Int

#     function CPCV(; n_groups, n_test_sets, max_trade, embargo)
#         return new(n_groups, n_test_sets, max_trade, embargo)
#     end
# end

# function generate_config(df, ::Type{T}, config::CPCV)::DataFrame where {T<:BarType}
#     unique_ts = sort(unique(df.timestamp))
#     n_timestamps = length(unique_ts)

#     indices = _generate_indices(n_timestamps, config)

#     training_ts = [
#         [(unique_ts[first(rng)], unique_ts[last(rng)]) for rng in split] for
#         split in indices.training
#     ]

#     test_ts = [
#         [(unique_ts[first(rng)], unique_ts[last(rng)]) for rng in split] for
#         split in indices.test
#     ]

#     return DataFrame(;
#         split_id=1:length(indices.training),
#         training_set_timestamps=training_ts,
#         test_set_timestamps=test_ts,
#     )
# end

# function _generate_indices(n_indices::Int, s::CPCV)
#     group_ids = collect(1:(s.n_groups))
#     group_ranges = _generate_group_indices(n_indices, s.n_groups)
#     test_combos = collect(combinations(group_ids, s.n_test_sets))

#     train_indices, test_indices = _split_ranges(
#         length(test_combos), s, group_ids, group_ranges, test_combos
#     )

#     return (training=train_indices, test=test_indices)
# end

# function _generate_group_indices(n, num_groups)
#     base, rem = divrem(n, num_groups)
#     start_idx = 1
#     map(1:num_groups) do i
#         end_idx = start_idx + base - (i > rem ? 1 : 0)
#         rng = start_idx:end_idx
#         start_idx = end_idx + 1
#         return rng
#     end
# end

# function _split_ranges(n_splits, s::CPCV, group_ids, group_ranges, test_combos)
#     all_train = Vector{Vector{UnitRange{Int}}}(undef, n_splits)
#     all_test = Vector{Vector{UnitRange{Int}}}(undef, n_splits)

#     @threads for i in 1:n_splits
#         test_set = BitSet(test_combos[i])
#         train_split = UnitRange{Int}[]
#         test_split = UnitRange{Int}[]

#         sizehint!(train_split, s.n_groups)
#         sizehint!(test_split, s.n_test_sets)

#         for (id, rng) in zip(group_ids, group_ranges)
#             if id in test_set
#                 push!(test_split, rng)
#                 continue
#             end

#             start_idx, end_idx = first(rng), last(rng)

#             if (id - 1) in test_set
#                 start_idx += (s.max_trade + s.embargo)
#             end

#             if (id + 1) in test_set
#                 end_idx -= s.max_trade
#             end

#             if start_idx <= end_idx
#                 push!(train_split, start_idx:end_idx)
#             end
#         end
#         all_train[i] = train_split
#         all_test[i] = test_split
#     end
#     return all_train, all_test
# end