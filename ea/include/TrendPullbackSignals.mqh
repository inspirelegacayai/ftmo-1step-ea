//+------------------------------------------------------------------+
//| TrendPullbackSignals.mqh                                         |
//| Entry rules (SPEC section 4), filters (section 5) and exit       |
//| rules (section 7) as pure functions over closed-bar data, so     |
//| tests/SignalTests.mq5 can check them without a market.           |
//|                                                                  |
//| Bar arrays are indexed like the spec: [0] = bar 1 (last closed), |
//| [1] = bar 2, [2] = bar 3. Nothing here reads the forming bar.    |
//+------------------------------------------------------------------+
#ifndef TREND_PULLBACK_SIGNALS_MQH
#define TREND_PULLBACK_SIGNALS_MQH

#include "TimeHelper.mqh"

//--- Strategy constants (SPEC sections 4, 5, 7) --------------------------
#define TREND_EMA_FAST            50     // H4
#define TREND_EMA_SLOW            200    // H4
#define PULLBACK_EMA              20     // H1
#define PULLBACK_GUARD_EMA        50     // H1
#define RSI_PERIOD                14     // H1
#define RSI_LONG_BELOW            45.0
#define RSI_SHORT_ABOVE           55.0
#define PULLBACK_BARS             3
#define STOP_BUFFER_PIPS          3.0
#define STOP_MIN_PIPS             15.0
#define STOP_MAX_PIPS             40.0
#define SESSION_START_LONDON_HOUR 7      // inclusive
#define SESSION_END_LONDON_HOUR   15     // exclusive, see CHANGELOG 2026-10-02
#define NEWS_WINDOW_MINUTES       30
#define TIME_STOP_HOURS           24
#define FRIDAY_CLOSE_LONDON_HOUR  20
#define HOLIDAY_START_MONTH       12     // no new entries Dec 24 ...
#define HOLIDAY_START_DAY         24
#define HOLIDAY_END_MONTH         1      // ... through Jan 2, London date
#define HOLIDAY_END_DAY           2

enum ENUM_SIGNAL
{
   SIGNAL_NONE,
   SIGNAL_LONG,
   SIGNAL_SHORT
};

string SignalText(const ENUM_SIGNAL s)
{
   return s == SIGNAL_LONG ? "LONG" : (s == SIGNAL_SHORT ? "SHORT" : "NONE");
}

// Last closed H4 bar
struct H4Trend
{
   double close;
   double emaFast;
   double emaSlow;
};

// Last PULLBACK_BARS closed H1 bars with indicator values at each bar
struct H1Bars
{
   double open[PULLBACK_BARS];
   double high[PULLBACK_BARS];
   double low[PULLBACK_BARS];
   double close[PULLBACK_BARS];
   double ema20[PULLBACK_BARS];
   double ema50[PULLBACK_BARS];
   double rsi[PULLBACK_BARS];
};

//--- Entry rules -----------------------------------------------------------

bool TrendUp(const H4Trend &t)   { return t.close > t.emaSlow && t.emaFast > t.emaSlow; }
bool TrendDown(const H4Trend &t) { return t.close < t.emaSlow && t.emaFast < t.emaSlow; }

bool PullbackLong(const H1Bars &b)
{
   bool touched = false;
   double lowestRsi = DBL_MAX;
   for(int i = 0; i < PULLBACK_BARS; i++)
   {
      if(b.low[i] <= b.ema20[i])
         touched = true;
      if(b.close[i] < b.ema50[i])
         return false;
      lowestRsi = MathMin(lowestRsi, b.rsi[i]);
   }
   return touched && lowestRsi < RSI_LONG_BELOW;
}

bool PullbackShort(const H1Bars &b)
{
   bool touched = false;
   double highestRsi = -DBL_MAX;
   for(int i = 0; i < PULLBACK_BARS; i++)
   {
      if(b.high[i] >= b.ema20[i])
         touched = true;
      if(b.close[i] > b.ema50[i])
         return false;
      highestRsi = MathMax(highestRsi, b.rsi[i]);
   }
   return touched && highestRsi > RSI_SHORT_ABOVE;
}

bool TriggerLong(const H1Bars &b)
{
   return b.close[0] > b.ema20[0] && b.close[0] > b.high[1] && b.close[0] > b.open[0];
}

bool TriggerShort(const H1Bars &b)
{
   return b.close[0] < b.ema20[0] && b.close[0] < b.low[1] && b.close[0] < b.open[0];
}

ENUM_SIGNAL EvaluateSignal(const H4Trend &t, const H1Bars &b)
{
   if(TrendUp(t) && PullbackLong(b) && TriggerLong(b))
      return SIGNAL_LONG;
   if(TrendDown(t) && PullbackShort(b) && TriggerShort(b))
      return SIGNAL_SHORT;
   return SIGNAL_NONE;
}

//--- Stops ----------------------------------------------------------------

double StopLossLong(const H1Bars &b, const double pip)
{
   double lowest = DBL_MAX;
   for(int i = 0; i < PULLBACK_BARS; i++)
      lowest = MathMin(lowest, b.low[i]);
   return lowest - STOP_BUFFER_PIPS * pip;
}

double StopLossShort(const H1Bars &b, const double pip)
{
   double highest = -DBL_MAX;
   for(int i = 0; i < PULLBACK_BARS; i++)
      highest = MathMax(highest, b.high[i]);
   return highest + STOP_BUFFER_PIPS * pip;
}

// Distance in pips from the entry price to the stop, either direction
double StopPips(const double entry, const double stop, const double pip)
{
   return MathAbs(entry - stop) / pip;
}

//--- Filters ----------------------------------------------------------------

// Rounded to 0.1 pip so float noise can't decide a boundary case
bool StopSizeOk(const double stopPips)
{
   double p = MathRound(stopPips * 10.0) / 10.0;
   return p >= STOP_MIN_PIPS && p <= STOP_MAX_PIPS;
}

bool SpreadOk(const double spreadPips, const double maxSpreadPips)
{
   return MathRound(spreadPips * 10.0) / 10.0 <= maxSpreadPips;
}

// Takes London wall time
bool IsHolidayBlackoutLondon(const datetime london)
{
   MqlDateTime d;
   TimeToStruct(london, d);
   if(d.mon == HOLIDAY_START_MONTH && d.day >= HOLIDAY_START_DAY)
      return true;
   return d.mon == HOLIDAY_END_MONTH && d.day <= HOLIDAY_END_DAY;
}

bool IsHolidayBlackout(const datetime server) { return IsHolidayBlackoutLondon(ServerToLondon(server)); }

bool IsEntrySession(const datetime barOpenServer)
{
   return IsInLondonWindow(barOpenServer, SESSION_START_LONDON_HOUR, SESSION_END_LONDON_HOUR);
}

//--- Exits ----------------------------------------------------------------

bool TimeStopDue(const datetime openServer, const datetime nowServer)
{
   return nowServer - openServer >= TIME_STOP_HOURS * TH_HOUR;
}

bool IsFridayCloseTime(const datetime server)
{
   return LondonDayOfWeek(server) == 5 && LondonHour(server) >= FRIDAY_CLOSE_LONDON_HOUR;
}

#endif
