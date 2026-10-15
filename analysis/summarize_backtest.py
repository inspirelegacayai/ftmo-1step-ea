"""Summarises Strategy Tester runs from the EA's trade and daily CSV logs.

Reports what CLAUDE.md asks for on every backtest: trades, win rate, profit factor,
max drawdown from the highest end-of-day balance, and worst single day. Also replays
the FTMO 1-Step rules (SPEC section 2) on the daily log: whether and when the 10% target
was reached before a daily-loss or trailing-floor breach, and the Best Day ratio.

The EA writes tester logs to the MT5 Common\\Files folder as
TrendPullback_tester_<variant>[_<tag>]_trades.csv and ..._daily.csv.

Usage:
  python analysis/summarize_backtest.py [--files <Common\\Files>] [--out reports/<name>.md] [run names...]
With no run names, every TrendPullback_tester_*_trades.csv found is summarised.
"""
import argparse
import csv
import sys
from pathlib import Path

DEFAULT_FILES = Path.home() / "AppData/Roaming/MetaQuotes/Terminal/Common/Files"
PREFIX = "TrendPullback_tester_"

# SPEC section 2, as % of initial balance
PROFIT_TARGET_PCT = 10.0
MAX_DAILY_LOSS_PCT = 3.0
MAX_LOSS_PCT = 10.0
BEST_DAY_MAX_SHARE = 0.50


def read_csv(path: Path) -> list:
    if not path.exists():
        return []
    with open(path, newline="", encoding="ascii", errors="replace") as f:
        return list(csv.DictReader(f))


def trade_stats(trades: list) -> dict:
    pnl = [float(t["pnl"]) for t in trades]
    wins = [p for p in pnl if p > 0]
    losses = [p for p in pnl if p < 0]
    gross_win, gross_loss = sum(wins), -sum(losses)
    reasons = {}
    for t in trades:
        reasons[t["exit_reason"]] = reasons.get(t["exit_reason"], 0) + 1
    symbols = {}
    for t in trades:
        symbols[t["symbol"]] = symbols.get(t["symbol"], 0) + 1
    return {
        "trades": len(pnl),
        "win_rate": 100.0 * len(wins) / len(pnl) if pnl else 0.0,
        "profit_factor": gross_win / gross_loss if gross_loss > 0 else float("inf") if gross_win > 0 else 0.0,
        "net": sum(pnl),
        "avg_win": gross_win / len(wins) if wins else 0.0,
        "avg_loss": -gross_loss / len(losses) if losses else 0.0,
        "first": trades[0]["entry_time"] if trades else "",
        "last": trades[-1]["exit_time"] if trades else "",
        "reasons": reasons,
        "symbols": symbols,
    }


def daily_stats(days: list) -> dict:
    if not days:
        return {}
    initial = float(days[0]["start_balance"])
    highest_eod = initial
    max_dd = 0.0
    worst_intraday = (0.0, "")
    worst_closed = (0.0, "")
    passed_on = breached_on = breach_kind = ""
    trailing_floor = initial - initial * MAX_LOSS_PCT / 100
    day_profits = []
    for d in days:
        start, end, low = float(d["start_balance"]), float(d["end_balance"]), float(d["lowest_equity"])
        max_dd = max(max_dd, highest_eod - low)
        if low - start < worst_intraday[0]:
            worst_intraday = (low - start, d["ftmo_date"])
        if end - start < worst_closed[0]:
            worst_closed = (end - start, d["ftmo_date"])
        day_profits.append(end - start)

        # FTMO 1-Step replay, only until the first pass or breach
        if not passed_on and not breached_on:
            if low <= start - initial * MAX_DAILY_LOSS_PCT / 100:
                breached_on, breach_kind = d["ftmo_date"], "daily loss"
            elif low <= trailing_floor:
                breached_on, breach_kind = d["ftmo_date"], "trailing max loss"
            elif end >= initial * (1 + PROFIT_TARGET_PCT / 100):
                passed_on = d["ftmo_date"]
        highest_eod = max(highest_eod, end)
        trailing_floor = min(highest_eod - initial * MAX_LOSS_PCT / 100, initial)

    positive = [p for p in day_profits if p > 0]
    best_share = max(positive) / sum(positive) if positive else 0.0
    return {
        "initial": initial,
        "days": len(days),
        "first_day": days[0]["ftmo_date"],
        "last_day": days[-1]["ftmo_date"],
        "final_balance": float(days[-1]["end_balance"]),
        "max_dd": max_dd,
        "max_dd_pct": 100 * max_dd / initial,
        "worst_intraday": worst_intraday,
        "worst_closed": worst_closed,
        "kill_switch_days": sum(1 for d in days if d["kill_switch"] == "yes"),
        "passed_on": passed_on,
        "breached_on": breached_on,
        "breach_kind": breach_kind,
        "best_day_share": best_share,
    }


def summarise(run: str, files: Path) -> str:
    trades = read_csv(files / f"{PREFIX}{run}_trades.csv")
    days = read_csv(files / f"{PREFIX}{run}_daily.csv")
    if not days:
        return f"## {run}\n\nNo daily log found ({PREFIX}{run}_daily.csv).\n"
    t, d = trade_stats(trades), daily_stats(days)
    init = d["initial"]
    pct = lambda v: f"{100 * v / init:+.2f}%"
    if d["passed_on"]:
        ftmo = f"passed on {d['passed_on']}"
    elif d["breached_on"]:
        ftmo = f"BREACHED ({d['breach_kind']}) on {d['breached_on']}"
    else:
        ftmo = "neither passed nor breached"
    pf = "n/a (no losses)" if t["profit_factor"] == float("inf") else f"{t['profit_factor']:.2f}"
    lines = [
        f"## {run}",
        "",
        "| Measure | Value |",
        "|---|---|",
        f"| Date range (FTMO days) | {d['first_day']} to {d['last_day']} ({d['days']} days) |",
        f"| Trades | {t['trades']} ({', '.join(f'{k} {v}' for k, v in sorted(t['symbols'].items()))}) |",
        f"| Win rate | {t['win_rate']:.1f}% |",
        f"| Profit factor | {pf} |",
        f"| Net P&L | {t['net']:+.2f} ({pct(t['net'])}) |",
        f"| Average win / loss | {t['avg_win']:+.2f} / {t['avg_loss']:+.2f} |",
        f"| Max drawdown from highest EOD balance | {d['max_dd']:.2f} ({d['max_dd_pct']:.2f}% of initial) |",
        f"| Worst day, intraday low vs start | {d['worst_intraday'][0]:+.2f} ({pct(d['worst_intraday'][0])}) on {d['worst_intraday'][1] or '-'} |",
        f"| Worst day, closed | {d['worst_closed'][0]:+.2f} ({pct(d['worst_closed'][0])}) on {d['worst_closed'][1] or '-'} |",
        f"| Kill switch days | {d['kill_switch_days']} |",
        f"| Exit reasons | {', '.join(f'{k} {v}' for k, v in sorted(t['reasons'].items())) or '-'} |",
        f"| FTMO 1-Step replay | {ftmo} |",
        f"| Best day share of positive days | {100 * d['best_day_share']:.0f}% (limit {100 * BEST_DAY_MAX_SHARE:.0f}%) |",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="*", help="run names, e.g. spec rsi50 noguard rsi50-noguard")
    ap.add_argument("--files", type=Path, default=DEFAULT_FILES)
    ap.add_argument("--out", type=Path, help="also write the report to this markdown file")
    args = ap.parse_args()
    runs = args.runs or sorted(p.name[len(PREFIX):-len("_trades.csv")]
                               for p in args.files.glob(f"{PREFIX}*_trades.csv"))
    if not runs:
        print(f"No {PREFIX}*_trades.csv files in {args.files}")
        return 1
    report = "\n".join(summarise(r, args.files) for r in runs)
    print(report)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
