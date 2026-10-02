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
