# CLAUDE.md

Working rules for this repo. Read SPEC.md before doing anything.

## What this project is

An MT5 Expert Advisor in MQL5 that trades an FTMO 1-Step challenge. SPEC.md defines every rule and number. Your job is to build exactly what it says, not to improve the strategy on your own.

## Rules

- SPEC.md is the source of truth. If something in it is unclear or looks wrong, stop and ask. Don't guess.
- Never change a strategy rule, parameter or default value unless I ask. Every change gets a line in CHANGELOG.md with the date, what changed, why, and the backtest that supports it.
- Never run or open results on the out-of-sample period (the most recent 2 years) unless I explicitly say the rules are frozen.
- Never attach the EA to a live or challenge account, or change anything that places real orders, without asking first.
- Compile after every change to an .mq5 or .mqh file. A change isn't done until it compiles with zero errors and zero warnings.
- Commit after each working step with a clear message. Don't bundle unrelated changes.
- Follow the build order in SPEC.md section 14. Don't skip ahead.

## Code style

- Plain, readable MQL5. Short functions with clear names. Comments explain why, not what.
- Signals use closed bars only. Nothing calculated on the forming bar.
- All FTMO limits and EA risk limits live in FtmoRules.mqh and RiskManager.mqh. No magic numbers anywhere else.
- Every order has its stop loss and take profit attached at placement.
- Check and log the result of every trade operation. Never assume an order went through.
- Only manage positions with this EA's magic number.

## Testing

- TimeHelper needs tests on known dates on both sides of each daylight saving change before anything depends on it.
- When reporting a backtest, always include: date range, symbols, model used (real ticks), number of trades, win rate, profit factor, max drawdown from highest end-of-day balance, and worst single day.
- Save Strategy Tester reports and logs to /reports with the date and settings in the file name.

## Not in scope for version 1

Volume or tick volume, trailing stops, breakeven, partial closes, extra symbols, MetaApi or any outside bridge.
