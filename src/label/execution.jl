abstract type ExecutionBasis end

struct CurrentOpen <: ExecutionBasis end
struct CurrentClose <: ExecutionBasis end
struct NextOpen <: ExecutionBasis end
struct NextClose <: ExecutionBasis end
struct Immediate <: ExecutionBasis end

_get_idx_adj(::Union{CurrentOpen,CurrentClose,Immediate}) = 0
_get_idx_adj(::Union{NextOpen,NextClose}) = 1

@inline _get_price(::Union{CurrentOpen,NextOpen}, ::Any, idx, args) = args.bars.open[idx]
@inline _get_price(::Union{CurrentClose,NextClose}, ::Any, idx, args) = args.bars.close[idx]
@inline _get_price(::Immediate, level, ::Any, ::Any) = level