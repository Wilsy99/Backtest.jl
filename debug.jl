using Pkg
Pkg.activate(".")
# debug.jl — Run with: julia --project debug.jl
using Backtest

prices_small = collect(100.0:299.0)   # n=200
prices_large = collect(100.0:2099.0)  # n=2000

# ─── 1. Baseline: just the result vector ───────────────────────────────────
# If zeros(Int8, n) accounts for most of the allocation, overhead is fixed.
alloc_zeros_small(n) = @allocated zeros(Int8, n)
alloc_zeros_small(200)
z_small = alloc_zeros_small(200)

alloc_zeros_large(n) = @allocated zeros(Int8, n)
alloc_zeros_large(2000)
z_large = alloc_zeros_large(2000)

println("=== 1. zeros(Int8, n) ===")
println("  n=200:  $z_small bytes")
println("  n=2000: $z_large bytes")
println("  delta:  $(z_large - z_small) bytes (should ≈ 1800 = pure data growth)")

# ─── 2. Full function at both sizes ────────────────────────────────────────
# If overhead is constant, delta ≈ data growth. If it scales, there's a bug.
alloc_cusum_small(p) = @allocated Backtest._calculate_cusum(p, 1.0, 100, 0.0)
Backtest._calculate_cusum(prices_small, 1.0, 100, 0.0)
alloc_cusum_small(prices_small)
a_small = alloc_cusum_small(prices_small)

alloc_cusum_large(p) = @allocated Backtest._calculate_cusum(p, 1.0, 100, 0.0)
Backtest._calculate_cusum(prices_large, 1.0, 100, 0.0)
alloc_cusum_large(prices_large)
a_large = alloc_cusum_large(prices_large)

println("\n=== 2. _calculate_cusum (full) ===")
println("  n=200:  $a_small bytes")
println("  n=2000: $a_large bytes")
println("  delta:  $(a_large - a_small) bytes (should ≈ 1800)")
println("  overhead n=200:  $(a_small - z_small) bytes")
println("  overhead n=2000: $(a_large - z_large) bytes")

# ─── 3. Isolate the @warn macro ────────────────────────────────────────────
# Call with n > 101 (no warn) vs n <= 101 (warn fires)
prices_short = fill(100.0, 50)
alloc_short(p) = @allocated Backtest._calculate_cusum(p, 1.0, 100, 0.0)
Backtest._calculate_cusum(prices_short, 1.0, 100, 0.0)  # warmup (triggers warn)
alloc_short(prices_short)
a_short = alloc_short(prices_short)

println("\n=== 3. @warn path (n=50, triggers warning) ===")
println("  n=50:  $a_short bytes")
println(
    "  zeros(Int8,50) baseline: $(let f(n)=@allocated(zeros(Int8,n)); f(50); f(50) end) bytes",
)

# ─── 4. Isolate warmup loop vs post-warmup loop ────────────────────────────
# n=102 (1 post-warmup iteration) vs n=200 (99 iterations) vs n=2000 (1899)
prices_102 = fill(100.0, 102)
alloc_102(p) = @allocated Backtest._calculate_cusum(p, 1.0, 100, 0.0)
Backtest._calculate_cusum(prices_102, 1.0, 100, 0.0)
alloc_102(prices_102)
a_102 = alloc_102(prices_102)

println("\n=== 4. Scaling with post-warmup iterations ===")
println("  n=102  (1 iter):    $a_102 bytes")
println("  n=200  (99 iter):   $a_small bytes")
println("  n=2000 (1899 iter): $a_large bytes")
println("  If these three overhead values are ≈equal, loops are allocation-free.")
println(
    "  overhead 102:  $(a_102 - (let f(n)=@allocated(zeros(Int8,n)); f(102); f(102) end)) bytes",
)
println("  overhead 200:  $(a_small - z_small) bytes")
println("  overhead 2000: $(a_large - z_large) bytes")

# ─── 5. calculate_feature wrapper overhead ────────────────────────────────
feat = CUSUM(1.0)
alloc_calc(feat, p) = @allocated calculate_feature(feat, p)
calculate_feature(feat, prices_small)
alloc_calc(feat, prices_small)
a_calc = alloc_calc(feat, prices_small)

println("\n=== 5. calculate_feature vs _calculate_cusum (n=200) ===")
println("  _calculate_cusum:   $a_small bytes")
println("  calculate_feature: $a_calc bytes")
println("  wrapper overhead:    $(a_calc - a_small) bytes (should be 0)")

# ─── 6. Functor / NamedTuple merge overhead ─────────────────────────────────
using Dates
bars = let n = 200
    ts = [DateTime(2024, 1, 1) + Day(i - 1) for i in 1:n]
    cl = [100.0 + 0.05i + 2.0 * sin(2π * i / 20) for i in 1:n]
    cl = max.(cl, 0.01)
    op = vcat([100.0], cl[1:(end - 1)])
    sp = [0.5 + 0.3 * abs(sin(0.7i)) for i in 1:n]
    hi = max.(op, cl) .+ sp
    lo = min.(op, cl) .- sp
    vol = [1000.0 + 100.0 * abs(sin(0.3i)) for i in 1:n]
    PriceBars(op, hi, lo, cl, vol, ts, TimeBar())
end

alloc_functor(feat, b) = @allocated feat(b)
feat(bars)
alloc_functor(feat, bars)
a_func = alloc_functor(feat, bars)

println("\n=== 6. Functor with PriceBars (n=200) ===")
println("  functor:            $a_func bytes")
println("  _calculate_cusum:   $a_small bytes")
println("  merge overhead:     $(a_func - a_small) bytes")

# ─── Summary ────────────────────────────────────────────────────────────────
println("\n=== DIAGNOSIS ===")
overhead_200 = a_small - z_small
overhead_2000 = a_large - z_large
if abs(overhead_200 - overhead_2000) < 100
    println("✓ Overhead is CONSTANT (~$(overhead_200) bytes) — not a scaling bug.")
    println("  Likely cause: @warn macro infrastructure / logging scaffolding.")
    println(
        "  Safe to increase budget overhead constant to $(max(overhead_200, overhead_2000) + 256) bytes.",
    )
else
    println("✗ Overhead SCALES with n — investigate further!")
    println("  overhead n=200:  $overhead_200")
    println("  overhead n=2000: $overhead_2000")
    println(
        "  per-element overhead: $((overhead_2000 - overhead_200) / 1800) bytes/element"
    )
end
