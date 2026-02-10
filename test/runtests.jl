using Backtest, Test

@testset "Backtest.jl" begin
    include("utility_tests.jl")
    include("data_tests.jl")
end
