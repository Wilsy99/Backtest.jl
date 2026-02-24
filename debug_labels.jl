using Pkg
Pkg.activate(".")
using Backtest
using Dates

# ── Setup test data ──
n = 500
ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
cl = [100.0 + 0.05i + 2.0 * sin(2π * i / 20) for i in 1:n]
cl = max.(cl, 0.01)
op = vcat([100.0], cl[1:(end - 1)])
sp = [0.5 + 0.3 * abs(sin(0.7i)) for i in 1:n]
hi = max.(op, cl) .+ sp
lo = min.(op, cl) .- sp
vol = [1000.0 + 100.0 * abs(sin(0.3i)) for i in 1:n]

bars = PriceBars(op, hi, lo, cl, vol, ts, TimeBar())
side_vec = Int8.(ones(Int, n))
events = collect(10:20:200)  # ~10 events

barriers = (
    UpperBarrier(d -> d.entry_price * 1.05),
    LowerBarrier(d -> d.entry_price * 0.95),
    TimeBarrier(d -> d.entry_ts + Day(30)),
)

# ── 1. Warmup ──
println("Warming up...")
result = calculate_label(events, bars, barriers; side=side_vec)
println("  Got $(length(result.labels)) labels")

# ── 2. Total calculate_label allocations ──
alloc_total(ev, b, bar; s) = @allocated calculate_label(ev, b, bar; side=s)
alloc_total(events, bars, barriers; s=side_vec)  # compile
alloc_total(events, bars, barriers; s=side_vec)  # warmup

total = minimum([alloc_total(events, bars, barriers; s=side_vec) for _ in 1:5])
println("\n=== Total calculate_label allocations ===")
println("  $total bytes")

# ── 3. Isolate _label_loop! allocations ──
# Reproduce the setup from calculate_label then measure just the loop
function measure_label_loop(events, bars, barriers, side_vec)
    T = eltype(bars.close)
    TS = eltype(bars.timestamp)
    n_events = length(events)
    n_prices = length(bars)
    full_args = (; bars=bars, side=side_vec)
    entry_indices = zeros(Int, n_events)
    entry_timestamps = fill(bars.timestamp[1], n_events)
    buf = Backtest.ExitBuffers(n_events, T, TS)
    entry_adj = Backtest._get_idx_adj(NextOpen())

    alloc = @allocated Backtest._label_loop!(
        events, entry_indices, entry_timestamps, buf, barriers,
        bars, full_args, NextOpen(), entry_adj, n_events, n_prices, T, false
    )
    return alloc
end

measure_label_loop(events, bars, barriers, side_vec)  # compile
measure_label_loop(events, bars, barriers, side_vec)  # warmup
loop_alloc = minimum([measure_label_loop(events, bars, barriers, side_vec) for _ in 1:5])
println("\n=== _label_loop! allocations (just the event loop) ===")
println("  $loop_alloc bytes")

# ── 4. Isolate a single _label_event! ──
function measure_single_event(bars, barriers, side_vec)
    T = eltype(bars.close)
    TS = eltype(bars.timestamp)
    n_prices = length(bars)
    full_args = (; bars=bars, side=side_vec)
    entry_indices = zeros(Int, 1)
    entry_timestamps = fill(bars.timestamp[1], 1)
    buf = Backtest.ExitBuffers(1, T, TS)

    sorted_events = [50]  # single event at index 50
    entry_adj = 1  # NextOpen

    alloc = @allocated Backtest._label_event!(
        1, sorted_events, entry_indices, entry_timestamps, buf, barriers,
        bars, full_args, NextOpen(), entry_adj, n_prices, T
    )
    return alloc
end

measure_single_event(bars, barriers, side_vec)  # compile
measure_single_event(bars, barriers, side_vec)  # warmup
event_alloc = minimum([measure_single_event(bars, barriers, side_vec) for _ in 1:5])
println("\n=== Single _label_event! allocations ===")
println("  $event_alloc bytes  (should be 0 if BarrierArgs is stack-allocated)")

# ── 5. Test BarrierArgs stack allocation directly ──
function measure_barrier_args_creation(bars, side_vec)
    full_args = (; bars=bars, side=side_vec)
    entry_price = 100.0
    entry_ts = bars.timestamp[1]
    entry_side = Int8(1)

    alloc = @allocated begin
        for j in 1:100
            ba = Backtest.BarrierArgs(full_args, j, entry_price, entry_ts, entry_side)
            # Access fields to prevent dead code elimination
            _ = ba.idx
            _ = ba.entry_price
        end
    end
    return alloc
end

measure_barrier_args_creation(bars, side_vec)  # compile
measure_barrier_args_creation(bars, side_vec)  # warmup
ba_alloc = minimum([measure_barrier_args_creation(bars, side_vec) for _ in 1:5])
println("\n=== BarrierArgs creation (100 iterations, no barrier_level calls) ===")
println("  $ba_alloc bytes  (should be 0 if stack-allocated)")

# ── 6. Test BarrierArgs with barrier_level call ──
function measure_barrier_level(bars, barriers, side_vec)
    full_args = (; bars=bars, side=side_vec)
    entry_price = 100.0
    entry_ts = bars.timestamp[1]
    entry_side = Int8(1)
    barrier = barriers[1]  # UpperBarrier

    alloc = @allocated begin
        for j in 2:100
            ba = Backtest.BarrierArgs(full_args, j, entry_price, entry_ts, entry_side)
            level = Backtest.barrier_level(barrier, ba)
        end
    end
    return alloc
end

measure_barrier_level(bars, barriers, side_vec)  # compile
measure_barrier_level(bars, barriers, side_vec)  # warmup
bl_alloc = minimum([measure_barrier_level(bars, barriers, side_vec) for _ in 1:5])
println("\n=== BarrierArgs + barrier_level call (99 iterations) ===")
println("  $bl_alloc bytes  (should be 0 if inlined & stack-allocated)")

# ── 7. Test _check_barriers! (full barrier checking) ──
function measure_check_barriers(bars, barriers, side_vec)
    T = eltype(bars.close)
    TS = eltype(bars.timestamp)
    full_args = (; bars=bars, side=side_vec)
    buf = Backtest.ExitBuffers(1, T, TS)
    entry_price = bars.close[50]
    entry_side = Int8(1)
    entry_ts = bars.timestamp[50]
    n_prices = length(bars)

    alloc = @allocated begin
        for j in 52:100
            ba = Backtest.BarrierArgs(full_args, j, entry_price, entry_ts, entry_side)
            Backtest._check_barriers!(1, j, barriers, ba, bars, entry_price, entry_side, full_args, n_prices, buf)
        end
    end
    return alloc
end

measure_check_barriers(bars, barriers, side_vec)  # compile
measure_check_barriers(bars, barriers, side_vec)  # warmup
cb_alloc = minimum([measure_check_barriers(bars, barriers, side_vec) for _ in 1:5])
println("\n=== BarrierArgs + _check_barriers! (49 iterations) ===")
println("  $cb_alloc bytes")

# ── 8. Weight calculation allocations ──
function measure_weights(bars, events, side_vec, barriers)
    res = calculate_label(events, bars, barriers; side=side_vec)
    T = eltype(bars.close)
    n_prices = length(bars)
    label_classes = unique(res.labels)
    entry_idx = res.entry_indices
    exit_idx = res.exit_indices
    labels = res.labels
    closes = bars.close

    alloc = @allocated Backtest._attribution_weights(
        label_classes, length(entry_idx), n_prices,
        entry_idx, exit_idx, labels, closes, T(1.0), 1
    )
    return alloc
end

measure_weights(bars, events, side_vec, barriers)  # compile
measure_weights(bars, events, side_vec, barriers)  # warmup
w_alloc = minimum([measure_weights(bars, events, side_vec, barriers) for _ in 1:5])
println("\n=== _attribution_weights allocations ===")
println("  $w_alloc bytes")

# ── 9. Masking/filtering allocations ──
function measure_masking(n_events)
    labels = fill(Int8(1), n_events)
    labels[end] = Int8(-99)  # one unfinished

    alloc = @allocated begin
        mask = labels .!= Int8(-99)
    end
    return alloc
end

measure_masking(10); measure_masking(10)
mask_alloc = minimum([measure_masking(10) for _ in 1:5])
println("\n=== Masking allocations (n=10) ===")
println("  $mask_alloc bytes")

# ── 10. Scaling test: does loop allocate per-bar? ──
events_small = [50]
events_large = [50]

# Use n=200 bars
bars_200 = PriceBars(op[1:200], hi[1:200], lo[1:200], cl[1:200], vol[1:200], ts[1:200], TimeBar())
side_200 = Int8.(ones(Int, 200))

# Use n=500 bars (same event at index 50)
bars_500 = bars
side_500 = side_vec

function measure_loop_only(events, bars, barriers, side_vec)
    T = eltype(bars.close)
    TS = eltype(bars.timestamp)
    n_events = length(events)
    n_prices = length(bars)
    full_args = (; bars=bars, side=side_vec)
    entry_indices = zeros(Int, n_events)
    entry_timestamps = fill(bars.timestamp[1], n_events)
    buf = Backtest.ExitBuffers(n_events, T, TS)
    entry_adj = 1

    alloc = @allocated Backtest._label_loop!(
        events, entry_indices, entry_timestamps, buf, barriers,
        bars, full_args, NextOpen(), entry_adj, n_events, n_prices, T, false
    )
    return alloc
end

measure_loop_only(events_small, bars_200, barriers, side_200)
measure_loop_only(events_small, bars_200, barriers, side_200)
a_200 = minimum([measure_loop_only(events_small, bars_200, barriers, side_200) for _ in 1:5])

measure_loop_only(events_small, bars_500, barriers, side_500)
measure_loop_only(events_small, bars_500, barriers, side_500)
a_500 = minimum([measure_loop_only(events_small, bars_500, barriers, side_500) for _ in 1:5])

println("\n=== Scaling test: 1 event, varying n_bars ===")
println("  n=200 bars: $a_200 bytes")
println("  n=500 bars: $a_500 bytes")
delta = a_500 - a_200
println("  delta: $delta bytes")
if delta > 100
    per_bar = delta / (500 - 200)
    println("  ≈ $(round(per_bar, digits=1)) bytes/bar — ALLOCATING PER BAR!")
else
    println("  ✓ Constant — no per-bar allocation")
end

# ── Summary ──
println("\n" * "="^60)
println("SUMMARY")
println("="^60)
println("  Total calculate_label:     $total bytes")
println("  _label_loop! only:         $loop_alloc bytes")
println("  Single _label_event!:      $event_alloc bytes")
println("  BarrierArgs creation:      $ba_alloc bytes")
println("  BarrierArgs + level call:  $bl_alloc bytes")
println("  BarrierArgs + check:       $cb_alloc bytes")
println("  Weights:                   $w_alloc bytes")
println("  Masking:                   $mask_alloc bytes")
println("  Loop overhead (total - loop - weights - mask): $(total - loop_alloc - w_alloc - mask_alloc) bytes")
