struct LowerBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

struct UpperBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

struct TimeBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

struct ConditionBarrier{F<:Function,E<:AbstractExecutionBasis} <: AbstractBarrier
    level_func::F
    label::Int8
    exit_basis::E
end

LowerBarrier(f; label=-1, exit_basis=Immediate()) = LowerBarrier(f, label, exit_basis)
UpperBarrier(f; label=1, exit_basis=Immediate()) = UpperBarrier(f, label, exit_basis)
TimeBarrier(f; label=0, exit_basis=Immediate()) = TimeBarrier(f, label, exit_basis)
function ConditionBarrier(f; label=0, exit_basis=NextClose())
    return ConditionBarrier(f, label, exit_basis)
end

@inline barrier_level(b::AbstractBarrier, args) = b.level_func(args)

@inline gap_hit(::LowerBarrier, level, open_price) = open_price <= level
@inline gap_hit(::UpperBarrier, level, open_price) = open_price >= level
@inline gap_hit(::Union{TimeBarrier,ConditionBarrier}, ::Any, ::Any) = false

@inline barrier_hit(::LowerBarrier, level, low, ::Any, ::Any) = low <= level
@inline barrier_hit(::UpperBarrier, level, ::Any, high, ::Any) = high >= level
@inline barrier_hit(::TimeBarrier, level::TimeType, ::Any, ::Any, ts::TimeType) =
    ts >= level
@inline barrier_hit(::ConditionBarrier, level, ::Any, ::Any, ::Any) = level

struct BarrierContext end

macro UpperBarrier(ex, args...)
    return :(@_Barrier UpperBarrier 1 $ex $(args...))
end

macro LowerBarrier(ex, args...)
    return :(@_Barrier LowerBarrier -1 $ex $(args...))
end

macro TimeBarrier(ex, args...)
    return :(@_Barrier TimeBarrier 0 $ex $(args...))
end

macro ConditionBarrier(ex, args...)
    return :(@_Barrier ConditionBarrier 0 $ex $(args...))
end

macro _Barrier(type, default_label, args...)
    funcs, kwargs = _build_macro_components(BarrierContext(), args)
    return esc(:($type($(funcs[1]); label=$default_label, $(kwargs...))))
end

function _replace_symbols(::BarrierContext, ex::QuoteNode)
    direct_fields = (:entry_price, :entry_ts, :idx)
    if ex.value in direct_fields
        return :(d.$(ex.value))
    else
        return :(d.bars.$(ex.value)[d.idx])
    end
end