//+------------------------------------------------------------------+
//| CandidateSignals.mqh                                             |
//| SPEC section 4A candidate entries as pure functions:             |
//|  A. London breakout of the Asian range                           |
//|  B. Holy Grail (ADX trend, pullback to EMA20, stop order)        |
//| Closed bars only. Tests: tests/CandidateTests.mq5.               |
//+------------------------------------------------------------------+
#ifndef CANDIDATE_SIGNALS_MQH
#define CANDIDATE_SIGNALS_MQH

#include "TrendPullbackSignals.mqh"

//--- Which entry the EA runs. Only the section 4 entry may trade a live account
//--- until a candidate passes the section 11 plan and section 4 is rewritten.
enum ENUM_ENTRY_MODEL
{
   ENTRY_TREND_PULLBACK,   // Section 4: trend pullback (live)
   ENTRY_LONDON_BREAKOUT,  // Section 4A-A: London breakout (test only)
   ENTRY_HOLY_GRAIL        // Section 4A-B: Holy Grail (test only)
};

string EntryModelText(const ENUM_ENTRY_MODEL m)
{
   switch(m)
   {
      case ENTRY_LONDON_BREAKOUT: return "breakout";
      case ENTRY_HOLY_GRAIL:      return "grail";
      default:                    return "pullback";
   }
}

//--- A. London breakout ----------------------------------------------------
#define ASIAN_FIRST_LONDON_HOUR  0     // first H1 bar of the range opens 00:00 London
#define ASIAN_LAST_LONDON_HOUR   6     // last opens 06:00, so the range is complete at 07:00
#define ASIAN_RANGE_BARS         7
#define BREAKOUT_FIRST_LONDON_HOUR 7   // the breakout bar opens 07:00 or later

struct AsianRange
{
   bool     valid;
   datetime londonDate;   // 00:00 of the London date the range belongs to
   double   high;
   double   low;
};

datetime LondonDateOf(const datetime server)
{
   datetime london = ServerToLondon(server);
   return london - london % TH_DAY;
}

// Builds the Asian range for londonDate from closed H1 bars (any order).
// Valid only when all 7 range bars are present, so a data gap can't shrink the range.
void BuildAsianRange(const MqlRates &bars[], const datetime londonDate, AsianRange &r)
{
   r.valid      = false;
   r.londonDate = londonDate;
   r.high       = -DBL_MAX;
   r.low        = DBL_MAX;
   int found = 0;
   for(int i = 0; i < ArraySize(bars); i++)
   {
      if(LondonDateOf(bars[i].time) != londonDate)
         continue;
      int hour = LondonHour(bars[i].time);
      if(hour < ASIAN_FIRST_LONDON_HOUR || hour > ASIAN_LAST_LONDON_HOUR)
         continue;
      r.high = MathMax(r.high, bars[i].high);
      r.low  = MathMin(r.low, bars[i].low);
      found++;
   }
   r.valid = (found == ASIAN_RANGE_BARS);
}

// bar1Open/bar1Close describe H1 bar 1 (the last closed bar)
ENUM_SIGNAL BreakoutSignal(const AsianRange &r, const datetime bar1Open, const double bar1Close)
{
   if(!r.valid || LondonDateOf(bar1Open) != r.londonDate || LondonHour(bar1Open) < BREAKOUT_FIRST_LONDON_HOUR)
      return SIGNAL_NONE;
   if(bar1Close > r.high)
      return SIGNAL_LONG;
   if(bar1Close < r.low)
      return SIGNAL_SHORT;
   return SIGNAL_NONE;
}

// Section 4A-A rule 3: only the day's first close outside the range counts. Worked out
// from the bars themselves (bars of the range's date opening 07:00 London or later,
// before bar 1), so a restart mid-day can't produce a second entry.
ENUM_SIGNAL FirstBreakoutSignal(const MqlRates &bars[], const AsianRange &r,
                                const datetime bar1Open, const double bar1Close)
{
   ENUM_SIGNAL s = BreakoutSignal(r, bar1Open, bar1Close);
   if(s == SIGNAL_NONE)
      return SIGNAL_NONE;
   for(int i = 0; i < ArraySize(bars); i++)
   {
      if(bars[i].time >= bar1Open || LondonDateOf(bars[i].time) != r.londonDate ||
         LondonHour(bars[i].time) < BREAKOUT_FIRST_LONDON_HOUR)
         continue;
      if(bars[i].close > r.high || bars[i].close < r.low)
         return SIGNAL_NONE;
   }
   return s;
}

// Opposite side of the range plus the section 7 buffer
double BreakoutStop(const AsianRange &r, const ENUM_SIGNAL s, const double pip)
{
   return s == SIGNAL_LONG ? r.low - STOP_BUFFER_PIPS * pip : r.high + STOP_BUFFER_PIPS * pip;
}

//--- B. Holy Grail ----------------------------------------------------------
#define GRAIL_ADX_PERIOD        14
#define GRAIL_ADX_MIN           30.0
#define GRAIL_ENTRY_BUFFER_PIPS 1.0
#define GRAIL_EXPIRY_BARS       3

// Bar 1 values, plus ADX on bar 2 to see whether it is rising
struct GrailBars
{
   double adx1;
   double adx2;
   double plusDi1;
   double minusDi1;
   double high1;
   double low1;
   double ema20_1;
};

ENUM_SIGNAL GrailSignal(const GrailBars &g)
{
   if(g.adx1 <= GRAIL_ADX_MIN || g.adx1 <= g.adx2)
      return SIGNAL_NONE;
   if(g.plusDi1 > g.minusDi1 && g.low1 <= g.ema20_1)
      return SIGNAL_LONG;
   if(g.minusDi1 > g.plusDi1 && g.high1 >= g.ema20_1)
      return SIGNAL_SHORT;
   return SIGNAL_NONE;
}

double GrailOrderPrice(const GrailBars &g, const ENUM_SIGNAL s, const double pip)
{
   return s == SIGNAL_LONG ? g.high1 + GRAIL_ENTRY_BUFFER_PIPS * pip : g.low1 - GRAIL_ENTRY_BUFFER_PIPS * pip;
}

// A pending order placed at a bar open lives through that bar and the next two
bool GrailOrderExpired(const datetime placedServer, const datetime nowServer)
{
   return nowServer - placedServer >= GRAIL_EXPIRY_BARS * TH_HOUR;
}

#endif
