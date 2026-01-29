# function TripleBarrier(tp::T, sl::T, to::Int) where {T<:AbstractFloat}
#     return TripleBarrier{T}(tp, sl, to)
# end

# function calculate_labels(
#     label::TripleBarrier{T},
#     event_indices::AbstractVector{Int},
#     opens::AbstractVector{T},
#     highs::AbstractVector{T},
#     lows::AbstractVector{T},
#     closes::AbstractVector{T};
#     drop_unfinished::Bool=true,
# ) where {T<:AbstractFloat}
#     take_profit = label.take_profit
#     stop_loss = -label.stop_loss
#     time_out = label.time_out
#     n_events = length(event_indices)
#     n_prices = length(closes)

#     tp_threshold = one(T) + take_profit
#     sl_threshold = one(T) + stop_loss

#     log_tp = log(tp_threshold)
#     log_sl = log(sl_threshold)

#     t₁ = Vector{Int}(undef, n_events)
#     # Use -99 as a sentinel to identify trades that didn't finish
#     labels = fill(Int8(-99), n_events)
#     log_returns = Vector{T}(undef, n_events)

#     # We iterate 1:n_events to map results correctly to output vectors
#     @threads for i in 1:n_events
#         @inbounds begin
#             event_idx = event_indices[i]
#             entry_price = closes[event_idx]
#             time_out_idx = event_idx + time_out
#             limit_index = min(time_out_idx, n_prices)
#             barrier_hit = false

#             for prices_idx in (event_idx + 1):limit_index
#                 # Check for Gaps at Open (using prices_idx for the future bar)
#                 return_open = opens[prices_idx] / entry_price

#                 if return_open <= sl_threshold
#                     t₁[i] = prices_idx
#                     labels[i] = -1
#                     log_returns[i] = log(return_open)
#                     barrier_hit = true
#                     break
#                 elseif return_open >= tp_threshold
#                     t₁[i] = prices_idx
#                     labels[i] = 1
#                     log_returns[i] = log(return_open)
#                     barrier_hit = true
#                     break
#                 end

#                 # Check SL hit before TP hit
#                 return_low = lows[prices_idx] / entry_price
#                 if return_low <= sl_threshold
#                     t₁[i] = prices_idx
#                     labels[i] = -1
#                     log_returns[i] = log_sl
#                     barrier_hit = true
#                     break
#                 end

#                 return_high = highs[prices_idx] / entry_price
#                 if return_high >= tp_threshold
#                     t₁[i] = prices_idx
#                     labels[i] = 1
#                     log_returns[i] = log_tp
#                     barrier_hit = true
#                     break
#                 end
#             end

#             if !barrier_hit && time_out_idx <= n_prices
#                 t₁[i] = time_out_idx
#                 labels[i] = 0
#                 log_returns[i] = log(closes[time_out_idx] / entry_price)
#             end
#         end
#     end

#     if drop_unfinished
#         keep_mask = labels .!= -99
#         return (
#             event_indices=event_indices[keep_mask],
#             t₁=t₁[keep_mask],
#             label=labels[keep_mask],
#             log_return=log_returns[keep_mask],
#         )
#     else
#         return (t₁=t₁, label=labels, log_return=log_returns)
#     end
# end