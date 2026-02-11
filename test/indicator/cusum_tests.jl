@testset "CUSUM" begin
    # ── Constructor Validation ──

    @testset "Constructor validation" begin
        @test CUSUM(1.0) isa CUSUM
        @test CUSUM(0.5) isa CUSUM
        @test CUSUM(2.0; span=50, expected_value=0.01) isa CUSUM

        # Multiplier must be positive
        @test_throws ArgumentError CUSUM(0.0)
        @test_throws ArgumentError CUSUM(-1.0)

        # Span must be a natural number
        @test_throws ArgumentError CUSUM(1.0; span=0)
        @test_throws ArgumentError CUSUM(1.0; span=-5)
    end

    @testset "Constructor field values" begin
        c = CUSUM(1.5; span=50, expected_value=0.01)
        @test c.multiplier ≈ 1.5
        @test c.span == 50
        @test c.expected_value ≈ 0.01
    end

    @testset "Default parameter values" begin
        c = CUSUM(1.0)
        @test c.span == 100
        @test c.expected_value ≈ 0.0
    end

    # ── Output Properties ──

    @testset "Output values are in {-1, 0, 1}" begin
        bars = make_pricebars(; n=300, volatility=5.0)
        result = calculate_indicator(CUSUM(1.0), bars.close)

        @test all(r ∈ Int8.([-1, 0, 1]) for r in result)
    end

    @testset "Output length equals input length" begin
        for n in [102, 150, 300, 500]
            prices = make_flat_prices(; n=n, price=100.0)
            result = calculate_indicator(CUSUM(1.0), prices)
            @test length(result) == n
        end
    end

    @testset "Output type is Vector{Int8}" begin
        prices = make_flat_prices(; n=200, price=100.0)
        result = calculate_indicator(CUSUM(1.0), prices)
        @test result isa Vector{Int8}
    end

    # ── Warmup Behavior ──

    @testset "Data shorter than warmup returns all zeros" begin
        for n in [1, 10, 50, 100, 101]
            prices = Float64.(1:n) .+ 100.0
            result = calculate_indicator(CUSUM(1.0), prices)
            @test all(result .== 0)
        end
    end

    @testset "First 101 values are always zero" begin
        bars = make_pricebars(; n=300, volatility=10.0)
        result = calculate_indicator(CUSUM(1.0), bars.close)
        @test all(result[1:101] .== 0)
    end

    # ── Flat Prices ──

    @testset "Flat prices produce no jumps" begin
        prices = make_flat_prices(; n=500, price=100.0)
        result = calculate_indicator(CUSUM(1.0), prices)
        @test all(result .== 0)
    end

    @testset "Nearly flat prices produce no jumps with high multiplier" begin
        # Tiny noise relative to a high multiplier should produce no signals
        prices = [100.0 + 0.001 * sin(0.1 * i) for i in 1:500]
        result = calculate_indicator(CUSUM(10.0), prices)
        @test all(result .== 0)
    end

    # ── Jump Detection ──

    @testset "Detects upward jump" begin
        # Flat then sudden up
        prices = make_step_prices(; n=300, low=100.0, high=200.0, step_at=150)
        result = calculate_indicator(CUSUM(1.0), prices)

        # Should have at least one positive signal after the jump
        @test any(result .== 1)
        # The positive signal should occur at or after the jump
        pos_indices = findall(result .== 1)
        @test !isempty(pos_indices)
        @test minimum(pos_indices) >= 102  # after warmup
    end

    @testset "Detects downward jump" begin
        # Flat then sudden down
        prices = make_step_prices(; n=300, low=100.0, high=50.0, step_at=150)
        result = calculate_indicator(CUSUM(1.0), prices)

        # Should have at least one negative signal after the jump
        @test any(result .== -1)
        neg_indices = findall(result .== -1)
        @test !isempty(neg_indices)
        @test minimum(neg_indices) >= 102
    end

    @testset "No false signals before step in step prices" begin
        prices = make_step_prices(; n=300, low=100.0, high=200.0, step_at=200)
        result = calculate_indicator(CUSUM(1.0), prices)

        # Before the step (and after warmup), there should be no signals
        @test all(result[102:199] .== 0)
    end

    # ── Multiplier Sensitivity ──

    @testset "Higher multiplier means fewer signals" begin
        bars = make_pricebars(; n=500, volatility=5.0)
        prices = bars.close

        result_low = calculate_indicator(CUSUM(0.5), prices)
        result_high = calculate_indicator(CUSUM(5.0), prices)

        signals_low = count(result_low .!= 0)
        signals_high = count(result_high .!= 0)

        @test signals_high <= signals_low
    end

    # ── Span Parameter ──

    @testset "Different spans produce valid output" begin
        bars = make_pricebars(; n=300, volatility=3.0)
        for span in [10, 50, 100, 200]
            result = calculate_indicator(CUSUM(1.0; span=span), bars.close)
            @test length(result) == 300
            @test all(r ∈ Int8.([-1, 0, 1]) for r in result)
        end
    end

    # ── Expected Value Parameter ──

    @testset "Non-zero expected value" begin
        bars = make_pricebars(; n=300, volatility=3.0)
        result = calculate_indicator(CUSUM(1.0; expected_value=0.01), bars.close)

        @test length(result) == 300
        @test all(r ∈ Int8.([-1, 0, 1]) for r in result)
    end

    # ── NamedTuple Result Interface ──

    @testset "NamedTuple result" begin
        bars = make_pricebars(; n=200)
        nt = Backtest._indicator_result(CUSUM(1.0), bars.close)

        @test haskey(nt, :cusum)
        @test nt.cusum isa Vector{Int8}
        @test length(nt.cusum) == 200
    end

    # ── Numerical Edge Cases ──

    @testset "Very large prices" begin
        prices = fill(50_000.0, 300) .+ [0.05 * i for i in 1:300]
        result = calculate_indicator(CUSUM(1.0), prices)
        @test length(result) == 300
        @test all(r ∈ Int8.([-1, 0, 1]) for r in result)
    end

    @testset "Very small prices" begin
        prices = fill(0.01, 300) .+ [0.00001 * i for i in 1:300]
        result = calculate_indicator(CUSUM(1.0), prices)
        @test length(result) == 300
        @test all(r ∈ Int8.([-1, 0, 1]) for r in result)
    end

    @testset "Prices must be positive (log requirement)" begin
        # CUSUM uses log(prices), so prices must be positive
        @test_throws DomainError calculate_indicator(
            CUSUM(1.0), vcat(fill(100.0, 50), [0.0], fill(100.0, 250))
        )
    end

    # ── Type Stability ──

    @testset "Type stability" begin
        prices = fill(100.0, 200)
        @test @inferred(calculate_indicator(CUSUM(1.0), prices)) isa Vector{Int8}
    end

    @testset "Float32 support" begin
        c = CUSUM(1.0f0)
        @test c.multiplier isa Float32
        @test c.expected_value isa Float32
    end

    # ── Reproducibility ──

    @testset "Deterministic output" begin
        bars = make_pricebars(; n=300, volatility=5.0)
        result1 = calculate_indicator(CUSUM(1.0), bars.close)
        result2 = calculate_indicator(CUSUM(1.0), bars.close)

        @test result1 == result2
    end
end
