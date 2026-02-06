struct LowerBarrier{F} <: AbstractBarrier
    level_func::F
    label::Int8
end

struct UpperBarrier{F} <: AbstractBarrier
    level_func::F
    label::Int8
end

struct TimeBarrier{F} <: AbstractBarrier
    level_func::F
    label::Int8
end

struct ConditionBarrier{F} <: AbstractBarrier
    level_func::F
    label::Int8
end

@inline function barrier_level(b::AbstractBarrier, args::NamedTuple)
    return b.level_func(args)
end

@inline barrier_hit(::LowerBarrier, level, price, ::Any, ::Any) = price <= level
@inline barrier_hit(::UpperBarrier, level, ::Any, price, ::Any) = price >= level
@inline barrier_hit(::TimeBarrier, level::TimeType, ::Any, ::Any, ts::TimeType) =
    ts >= level
@inline barrier_hit(::ConditionBarrier, level, ::Any, ::Any, ::Any) = level