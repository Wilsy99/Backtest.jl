using Backtest, Test, Dates

include("testutils.jl")

@testset "Backtest.jl" begin
    include("aqua_tests.jl")
    include("utility_tests.jl")
    include("type_tests.jl")
    include("data_tests.jl")
    @testset "Indicators" begin
        include("indicator/ema_tests.jl")
        include("indicator/cusum_tests.jl")
        include("indicator/indicator_tests.jl")
    end
    include("integration_tests.jl")
end
