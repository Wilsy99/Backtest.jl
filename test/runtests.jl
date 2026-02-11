using Backtest, Test

@testset "Backtest.jl" begin
    include("utility_tests.jl")
    include("indicator/ema_tests.jl")
end
