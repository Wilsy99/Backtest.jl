using Pkg
Pkg.activate(".")

using Backtest

# Simulate what your test does
prices = rand(Float64, 200)

# Closure capturing `prices` from outer scope
allocs_seed() = @allocated Backtest._sma_seed(prices, 10)
Backtest._sma_seed(prices, 10)
allocs_seed()
println("closure over outer prices: $(allocs_seed())")

# Explicit argument — no capture
allocs_seed2(p) = @allocated Backtest._sma_seed(p, 10)
allocs_seed2(prices)
println("explicit argument: $(allocs_seed2(prices))")