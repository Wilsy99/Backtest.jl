struct Crossover{D<:AbstractDirection,Fast,Slow,Wait} <: AbstractSide
    function Crossover{D,Fast,Slow,Wait}() where {D<:AbstractDirection,Fast,Slow,Wait}
        return new{D,Fast,Slow,Wait}()
    end
end

function Crossover(
    fast::Symbol,
    slow::Symbol;
    wait_for_cross::Bool=true,
    direction::AbstractDirection=LongShort(),
)
    return Crossover{typeof(direction),fast,slow,wait_for_cross}()
end

function Crossover(; wait_for_cross::Bool=true, direction::AbstractDirection=LongShort())
    return Crossover{typeof(direction),nothing,nothing,wait_for_cross}()
end

function _side_result(
    side::Crossover{D,Fast,Slow,Wait}, d::NamedTuple
) where {D,Fast,Slow,Wait}
    vals = calculate_side(side, d[Fast], d[Slow])
    return (side=vals,)
end

function calculate_side(
    ::Crossover{D,Fast,Slow,Wait},
    fast_series::AbstractVector{T},
    slow_series::AbstractVector{T},
) where {D<:AbstractDirection,Fast,Slow,Wait,T<:AbstractFloat}
    return _calculate_cross_sides(fast_series, slow_series, Val(Wait), D())
end

function _calculate_cross_sides(
    fast_series::AbstractVector{T}, slow_series::AbstractVector{T}, ::Val{Wait}, dir::D
) where {T<:AbstractFloat,Wait,D<:AbstractDirection}
    n = length(fast_series)
    sides = zeros(Int8, n)

    start_idx = findfirst(!isnan, slow_series)
    isnothing(start_idx) && return sides

    cond_f = _get_condition_func(fast_series, slow_series, dir)

    if !Wait
        _fill_sides_generic!(sides, start_idx, cond_f)
        return sides
    end

    first_cross = _find_first_cross(fast_series, slow_series, start_idx, dir)

    if first_cross != -1
        _fill_sides_generic!(sides, first_cross, cond_f)
    end

    return sides
end

# ============================================
# Condition functions - dispatched by direction
# ============================================

@inline function _get_condition_func(fast, slow, ::LongOnly)
    return i -> @inbounds ifelse(fast[i] > slow[i], Int8(1), Int8(0))
end

@inline function _get_condition_func(fast, slow, ::ShortOnly)
    return i -> @inbounds ifelse(fast[i] < slow[i], Int8(-1), Int8(0))
end

@inline function _get_condition_func(fast, slow, ::LongShort)
    return i -> @inbounds begin
        f, s = fast[i], slow[i]
        ifelse(f > s, Int8(1), ifelse(f < s, Int8(-1), Int8(0)))
    end
end

# ============================================
# Find first cross - dispatched by direction
# ============================================

@inline function _find_first_cross(fast, slow, start_idx, ::LongOnly)
    n = length(fast)
    @inbounds has_been_below = fast[start_idx] <= slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        f_val = fast[i]
        s_val = slow[i]
        if has_been_below && f_val > s_val
            return i
        elseif f_val <= s_val
            has_been_below = true
        end
    end
    return -1
end

@inline function _find_first_cross(fast, slow, start_idx, ::ShortOnly)
    n = length(fast)
    @inbounds has_been_above = fast[start_idx] >= slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        f_val = fast[i]
        s_val = slow[i]
        if has_been_above && f_val < s_val
            return i
        elseif f_val >= s_val
            has_been_above = true
        end
    end
    return -1
end

@inline function _find_first_cross(fast, slow, start_idx, ::LongShort)
    n = length(fast)
    @inbounds prev_above = fast[start_idx] > slow[start_idx]

    @inbounds for i in (start_idx + 1):n
        curr_above = fast[i] > slow[i]
        if curr_above != prev_above
            return i
        end
        prev_above = curr_above
    end
    return -1
end