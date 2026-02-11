using Aqua

@testset "Package Quality (Aqua.jl)" begin
    Aqua.test_all(Backtest; ambiguities=false)
end
