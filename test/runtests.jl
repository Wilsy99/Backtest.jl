using Backtest, Test

@testset "Backtest.jl" begin
    include("utility_tests.jl")
    include("data_tests.jl")
    include("indicator/indicator_tests.jl")
    include("indicator/ema_tests.jl")
    include("indicator/cusum_tests.jl")
    include("strategy/ema_cross_tests.jl")
    include("integration_tests.jl")
end
