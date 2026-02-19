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

function ConditionBarrier(f; label=0, exit_basis=NextOpen())
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

function _build_barrier_expr(type::Symbol, default_label, args)
    funcs, kwargs = _build_macro_components(BarrierContext(), args)
    has_label = any(kw -> kw.args[1] == :label, kwargs)
    if has_label
        return esc(:($type($(funcs[1]); $(kwargs...))))
    else
        return esc(:($type($(funcs[1]); label=$default_label, $(kwargs...))))
    end
end

macro UpperBarrier(ex, args...)
    return _build_barrier_expr(:UpperBarrier, 1, (ex, args...))
end

macro LowerBarrier(ex, args...)
    return _build_barrier_expr(:LowerBarrier, -1, (ex, args...))
end

macro TimeBarrier(ex, args...)
    return _build_barrier_expr(:TimeBarrier, 0, (ex, args...))
end

macro ConditionBarrier(ex, args...)
    return _build_barrier_expr(:ConditionBarrier, 0, (ex, args...))
end

function _replace_symbols(::BarrierContext, ex::QuoteNode)
    direct_fields = (:entry_price, :entry_ts, :idx)
    bars_fields = (:open, :high, :low, :close, :volume, :timestamp)
    if ex.value in direct_fields
        return :(d.$(ex.value))
    elseif ex.value in bars_fields
        return :(d.bars.$(ex.value)[d.idx])
    else
        return :(d.$(ex.value)[d.idx])
    end
end