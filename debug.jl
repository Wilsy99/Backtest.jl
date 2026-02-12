using Pkg
Pkg.activate(".")
using Backtest

prices = collect(1.0:200.0)
periods = [5, 10, 20]

# Warmup
Backtest._calculate_emas(prices, periods)

# Check matrix-only allocation
println("Matrix alone: ", @allocated(Matrix{Float64}(undef, 200, 3)), " bytes")

# Check full function
println("Full function: ", @allocated(Backtest._calculate_emas(prices, periods)), " bytes")

# Check a single view allocation

@views col = M[:, 1]  # warmup
println("Single @views slice: ", @allocated(@views M[:, 1]), " bytes")

M = Matrix{Float64}(undef, 200, 3)
tst(M) = (@views M[:, 1])
@allocated tst(M)

alloc_matrix(n, k) = Matrix{Float64}(undef, n, k)
alloc_matrix(200, 3)  # warmup
@allocated alloc_matrix(200, 3)

global_m = Matrix{Float64}(undef, 0, 0)
println("Real Overhead: ", @allocated(global_m = Matrix{Float64}(undef, 0, 0)), " bytes")

function create_empty_matrix(T)
    return Matrix{T}(undef, 0, 0)
end

@allocated create_empty_matrix(Float64)