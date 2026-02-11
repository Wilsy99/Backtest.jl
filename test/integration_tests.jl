@testset "Integration — Full Pipeline" begin
    bars = make_pricebars(; n=300, volatility=3.0)

    # ── EMA → Crossover pipeline ──
    @testset "EMA → Crossover produces valid sides" begin
        nt = EMA(10, 50)(bars)
        cross = Crossover(:ema_10, :ema_50; direction=LongShort())
        result = cross(nt)

        @test haskey(result, :bars)
        @test haskey(result, :ema_10)
        @test haskey(result, :ema_50)
        @test haskey(result, :side)
        @test all(s ∈ Int8.([-1, 0, 1]) for s in result.side)
    end

    # ── EMA → Event → Label pipeline ──
    @testset "EMA → Event → Label full pipeline" begin
        nt = EMA(10, 50)(bars)

        # Event: when short EMA crosses above long EMA
        evt = Event(d -> d.ema_10 .> d.ema_50; match=:all)
        nt_with_events = evt(nt)

        @test haskey(nt_with_events, :event_indices)
        @test length(nt_with_events.event_indices) > 0

        # Label with barriers
        upper = UpperBarrier(d -> d.entry_price * 1.05)
        lower = LowerBarrier(d -> d.entry_price * 0.95)
        time_b = TimeBarrier(d -> d.entry_ts + Day(20))

        lab = Label(upper, lower, time_b; entry_basis=NextOpen(), drop_unfinished=true)
        result = lab(nt_with_events)

        @test haskey(result, :labels)
        labels = result.labels
        @test labels isa Backtest.LabelResults
        @test all(labels.t₁ .>= labels.t₀)
        @test all(l ∈ Int8.([-1, 0, 1]) for l in labels.label)
    end

    # ── Pipeline with >> operator ──
    @testset ">> operator full chain" begin
        evt = Event(d -> d.ema_10 .> d.ema_50; match=:all)

        upper = UpperBarrier(d -> d.entry_price * 1.05)
        lower = LowerBarrier(d -> d.entry_price * 0.95)
        time_b = TimeBarrier(d -> d.entry_ts + Day(20))

        lab = Label!(upper, lower, time_b; entry_basis=NextOpen())

        job = bars >> EMA(10, 50) >> evt >> lab
        result = job()

        @test result isa Backtest.LabelResults
        @test all(result.t₁ .>= result.t₀)
        @test length(result.label) == length(result.ret)
        @test length(result.label) == length(result.log_ret)
    end

    # ── Return Consistency ──
    @testset "Returns are consistent with labels" begin
        evt = Event(d -> d.ema_10 .> d.ema_50; match=:all)

        upper = UpperBarrier(d -> d.entry_price * 1.10)
        lower = LowerBarrier(d -> d.entry_price * 0.90)

        nt = EMA(10, 50)(bars)
        nt = evt(nt)

        lab = Label!(upper, lower; entry_basis=NextOpen())
        result = lab(nt)

        for i in eachindex(result.label)
            if result.label[i] == Int8(1)  # upper barrier hit
                @test result.ret[i] > 0
            elseif result.label[i] == Int8(-1)  # lower barrier hit
                @test result.ret[i] < 0
            end
        end
    end

    # ── Log return consistency ──
    @testset "Log returns match simple returns" begin
        evt = Event(d -> d.ema_10 .> d.ema_50; match=:all)

        upper = UpperBarrier(d -> d.entry_price * 1.05)
        lower = LowerBarrier(d -> d.entry_price * 0.95)
        time_b = TimeBarrier(d -> d.entry_ts + Day(20))

        nt = EMA(10, 50)(bars)
        nt = evt(nt)

        lab = Label!(upper, lower, time_b; entry_basis=NextOpen())
        result = lab(nt)

        for i in eachindex(result.ret)
            @test result.log_ret[i] ≈ log1p(result.ret[i]) atol = 1e-12
        end
    end

    # ── Different Directions ──
    @testset "LongOnly pipeline" begin
        nt = EMA(10, 50)(bars)
        cross = Crossover(:ema_10, :ema_50; direction=LongOnly())
        result = cross(nt)
        @test all(s ∈ Int8.([0, 1]) for s in result.side)
    end

    @testset "ShortOnly pipeline" begin
        nt = EMA(10, 50)(bars)
        cross = Crossover(:ema_10, :ema_50; direction=ShortOnly())
        result = cross(nt)
        @test all(s ∈ Int8.([-1, 0]) for s in result.side)
    end

    # ── CUSUM as event source ──
    @testset "CUSUM → Event → Label pipeline" begin
        nt = CUSUM(1.0)(bars)
        evt = Event(d -> d.cusum .!= 0; match=:all)
        nt = evt(nt)

        if !isempty(nt.event_indices)
            upper = UpperBarrier(d -> d.entry_price * 1.05)
            lower = LowerBarrier(d -> d.entry_price * 0.95)
            time_b = TimeBarrier(d -> d.entry_ts + Day(10))

            lab = Label!(upper, lower, time_b; entry_basis=NextOpen())
            result = lab(nt)

            @test result isa Backtest.LabelResults
            @test all(l ∈ Int8.([-1, 0, 1]) for l in result.label)
        end
    end

    # ── Pipeline preserves all intermediate data ──
    @testset "Pipeline data preservation" begin
        nt1 = EMA(10, 50)(bars)
        @test haskey(nt1, :bars)
        @test haskey(nt1, :ema_10)
        @test haskey(nt1, :ema_50)

        cross = Crossover(:ema_10, :ema_50; direction=LongShort())
        nt2 = cross(nt1)
        @test haskey(nt2, :bars)
        @test haskey(nt2, :ema_10)
        @test haskey(nt2, :ema_50)
        @test haskey(nt2, :side)

        evt = Event(d -> d.ema_10 .> d.ema_50; match=:all)
        nt3 = evt(nt2)
        @test haskey(nt3, :bars)
        @test haskey(nt3, :ema_10)
        @test haskey(nt3, :ema_50)
        @test haskey(nt3, :side)
        @test haskey(nt3, :event_indices)
    end

    # ── Empty events ──
    @testset "Pipeline with no events" begin
        # Condition that can never be true
        evt = Event(d -> d.bars.close .> 1e10; match=:all)
        nt = EMA(10, 50)(bars)
        nt = evt(nt)
        @test isempty(nt.event_indices)

        upper = UpperBarrier(d -> d.entry_price * 1.05)
        lower = LowerBarrier(d -> d.entry_price * 0.95)

        lab = Label!(upper, lower; entry_basis=NextOpen())
        result = lab(nt)

        @test result isa Backtest.LabelResults
        @test isempty(result.label)
    end
end
