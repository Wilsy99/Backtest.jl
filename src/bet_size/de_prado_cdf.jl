struct DePradoCDF{T<:AbstractFloat} <: AbstractBetSizeStrategy
    step_size::T      # e.g., 0.1 for 10-step grid. 0.0 for continuous.
    scale::T          # 1.0 is standard AFML. > 1.0 flattens the curve.
    min_prob::T       # e.g., 0.55. Below this, bet size is 0.

    function DePradoCDF{T}(ss, s, mp) where {T<:AbstractFloat}
        return new{T}(
            _nonnegative_float(T(ss)), # Allowed to be 0.0
            _positive_float(T(s)),     # MUST be > 0.0
            _nonnegative_float(T(mp)),  # Allowed to be 0.0
        )
    end
end

function DePradoCDF(; step_size::Float64=0.0, scale::Float64=1.0, min_prob::Float64=0.5)
    return DePradoCDF{Float64}(step_size, scale, min_prob)
end

@inline function bet_size(strategy::DePradoCDF{T}, prob::T) where {T<:AbstractFloat}
    @fastmath begin # 1. The Dead Zone Check
        # If the probability is too close to 0.5, don't trade.
        (prob >= strategy.min_prob || prob <= (one(T) - strategy.min_prob)) ||
            return zero(T)

        # 2. Get the continuous bet size (using your optimized _erf function)
        # Notice we apply the 'scale' to the denominator to adjust the curve
        prob_safe = clamp(prob, T(1e-15), one(T) - T(1e-15))
        val =
            (prob_safe - T(0.5)) /
            (strategy.scale * sqrt(T(2.0) * prob_safe * (one(T) - prob_safe)))

        m_continuous = _erf(val)

        # 3. Discretization (Grid Size)
        return ifelse(
            strategy.step_size > zero(T),
            round(m_continuous / strategy.step_size) * strategy.step_size,
            m_continuous,
        )
    end
end

@inline function _erf(x::T) where {T<:AbstractFloat}
    @fastmath begin
        abs_x = abs(x)

        # copysign is a branchless way to apply the sign of 'x' to '1.0'
        # This replaces the `if signbit()` logic
        sign_val = copysign(one(T), x)

        prob_const = T(0.3275911)
        t = one(T) / muladd(prob_const, abs_x, one(T))

        poly = evalpoly(
            t,
            (
                zero(T),
                T(0.254829592),
                T(-0.284496736),
                T(1.421413741),
                T(-1.453152027),
                T(1.061405429),
            ),
        )

        y = one(T) - poly * exp(-x^2)

        return sign_val * y
    end
end
