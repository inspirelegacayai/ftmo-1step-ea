# SPEC: Trend Pullback EA for FTMO 1-Step

Version 1.0. This is the source of truth for the strategy. If the code and this file disagree, this file wins. Any change to a rule or number here needs a backtest and an entry in CHANGELOG.md.

## 1. Goal

Pass an FTMO 1-Step challenge, then keep running the same system on the funded account. The style is lots of small wins: 30 to 50 pip targets, low risk per trade, no big days. Passing slowly is fine. Breaching is not.

## 2. Account rules (FTMO 1-Step)

These are hard limits set by FTMO. The EA's own limits (section 6) sit well inside them.

- Profit target: 10% of initial balance.
- Maximum Daily Loss: 3% of initial balance. Floating P&L counts. Daily floor = balance at the start of the FTMO day minus 3% of initial balance. The FTMO day resets at midnight CE(S)T (Europe/Prague time).
- Maximum Loss: 10% of initial balance, trailing at end of day. Floor = highest end-of-day balance minus 10% of initial balance. It updates once a day after 23:59:59 CE(S)T and stops trailing once it reaches the initial balance.
- Best Day rule: the most profitable day can't be more than 50% of the total profit from all positive days. Not an instant breach, but it delays passing and payouts. Also applies on the funded account.

All of these numbers go in one config file (FtmoRules.mqh) so nothing is hardcoded twice.

## 3. Markets and timeframes

- Symbols: EURUSD, GBPUSD. FTMO symbol names may have a suffix, so symbol names are inputs.
- Trend timeframe: H4.
- Signal timeframe: H1.
- All signals use closed bars only (bar index 1 and older). Nothing is calculated on the bar that's still forming.
- The EA evaluates signals once per symbol, on the first tick of each new H1 bar.

## 4. Entry rules

### Long

All of these must be true:

1. Trend (H4, last closed bar): close > EMA(200) and EMA(50) > EMA(200).
2. Pullback (H1, last 3 closed bars, index 1 to 3):
   - at least one bar has low <= EMA(20) at that bar
   - no bar closed below EMA(50) at that bar
   - the lowest RSI(14) across those bars is below 45
3. Trigger (H1, bar 1):
   - close > EMA(20)
   - close > high of bar 2
   - close > open (bullish candle)

### Short

Mirror image:

1. Trend (H4): close < EMA(200) and EMA(50) < EMA(200).
2. Pullback (H1, bars 1 to 3): at least one bar has high >= EMA(20), no bar closed above EMA(50), highest RSI(14) above 55.
3. Trigger (H1, bar 1): close < EMA(20), close < low of bar 2, close < open.

### Entry execution

Market order on the first tick of the new H1 bar, with stop loss and take profit attached to the order so they live on FTMO's server.

## 4A. Candidate entries v2 (under test, added 2026-10-16)

The section 4 rules took 6 trades in 16 months on the FTMO server's data and every loosening lost money (CHANGELOG 2026-10-15). Two replacement entries are being tested. Everything else (sections 2, 3, 5, 6, 7, 8, 9) applies unchanged to both, including the London session filter, the 15 to 40 pip stop-size filter, the 2-per-day and position caps, and all exits. Only one entry runs at a time, chosen by an input that is test-only until one candidate is approved and section 4 is rewritten.

Choices marked *(choice)* are where published versions of the setup differ; they were picked before testing and are not to be tuned on the hold-out data.

### A. London breakout

1. Asian range: the highest high and lowest low of the H1 bars that open from 00:00 to 06:00 London time on the current London date (7 bars, all closed by 07:00).
2. Long: H1 bar 1 opened at 07:00 London or later on the same date and closed above the Asian range high. Short: closed below the Asian range low. *(choice: a confirmed close, not a stop order at the range edge)*
3. Only the first bar 1 of the day that closes outside the range counts, per symbol. If that signal is skipped by a filter or a limit, there is no second attempt that day. *(choice)*
4. Stop: long = Asian range low minus 3 pips; short = Asian range high plus 3 pips. *(choice: the opposite side of the range, not its midpoint)* The 15 to 40 pip stop-size filter applies, so days with a wide range are skipped.
5. Target: TakeProfitPips (section 7). No trend filter. *(choice)*
6. Execution as section 4: market order on the first tick of the new H1 bar, stop and target attached.

Development variants (added 2026-10-16 after the first in-sample run gave PF 1.18 against the 1.2 bar; in-sample only, the best one goes to the hold-out once):

- A1, trend filter: rules 1 to 6, plus longs only when the section 4 H4 trend is up (close > EMA(200) and EMA(50) > EMA(200)), shorts only when it is down.
- A2, mid-range stop: rules 1 to 6, but the stop is the midpoint of the Asian range minus 3 pips for a long, plus 3 pips for a short.
- A3: both A1 and A2.

No other breakout variants are to be tried before the hold-out.

### B. Holy Grail (Raschke/Connors, from section 10)

1. ADX(14) on H1, bar 1: above 30, and higher than on bar 2.
2. Direction: long when +DI > -DI on bar 1, short when -DI > +DI. *(choice: DI decides direction)*
3. Touch: long when bar 1 low <= EMA(20) at bar 1; short when bar 1 high >= EMA(20). *(choice: bar 1 only)*
4. Order: long = buy stop 1 pip above bar 1 high; short = sell stop 1 pip below bar 1 low. Placed on the first tick of the new H1 bar, with stop and target attached. Skipped if price is already beyond the order price.
5. Stop: section 7 rule (lowest low of bars 1 to 3 minus 3 pips, or highest high plus 3 pips). Size and stop-size filter measured from the order price. Target: TakeProfitPips from the order price, re-aligned to the fill.
6. Cancelled if not filled within 3 H1 bars, at the end of the London session (15:00), by the Friday close, or by the kill switch. *(choice: also cancelled at session end)*
7. A pending order counts as a position for the per-symbol and total caps. It counts toward the 2 entries per FTMO day when it fills; no new order is placed if fills plus pending orders already reach 2.

## 5. Filters (skip the trade if any fail)

- Session: the new H1 bar opens between 07:00 and 15:00 London time (Europe/London, daylight saving aware).
- News: no new entries from 30 minutes before to 30 minutes after a high-impact event for USD, EUR or GBP. Use the MQL5 economic calendar functions. These don't work in the Strategy Tester, so the filter is an input (UseNewsFilter) that is off in testing and on live.
- Spread: skip if current spread is above the input limit (start at 2.0 pips EURUSD, 2.5 pips GBPUSD).
- Holidays: no new entries from December 24 through January 2.
- Stop size: skip if the stop distance (section 7) is under 15 pips or over 40 pips.

## 6. Risk rules

- Risk per trade: input, default 0.5% of initial balance. Lot size = risk amount / (stop distance in pips x pip value per lot), rounded down to the symbol's volume step and kept within min and max volume.
- Starting ramp: the first two weeks live on the challenge run at 0.25%. This is set manually through the input, not automatic.
- Max one open position per symbol. Max two open positions total. Max two new entries per FTMO day.
- Losing streak brake: after 3 losing trades in a row, risk drops to 0.25% until the next winning trade.
- Daily kill switch: if equity falls to (start-of-day balance minus 1.5% of initial balance), close all positions, block new entries until the next FTMO day, and send a push notification.
- Trailing floor guard: track the trailing Maximum Loss floor from section 2.
  - Equity within 3% of initial balance above the floor: risk drops to 0.25%.
  - Equity within 1.5% of initial balance above the floor: block new entries and send a push notification. Resume only after manual review (input flag).

## 7. Exit rules

- Stop loss, long: lowest low of H1 bars 1 to 3, minus 3 pips. Short: highest high of bars 1 to 3, plus 3 pips. Measured from the actual fill price.
- Take profit: fixed, input TakeProfitPips, default 40. Test 30, 40 and 50.
- Time stop: close at market if the trade has been open 24 hours.
- Weekend: close everything at 20:00 London time on Friday.
- Version 1 has no trailing stops, no breakeven moves and no partial closes.

## 8. State and safety

- The EA only touches positions with its own magic number.
- State that must survive a restart (start-of-day balance, highest end-of-day balance, losing streak count, entries today, kill switch status) is saved to terminal global variables or a file, and reloaded on init.
- Server time to London time and Prague time conversion goes in one helper with explicit daylight saving rules (UK/EU: last Sunday of March and October). In the Strategy Tester, TimeGMT() returns server time, so the helper can't rely on it. The FTMO server's GMT offset and its daylight saving schedule must be checked and written into this helper, with tests on known dates on both sides of each change.
- Push notifications (SendNotification) for: kill switch, floor guard, any order error, EA start and stop.

## 9. Logging

- Trade log CSV: entry time, symbol, direction, entry price, stop, target, lot size, risk %, spread at entry, exit time, exit price, exit reason (TP, SL, time stop, Friday close, kill switch), pips, P&L.
- Daily log CSV: FTMO date, start balance, end balance, lowest equity during the day, trades taken, kill switch triggered (yes/no).
- The daily log feeds the Best Day check and the Monte Carlo.

## 10. Benchmark EA (Holy Grail)

> **Now candidate B in section 4A (2026-10-16)**, with the open points made exact there. The original benchmark text is kept for reference.

A second EA using the published Raschke/Connors Holy Grail entry, so we can tell whether our rules beat a known setup:

- H1, ADX(14) above 30 and rising.
- Price pulls back to touch EMA(20).
- Long: buy stop 1 pip above the high of the touch bar. Short: sell stop 1 pip below the low. Cancel if not filled within 3 bars.
- Same exits, filters, risk rules and logging as the main EA, so the only difference is the entry.

## 11. Backtest protocol

### Candidate test plan (section 4A, 2026-10-16)

Data: the FTMO server's own real ticks, the only history available. Every tick based on real ticks, 0.5% risk, TakeProfitPips 40, $10,000 deposit, EURUSD.sim and GBPUSD.sim.

- In-sample: 2025-06-01 to 2026-05-31. All development and any adjustment happens here.
- Hold-out: 2026-06-01 to 2026-10-14. Not run until the owner freezes a candidate's rules. Run once per frozen candidate. A candidate that fails it is dropped, not adjusted.
- Go-live bar to replace the live entry (confirmed by the owner 2026-10-16, before any candidate result was seen): in-sample profit factor above 1.2 with at least 40 trades, and on the hold-out a profit factor above 1.0 with no FTMO breach in the 1-Step replay. Both must hold.

> **Skipped (owner decision 2026-10-05).** The FTMO server only has history from April 2025, and getting long tick history elsewhere (Dukascopy) was rate-limited to days of downloading. The owner chose to go straight to the challenge at 0.25% risk instead. Consequence: the strategy goes live with no evidence that it is profitable, and none of the pass criteria below or the section 12 go-live bar are checked. The risk rules in section 6 still cap losses. The protocol below is kept for reference if backtesting is picked up later.

- Strategy Tester, "Every tick based on real ticks," with as much history as can be obtained (aim for 8 to 10 years, minimum 5). The FTMO server (OANDA-Prop Trader) only provides history from April 2025, so long history needs an outside source imported as custom symbols on the FTMO server clock (New York time + 7h), with the FTMO server's own ticks as confirmation.
- Commission per lot set to match the FTMO account specs.
- In-sample: everything except the most recent 2 years. All rule tuning happens here only.
- Out-of-sample: the most recent 2 years. Not opened until rules are frozen. Run once. If it fails, the strategy goes back to the drawing board, it doesn't get tuned on this data.
- Runs: main EA at TP 30, 40, 50. Benchmark EA at TP 40. All at 0.5% risk.

### Pass criteria (out-of-sample, 0.5% risk)

- At least 150 trades.
- Profit factor above 1.3.
- Max drawdown from the highest end-of-day balance under 5%.
- No single FTMO day worse than -1.5% (the kill switch should guarantee this, so a violation means a bug).

## 12. Monte Carlo (Python)

> **Skipped (owner decision 2026-10-05)**, along with backtesting, which produced its input. It could be run later on the challenge's own daily log once there are enough days.

Script: analysis/montecarlo.py. Reads the daily log.

- Resample whole trading days (not single trades), 10,000 runs.
- Apply the 1-Step rules exactly: 3% daily limit using each day's lowest equity, end-of-day trailing floor that locks at initial balance, Best Day ratio when the 10% target is reached.
- Run at 0.25%, 0.5% and 0.75% risk.
- Output per risk level: chance of passing before a breach, chance of breaching daily loss, chance of breaching the trailing floor, median trading days to pass, chance the Best Day rule delays passing.
- Go-live bar: at least 70% chance of passing before a breach at 0.5% risk.

## 13. Repo layout

```
/ea/TrendPullback.mq5
/ea/HolyGrailBenchmark.mq5
/ea/include/FtmoRules.mqh
/ea/include/TimeHelper.mqh
/ea/include/RiskManager.mqh
/ea/include/Logger.mqh
/analysis/montecarlo.py
/reports/            (Strategy Tester reports and logs)
SPEC.md
CLAUDE.md
CHANGELOG.md
```

## 14. Build order

1. Setup check: Git, MT5 data folder, command-line compile through MetaEditor.
2. TimeHelper with tests. Nothing else gets built until session times are proven correct.
3. FtmoRules and RiskManager (sizing, kill switch, floor guard, streak brake, state persistence).
4. Main EA signals and exits.
5. Logger.
6. ~~Benchmark EA.~~ Skipped.
7. ~~In-sample backtests.~~ Skipped.
8. ~~Freeze rules, run out-of-sample.~~ Skipped.
9. ~~Monte Carlo.~~ Skipped.
10. Challenge at 0.25% for two weeks, then 0.5%. (Was "If it passes"; steps 6 to 9 skipped by owner decision 2026-10-05.)

## 15. To verify before backtesting

- FTMO server GMT offset and daylight saving schedule, and how midnight CE(S)T maps to server time.
- Exact symbol names on the challenge account.
- Commission per lot and contract size.
- How much real tick history the FTMO server provides for each symbol.
- That the account dashboard shows the 1-Step rules exactly as in section 2.

## 16. Not in version 1

Volume or tick volume of any kind, trailing stops, breakeven, partial closes, extra symbols. Each can be tested later, one at a time, as its own change.
