# ftmo-1step-ea

MetaTrader 5 Expert Advisor for an FTMO 1-Step challenge. [SPEC.md](SPEC.md) defines the strategy;
[CHANGELOG.md](CHANGELOG.md) records every change to it.

> Status: EA built (build steps 1-5). Backtesting skipped by owner decision (2026-10-05):
> the strategy goes live on the challenge without backtest evidence, at 0.25% risk.

## Environment

| Item | Path |
|---|---|
| MetaEditor | `D:\Program Files (x86)\New folder\MetaEditor64.exe` |
| MT5 data folder | `C:\Users\visio\AppData\Roaming\MetaQuotes\Terminal\FD4EE2C8A393414AD14B68905678707F` |
| Trading server | OANDA-Prop Trader (FTMO). Server clock = New York time + 7h |
| Symbols | `EURUSD.sim`, `GBPUSD.sim` |
| Logs (CSV) | `C:\Users\visio\AppData\Roaming\MetaQuotes\Terminal\Common\Files\` |

## Building

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compile.ps1 path\to\EA.mq5
```

The script runs MetaEditor headless, prints errors/warnings, and exits `0` only when
the log reports `0 errors` (MetaEditor's own exit code is not reliable).
Standard library includes (e.g. `<Trade\Trade.mqh>`) resolve from the data folder's `MQL5\Include`.

Source files should be saved as UTF-8 so git can diff them (MetaEditor may default to UTF-16).

Tests are MT5 scripts in `tests/` (TimeHelper, RiskManager, Signals, Logger). Compile, copy the
`.ex5` to `MQL5\Scripts\ftmo-1step-ea\`, run on any chart; results go to `MQL5\Files\*Tests.txt`.

## Running on the challenge

The order handling has never run against a live server (no backtest or demo run), so the
first trades deserve a close look.

### One-time setup

1. **Push notifications.** Install the MetaTrader 5 app on your phone and copy its MetaQuotes ID
   (Settings > Messages). In MT5 desktop: Tools > Options > Notifications, tick
   "Enable Push notifications", paste the ID, click Test. The EA pushes kill switch, floor guard,
   order errors and start/stop.
2. **Algorithmic trading.** Tools > Options > Expert Advisors: tick "Allow algorithmic trading".
   Make sure the Algo Trading button in the toolbar is green.
3. **Keep the terminal running** Monday to Friday, on this PC (sleep off) or a VPS. Restarts are
   fine: the EA saves its state and catches up on trades that closed while it was off.

### Attaching the EA

Open one chart, `EURUSD.sim` H1, and drag **TrendPullback** onto it. One instance trades both
symbols. Inputs:

| Input | Value |
|---|---|
| InpSymbol1 / InpSymbol2 | `EURUSD.sim` / `GBPUSD.sim` |
| InpMaxSpreadPips1 / 2 | 2.0 / 2.5 |
| InpInitialBalance | The challenge's **initial balance** (required; the EA won't start without it) |
| InpRiskPercent | **0.25** for the first two weeks, then 0.5 |
| InpHighestEodBalance | 0 on a fresh challenge. If attaching later, the highest end-of-day balance from the FTMO dashboard |
| InpFloorGuardReviewed | false |
| InpTakeProfitPips | 40 |
| InpUseNewsFilter | true |
| InpMagic | 20261002 (don't change once trading; the EA only manages its own magic number) |
| InpLogTag | empty |

On the Common tab tick "Allow Algo Trading", then OK.

### Check right after attaching

- Experts tab shows `started. Initial balance ..., risk 0.25%` and a push arrives on your phone.
- The **daily floor** and **trailing floor** in that message match the FTMO dashboard's Max Daily
  Loss and Max Loss levels. If they don't, remove the EA and check InpInitialBalance.
- A chart smiley/hat icon in the top-right corner means the EA is running.

### Day to day

- Entries happen only on H1 bars opening 07:00-14:00 London, so most hours nothing happens.
- Trade log and daily log: `TrendPullback_<login>_20261002_trades.csv` and `_daily.csv` in the
  Logs folder above.
- After two weeks: open the EA's inputs (F7 on the chart), set InpRiskPercent to 0.5, OK.

### If a push says...

- **KILL SWITCH**: the EA closed everything and stops entries until the next FTMO day (midnight
  Prague). Nothing to do.
- **FLOOR GUARD**: entries are blocked until you review. To resume: set InpFloorGuardReviewed to
  true, OK, then set it back to false. If equity is still within 1.5% of the floor, it blocks again.
- **ERROR**: an order failed. Check the Experts and Journal tabs, and the position in the Trade tab.
