using Backtest, Test, DataFrames, DataFramesMeta, Dates

@testset "Integration Tests" begin
    @testset "DataFramesMeta @transform with EMA" begin
        df = DataFrame(
            ticker = fill("TEST", 20),
            timestamp = Date(2024, 1, 1) .+ Day.(0:19),
            close = Float64.(1:20),
        )

        result = @chain df begin
            @transform(:ema_5 = calculate_indicators(:close, EMA(5)))
        end

        @test "ema_5" ∈ names(result)
        @test length(result.ema_5) == 20
        @test all(isnan.(result.ema_5[1:4]))
        @test !any(isnan.(result.ema_5[5:end]))
    end

    @testset "DataFramesMeta @transform with multiple EMAs" begin
        df = DataFrame(
            ticker = fill("TEST", 30),
            timestamp = Date(2024, 1, 1) .+ Day.(0:29),
            close = Float64.(1:30),
        )

        result = @chain df begin
            @transform($AsTable = calculate_indicators(:close, EMA(5), EMA(10)))
        end

        @test "ema_5" ∈ names(result)
        @test "ema_10" ∈ names(result)
        @test length(result.ema_5) == 30
        @test length(result.ema_10) == 30
    end

    @testset "DataFramesMeta @transform with CUSUM" begin
        df = DataFrame(
            ticker = fill("TEST", 200),
            timestamp = Date(2024, 1, 1) .+ Day.(0:199),
            close = vcat(fill(100.0, 150), fill(150.0, 50)),
        )

        result = @chain df begin
            @transform(:cusum = calculate_indicators(:close, CUSUM(1.0)))
        end

        @test "cusum" ∈ names(result)
        @test eltype(result.cusum) == Int8
        @test length(result.cusum) == 200
    end

    @testset "Combined EMA and CUSUM" begin
        df = DataFrame(
            ticker = fill("TEST", 200),
            timestamp = Date(2024, 1, 1) .+ Day.(0:199),
            close = Float64.(100 .+ cumsum(randn(200))),
        )
        df.close = abs.(df.close)  # Ensure positive

        result = @chain df begin
            @transform(
                $AsTable = calculate_indicators(:close, EMA(10), EMA(20)),
                :cusum = calculate_indicators(:close, CUSUM(1.0)),
            )
        end

        @test "ema_10" ∈ names(result)
        @test "ema_20" ∈ names(result)
        @test "cusum" ∈ names(result)
    end

    @testset "Grouped DataFrame operations" begin
        df = DataFrame(
            ticker = vcat(fill("AAPL", 50), fill("MSFT", 50)),
            timestamp = vcat(
                Date(2024, 1, 1) .+ Day.(0:49),
                Date(2024, 1, 1) .+ Day.(0:49)
            ),
            close = vcat(Float64.(100:149), Float64.(200:249)),
        )

        result = @chain df begin
            @groupby(:ticker)
            @transform(:ema_5 = calculate_indicators(:close, EMA(5)))
        end

        @test nrow(result) == 100

        # Each ticker should have its own EMA calculation
        aapl = filter(r -> r.ticker == "AAPL", result)
        msft = filter(r -> r.ticker == "MSFT", result)

        @test length(aapl.ema_5) == 50
        @test length(msft.ema_5) == 50

        # MSFT prices are higher, so MSFT EMAs should be higher
        @test all(msft.ema_5[10:end] .> aapl.ema_5[10:end])
    end

    @testset "Large dataset performance sanity check" begin
        n = 10000
        df = DataFrame(
            ticker = fill("TEST", n),
            timestamp = Date(2020, 1, 1) .+ Day.(0:(n-1)),
            close = Float64.(100 .+ cumsum(randn(n))),
        )
        df.close = abs.(df.close)

        # Just ensure it completes without error
        result = @chain df begin
            @transform(
                $AsTable = calculate_indicators(:close, EMA(10), EMA(20), EMA(50)),
            )
        end

        @test nrow(result) == n
        @test "ema_10" ∈ names(result)
        @test "ema_20" ∈ names(result)
        @test "ema_50" ∈ names(result)
    end

    @testset "Real workflow: fetch-like data → indicators" begin
        # Simulate what get_data would return
        df = DataFrame(
            ticker = fill("SPY", 100),
            timestamp = Date(2024, 1, 1) .+ Day.(0:99),
            open = Float64.(100 .+ cumsum(randn(100) .* 0.5)),
            high = Float64.(102 .+ cumsum(randn(100) .* 0.5)),
            low = Float64.(98 .+ cumsum(randn(100) .* 0.5)),
            close = Float64.(100 .+ cumsum(randn(100) .* 0.5)),
            volume = rand(1000:10000, 100),
        )
        df.open = abs.(df.open)
        df.high = abs.(df.high)
        df.low = abs.(df.low)
        df.close = abs.(df.close)

        result = @chain df begin
            @transform(
                $AsTable = calculate_indicators(:close, EMA(5), EMA(10), EMA(20)),
            )
        end

        @test nrow(result) == 100
        @test Set(["ticker", "timestamp", "open", "high", "low", "close", "volume",
                   "ema_5", "ema_10", "ema_20"]) == Set(names(result))
    end
end
