struct Crossover{D,Fast,Slow,Wait} <: AbstractSide
    function Crossover{D,Fast,Slow,Wait}() where {D,Fast,Slow,Wait}
        D ∈ (LongOnly, ShortOnly, LongShort) ||
            throw(ArgumentError("Direction must be LongOnly, ShortOnly, or LongShort"))
        return new{D,Fast,Slow,Wait}()
    end
end

function Crossover(
    fast::Symbol, slow::Symbol; wait_for_cross::Bool=true, direction::Direction=LongShort
)
    return Crossover{direction,fast,slow,wait_for_cross}()
end

function Crossover(; wait_for_cross::Bool=true, direction::Direction=LongShort)
    return Crossover{direction,nothing,nothing,wait_for_cross}()
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
) where {D,Fast,Slow,Wait,T<:AbstractFloat}
    return _calculate_cross_sides(fast_series, slow_series, Val(Wait), Val(D))
end

function _calculate_cross_sides(
    fast_series::AbstractVector{T}, slow_series::AbstractVector{T}, ::Val{Wait}, dir::Val{D}
) where {T<:AbstractFloat,Wait,D}
    n = length(fast_series)
    sides = zeros(Int8, n)

    start_idx = findfirst(!isnan, slow_series)
    isnothing(start_idx) && return sides

    if Wait
        first_cross = _find_first_cross(fast_series, slow_series, start_idx, dir)
        first_cross == -1 && return sides
        start_idx = first_cross
    end

    _fill_cross_transitions!(sides, fast_series, slow_series, start_idx, dir)

    return sides
end

# ============================================
# Fill only at crossover transition points
# ============================================

@inline function _fill_cross_transitions!(
    sides::AbstractVector{Int8}, fast, slow, from_idx::Int, ::Val{LongOnly}
)
    n = length(sides)
    from_idx > n && return
    @inbounds if fast[from_idx] > slow[from_idx]
        sides[from_idx] = Int8(1)
    end
    @inbounds for i in (from_idx + 1):n
        if fast[i] > slow[i] && fast[i - 1] <= slow[i - 1]
            sides[i] = Int8(1)
        end
    end
end

@inline function _fill_cross_transitions!(
    sides::AbstractVector{Int8}, fast, slow, from_idx::Int, ::Val{ShortOnly}
)
    n = length(sides)
    from_idx > n && return
    @inbounds if fast[from_idx] < slow[from_idx]
        sides[from_idx] = Int8(-1)
    end
    @inbounds for i in (from_idx + 1):n
        if fast[i] < slow[i] && fast[i - 1] >= slow[i - 1]
            sides[i] = Int8(-1)
        end
    end
end

@inline function _fill_cross_transitions!(
    sides::AbstractVector{Int8}, fast, slow, from_idx::Int, ::Val{LongShort}
)
    n = length(sides)
    from_idx > n && return
    @inbounds begin
        f, s = fast[from_idx], slow[from_idx]
        sides[from_idx] = ifelse(f > s, Int8(1), ifelse(f < s, Int8(-1), Int8(0)))
    end
    @inbounds for i in (from_idx + 1):n
        if fast[i] > slow[i] && fast[i - 1] <= slow[i - 1]
            sides[i] = Int8(1)
        elseif fast[i] < slow[i] && fast[i - 1] >= slow[i - 1]
            sides[i] = Int8(-1)
        end
    end
end

# ============================================
# Find first cross - dispatched by direction
# ============================================

@inline function _find_first_cross(fast, slow, start_idx, ::Val{LongOnly})
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

@inline function _find_first_cross(fast, slow, start_idx, ::Val{ShortOnly})
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

@inline function _find_first_cross(fast, slow, start_idx, ::Val{LongShort})
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