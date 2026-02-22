#! format: off
bars |>
    EMA(10, 20) |>
    CUSUM(1) |>
    @Event(:cusum != 0) do # Global filter
        @Side(:ema_10 > :ema_20, Long())
        @Side(:ema_10 < :ema_20, Short())
    end |>
    Label!(;
        entry_basis=NextOpen(),
        @OnSide(
            Long(),
            @UpperBarrier(:entry_price * 1.20, label = Win(), exit_basis = Immediate()),
            @LowerBarrier(:entry_price * 0.95, label = Loss(), exit_basis = Immediate()),
            @ConditionBarrier(:ema_10 < :ema_20 && :close > :entry_price, label = Win()),
            @ConditionBarrier(:ema_10 < :ema_20 && :close <= :entry_price, label = Loss()),
        ),
        @OnSide(
            Short(),
            @UpperBarrier(:entry_price * 1.10, label = Loss(), exit_basis = Immediate()),
            @LowerBarrier(:entry_price * 0.90, label = Win(), exit_basis = Immediate()),
            @ConditionBarrier(:ema_10 > :ema_20 && :close < :entry_price, label = Win()),
            @ConditionBarrier(:ema_10 > :ema_20 && :close >= :entry_price, label = Loss()),
        ),
        @TimeBarrier(:entry_ts + Day(10), label = Neutral(), exit_basis = NextOpen()),
)
#! format: on