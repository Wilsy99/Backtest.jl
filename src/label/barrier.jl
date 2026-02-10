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

LowerBarrier(f, label) = LowerBarrier(f, label, Immediate())
UpperBarrier(f, label) = UpperBarrier(f, label, Immediate())
TimeBarrier(f, label) = TimeBarrier(f, label, Immediate())
ConditionBarrier(f, label) = ConditionBarrier(f, label, NextClose())

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

macro UpperBarrier(ex, label=1)
    return :(@_Barrier UpperBarrier $ex label = $label)
end

macro LowerBarrier(ex, label=-1)
    return :(@_Barrier LowerBarrier $ex label = $label)
end

macro TimeBarrier(ex, label=0)
    return :(@_Barrier TimeBarrier $ex label = $label)
end

macro ConditionBarrier(ex, label=0)
    return :(@_Barrier TimeBarrier $ex label = $label)
end

macro _Barrier(type, args...)
    funcs, kwargs = _build_macro_components(BarrierContext(), args)
    return esc(:($type($(funcs[1]), $(kwargs...))))
end

function _replace_symbols(::BarrierContext, ex::QuoteNode)
    direct_fields = (:entry_price, :entry_ts, :idx)
    if ex.value in direct_fields
        return :(d.$(ex.value))
    else
        # Barrier logic: :close -> d.bars.close[d.idx]
        return :(d.bars.$(ex.value)[d.idx])
    end
end