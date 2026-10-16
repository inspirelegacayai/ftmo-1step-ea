# Changelog

Every change to a strategy rule, parameter or default value in SPEC.md gets an entry here:
date, what changed, why, and the backtest that supports it.

## Unreleased

- 2026-10-02: SPEC.md v1.0 added as the baseline. No rule changes.
- 2026-10-02: Clarification, not a rule change. Section 5 session "new H1 bar opens between
  07:00 and 15:00 London" is implemented as 07:00 inclusive to 15:00 exclusive: bars opening
  07:00 through 14:00 qualify, the 15:00 bar does not. Why: SPEC wording was ambiguous at the
  end boundary; owner delegated the call. Conventional half-open window, 8 signal bars a day.
  Backtest: none needed (interpretation fixed before any testing).
- 2026-10-02: Verified fact (section 15). Server is OANDA-Prop Trader (used by FTMO); server
  clock = New York time + 7h (GMT+2 US winter, GMT+3 US summer, switching on US dates).
  Symbols: EURUSD.sim, GBPUSD.sim. Source: tools/ServerTimeProbe.mq5 and FTMO's DST notice.
- 2026-10-04: SPEC section 11, backtest data source (approved by owner). Was: backtest on the
  FTMO server with 8-10 years of history. Now: Dukascopy real ticks from 2016-01 imported as
  custom symbols on the FTMO server clock; FTMO server real ticks used as confirmation at step 8.
  Why: the FTMO server only has history from 2025-04-07 (ServerTimeProbe, 2026-10-02), all of
  it inside the out-of-sample window; the owner's OANDA MT4 has only patchy H4 bars.
  Backtest: none; this is a data-source change made before any backtest.
- 2026-10-05: Backtesting skipped (owner decision). Build steps 6 (benchmark EA), 7 (in-sample
  backtests), 8 (out-of-sample) and 9 (Monte Carlo) dropped; SPEC sections 10-12 marked skipped
  and kept for reference. Step 10 now goes straight to the challenge at 0.25% risk for two
  weeks, then 0.5%. A forward demo check of order handling was offered and declined. The
  2026-10-04 Dukascopy data-source entry is superseded; its download tools were removed.
  Why: no long history on the FTMO server, and Dukascopy rate-limited the download to days.
  Backtest: none. The strategy and order handling go live untested; the section 6 risk rules
  (0.25% risk, 1.5% daily kill switch, floor guard) are the remaining protection.
- 2026-10-15: Diagnostic backtest approved, no rule change. The live EA took no trade in its
  first 8 trading days (SignalDiagnostic: H4 trend present throughout, but the section 4
  pullback never qualified). Owner waived the CLAUDE.md out-of-sample rule for an 18-month
  Strategy Tester run on the FTMO server's own real ticks, comparing the spec rules with three
  test-only variants: RSI 50/50 instead of 45/55; no "close beyond EMA50" check; both. The
  variants are an input (InpRuleVariant) that defaults to the spec and is refused on live
  accounts. Caveat: no untouched data remains to confirm whichever variant looks best.
- 2026-10-15: Diagnostic backtest result, no rule change. 2025-06-01 to 2026-10-14, EURUSD.sim
  and GBPUSD.sim, every tick based on real ticks, 0.5% risk, TP 40. Spec: 6 trades, PF 0.86,
  -0.16%. RSI 50/50: 47 trades, PF 0.74, -3.21%. No EMA50 check: 102 trades, PF 0.76, -5.11%,
  floor guard blocked entries from 2026-07-09. Both: 42 trades, PF 0.48, -5.63%, floor guard
  blocked entries from 2025-09-04. None reached the 10% target. Every loosening lost money, so
  the live EA stays on the spec rules. Report: reports/2026-10-15_diagnostic_2025-06-01_2026-10-14_risk0.5_TP40_realticks.md
- 2026-10-16: SPEC section 4A added: two candidate entries to replace section 4, A London
  breakout and B Holy Grail (owner decision; same constraints as v1). Section 10 benchmark is
  now candidate B. Section 11 gains the candidate test plan: in-sample 2025-06-01 to 2026-05-31,
  hold-out 2026-06-01 to 2026-10-14 run once per frozen candidate, and a proposed go-live bar
  for the owner to confirm. Section 4 stays live until a candidate passes.
  Backtest: none yet; rules fixed before testing.
- 2026-10-16: Section 11 go-live bar confirmed by the owner while the first in-sample run was in
  progress and before any candidate result was seen: in-sample PF > 1.2 with >= 40 trades, and
  hold-out PF > 1.0 with no FTMO breach. Backtest: none; criteria fixed in advance.
- 2026-10-16: Candidate in-sample result, no rule change. 2025-06-01 to 2026-05-31, EURUSD.sim
  and GBPUSD.sim, every tick based on real ticks, 0.5% risk, TP 40. A London breakout: 274
  trades, win rate 48.5%, PF 1.18, +10.17%, max DD from highest EOD 5.98%, worst day -1.19%,
  FTMO replay passed 2026-05-05. B Holy Grail: 21 trades, PF 0.76, -1.23%. Neither meets the
  in-sample bar (PF > 1.2 with >= 40 trades); hold-out not run. Report:
  reports/2026-10-16_candidates_insample_2025-06-01_2026-05-31_risk0.5_TP40_realticks.md
- 2026-10-16: SPEC 4A-A gains three development variants (owner decision), declared before
  testing: A1 H4 trend filter, A2 stop at the Asian range midpoint, A3 both. In-sample only,
  same bar; the best goes to the hold-out once, and no further breakout variants before it.
  Backtest: pending.
- 2026-10-16: Breakout variant in-sample result, no rule change. Same period and settings.
  A: 274 trades, PF 1.18, +9.73%, max DD 6.14%, FTMO replay passed 2026-05-05 (re-run of the
  earlier A: same trades, net $44 lower, likely tester execution delay). A1 trend filter: 128
  trades, PF 1.17, +3.93%. A2 mid-range stop: 184 trades, PF 0.91, -4.20%. A3 both: 84 trades,
  PF 0.66, -6.58%. None meets the in-sample bar; hold-out not run. One A2 day reached -1.51%:
  the kill switch fired at -1.5% and the close filled $1 further down, not a logic fault.
  Report: reports/2026-10-16_breakout-variants_insample_2025-06-01_2026-05-31_risk0.5_TP40_realticks.md
