abstract type AbstractExecutionBasis end

struct CurrentOpen <: AbstractExecutionBasis end
struct CurrentClose <: AbstractExecutionBasis end
struct NextOpen <: AbstractExecutionBasis end
struct NextClose <: AbstractExecutionBasis end
struct Immediate <: AbstractExecutionBasis end

_temporal_priority(::Immediate) = 1
_temporal_priority(::CurrentOpen) = 2
_temporal_priority(::CurrentClose) = 3
_temporal_priority(::NextOpen) = 4
_temporal_priority(::NextClose) = 5

_get_idx_adj(::Union{CurrentOpen,CurrentClose,Immediate}) = 0
_get_idx_adj(::Union{NextOpen,NextClose}) = 1

@inline _get_price(::Union{CurrentOpen,NextOpen}, ::Any, idx, args) = args.bars.open[idx]
@inline _get_price(::Union{CurrentClose,NextClose}, ::Any, idx, args) = args.bars.close[idx]
@inline _get_price(::Immediate, level::AbstractFloat, ::Any, ::Any) = level
@inline _get_price(::Immediate, ::Union{TimeType,Bool}, idx, args) = args.bars.close[idx]