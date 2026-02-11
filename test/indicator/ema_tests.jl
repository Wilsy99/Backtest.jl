@testset "EMA" begin
    # ── Constructor Validation ──

    @testset "Constructor validation" begin
        @test EMA(1) isa EMA
        @test EMA(5) isa EMA
        @test EMA(100) isa EMA

        # Multiple periods
        @test EMA(5, 10) isa EMA
        @test EMA(5, 10, 20) isa EMA

        # Invalid periods
        @test_throws ArgumentError EMA(0)
        @test_throws ArgumentError EMA(-1)
        @test_throws ArgumentError EMA(-5)
        @test_throws ArgumentError EMA(5, 0)
        @test_throws ArgumentError EMA(0, 10)
    end

    # ── Hand-Calculated Reference Values ──

    @testset "Reference values — period 3" begin
        # prices = [10, 11, 12, 13, 14, 15]
        # α = 2/(3+1) = 0.5
        # SMA seed = (10+11+12)/3 = 11.0
        # EMA[4] = 0.5*13 + 0.5*11.0 = 12.0
        # EMA[5] = 0.5*14 + 0.5*12.0 = 13.0
        # EMA[6] = 0.5*15 + 0.5*13.0 = 14.0
        prices = Float64[10, 11, 12, 13, 14, 15]
        ema = calculate_indicator(EMA(3), prices)

        @test length(ema) == 6
        @test all(isnan, ema[1:2])
        @test ema[3] ≈ 11.0
        @test ema[4] ≈ 12.0
        @test ema[5] ≈ 13.0
        @test ema[6] ≈ 14.0
    end

    @testset "Reference values — period 5" begin
        # prices = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        # α = 2/(5+1) = 1/3, β = 2/3
        # SMA seed = (1+2+3+4+5)/5 = 3.0
        # EMA[6] = (1/3)*6 + (2/3)*3.0 = 4.0
        # EMA[7] = (1/3)*7 + (2/3)*4.0 = 5.0
        # EMA[8] = (1/3)*8 + (2/3)*5.0 = 6.0
        # EMA[9] = (1/3)*9 + (2/3)*6.0 = 7.0
        # EMA[10] = (1/3)*10 + (2/3)*7.0 = 8.0
        prices = Float64.(1:10)
        ema = calculate_indicator(EMA(5), prices)

        @test length(ema) == 10
        @test all(isnan, ema[1:4])
        @test ema[5] ≈ 3.0
        @test ema[6] ≈ 4.0
        @test ema[7] ≈ 5.0
        @test ema[8] ≈ 6.0
        @test ema[9] ≈ 7.0
        @test ema[10] ≈ 8.0
    end

    @testset "SMA seed correctness" begin
        prices = Float64[2, 4, 6, 8, 10]
        ema = calculate_indicator(EMA(5), prices)
        @test ema[5] ≈ 6.0  # mean([2,4,6,8,10]) = 6.0
    end

    # ── Multiple EMAs ──

    @testset "Multiple periods" begin
        prices = Float64.(1:20)
        result = calculate_indicator(EMA(3, 5), prices)

        @test result isa Matrix{Float64}
        @test size(result) == (20, 2)

        # Column 1 = EMA(3), Column 2 = EMA(5)
        single_3 = calculate_indicator(EMA(3), prices)
        single_5 = calculate_indicator(EMA(5), prices)

        # Non-NaN values must agree with single-period calculation
        for i in 3:20
            @test result[i, 1] ≈ single_3[i]
        end
        for i in 5:20
            @test result[i, 2] ≈ single_5[i]
        end
    end

    @testset "Three periods" begin
        prices = Float64.(1:30)
        result = calculate_indicator(EMA(2, 5, 10), prices)

        @test size(result) == (30, 3)

        single_2 = calculate_indicator(EMA(2), prices)
        single_5 = calculate_indicator(EMA(5), prices)
        single_10 = calculate_indicator(EMA(10), prices)

        for i in 10:30
            @test result[i, 1] ≈ single_2[i]
            @test result[i, 2] ≈ single_5[i]
            @test result[i, 3] ≈ single_10[i]
        end
    end

    # ── NamedTuple Result Interface ──

    @testset "NamedTuple result — single period" begin
        bars = make_pricebars(; n=50)
        nt = Backtest._indicator_result(EMA(10), bars.close)

        @test haskey(nt, :ema_10)
        @test nt.ema_10 isa Vector{Float64}
        @test length(nt.ema_10) == 50
    end

    @testset "NamedTuple result — multiple periods" begin
        bars = make_pricebars(; n=50)
        nt = Backtest._indicator_result(EMA(5, 10, 20), bars.close)

        @test haskey(nt, :ema_5)
        @test haskey(nt, :ema_10)
        @test haskey(nt, :ema_20)

        @test length(nt.ema_5) == 50
        @test length(nt.ema_10) == 50
        @test length(nt.ema_20) == 50
    end

    # ── Mathematical Properties ──

    @testset "Constant input converges to constant" begin
        prices = fill(42.0, 200)
        ema = calculate_indicator(EMA(10), prices)

        @test ema[10] ≈ 42.0
        @test ema[end] ≈ 42.0
        # All non-NaN values should be exactly the constant
        @test all(ema[10:end] .≈ 42.0)
    end

    @testset "EMA is bounded by price range" begin
        bars = make_pricebars(; n=200)
        prices = bars.close
        ema = calculate_indicator(EMA(10), prices)

        valid = ema[10:end]
        @test minimum(valid) >= minimum(prices) - eps()
        @test maximum(valid) <= maximum(prices) + eps()
    end

    @testset "Longer period is smoother" begin
        bars = make_pricebars(; n=500)
        prices = bars.close

        ema_short = calculate_indicator(EMA(5), prices)
        ema_long = calculate_indicator(EMA(50), prices)

        # Compare variance of differences (smoothness) over shared valid range
        start = 51
        var_short = sum(diff(ema_short[start:end]) .^ 2)
        var_long = sum(diff(ema_long[start:end]) .^ 2)

        @test var_long < var_short
    end

    @testset "EMA tracks trend direction" begin
        up = make_trending_prices(:up; n=100, step=1.0)
        ema_up = calculate_indicator(EMA(5), up)
        # EMA should also be increasing after warmup
        valid = ema_up[6:end]
        @test all(diff(valid) .> 0)

        down = make_trending_prices(:down; n=100, step=1.0)
        ema_down = calculate_indicator(EMA(5), down)
        valid_down = ema_down[6:end]
        @test all(diff(valid_down) .< 0)
    end

    @testset "EMA lags behind price on linear trend" begin
        prices = Float64.(1:100)
        ema = calculate_indicator(EMA(10), prices)

        # On a rising linear trend, EMA should be below current price
        for i in 11:100
            @test ema[i] < prices[i]
        end
    end

    # ── Edge Cases ──

    @testset "Period equals data length" begin
        prices = Float64.(1:10)
        ema = calculate_indicator(EMA(10), prices)

        @test length(ema) == 10
        @test all(isnan, ema[1:9])
        @test ema[10] ≈ 5.5  # SMA of 1:10
    end

    @testset "Period exceeds data length" begin
        prices = Float64.(1:5)
        ema = calculate_indicator(EMA(10), prices)

        @test length(ema) == 5
        @test all(isnan, ema)
    end

    @testset "Single element" begin
        prices = [42.0]
        ema = calculate_indicator(EMA(1), prices)

        @test length(ema) == 1
        @test ema[1] ≈ 42.0
    end

    @testset "Period of 1" begin
        prices = Float64[10, 20, 30, 40, 50]
        ema = calculate_indicator(EMA(1), prices)

        # EMA(1): α = 2/2 = 1.0, so EMA = price exactly
        @test ema[1] ≈ 10.0
        @test ema[2] ≈ 20.0
        @test ema[3] ≈ 30.0
    end

    @testset "Large prices (Bitcoin-scale)" begin
        prices = fill(50_000.0, 100) .+ Float64.(1:100)
        ema = calculate_indicator(EMA(10), prices)
        @test all(isfinite, ema[10:end])
    end

    @testset "Very small prices (sub-penny)" begin
        prices = fill(0.001, 100) .+ Float64.(1:100) .* 0.00001
        ema = calculate_indicator(EMA(10), prices)
        @test all(isfinite, ema[10:end])
    end

    @testset "NaN prefix length matches period - 1" begin
        for p in [2, 5, 10, 20, 50]
            n = max(p + 10, 60)
            prices = Float64.(1:n)
            ema = calculate_indicator(EMA(p), prices)

            @test all(isnan, ema[1:(p - 1)])
            @test !isnan(ema[p])
        end
    end

    # ── Type Stability ──

    @testset "Type stability" begin
        prices = Float64.(1:50)
        @test @inferred(calculate_indicator(EMA(5), prices)) isa Vector{Float64}

        prices32 = Float32.(1:50)
        @test @inferred(calculate_indicator(EMA(5), prices32)) isa Vector{Float32}
    end

    @testset "Float32 support" begin
        prices = Float32.(1:20)
        ema = calculate_indicator(EMA(5), prices)

        @test ema isa Vector{Float32}
        @test ema[5] ≈ Float32(3.0)
    end

    # ── Output Length ──

    @testset "Output length always equals input length" begin
        for n in [1, 5, 10, 50, 200]
            prices = Float64.(1:n)
            for p in [1, 3, 10]
                ema = calculate_indicator(EMA(p), prices)
                @test length(ema) == n
            end
        end
    end
end
