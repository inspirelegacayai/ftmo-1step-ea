//+------------------------------------------------------------------+
//| CandidateTests.mq5                                               |
//| Script. Checks CandidateSignals.mqh (SPEC section 4A) on         |
//| hand-built bars. Writes MQL5\Files\CandidateTests.txt.           |
//| Places no orders.                                                |
//+------------------------------------------------------------------+
#property strict

#include "..\ea\include\CandidateSignals.mqh"

#define PIP 0.0001

int g_file   = INVALID_HANDLE;
int g_passed = 0;
int g_failed = 0;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

void Check(const string label, const bool condition)
{
   if(condition)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label);
}

void CheckNum(const string label, const double actual, const double expected)
{
   if(MathAbs(actual - expected) < 1e-9)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out(StringFormat("FAIL %s: got %.6f, expected %.6f", label, actual, expected));
}

void CheckSignal(const string label, const ENUM_SIGNAL actual, const ENUM_SIGNAL expected)
{
   if(actual == expected)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label + ": got " + SignalText(actual) + ", expected " + SignalText(expected));
}

void AddBar(MqlRates &bars[], const datetime t, const double high, const double low)
{
   int n = ArraySize(bars);
   ArrayResize(bars, n + 1);
   ZeroMemory(bars[n]);
   bars[n].time = t;
   bars[n].high = high;
   bars[n].low  = low;
   bars[n].open = (high + low) / 2;
   bars[n].close = (high + low) / 2;
}

// The 7 range bars: high 1.1015 and low 1.0985 overall
void AddRangeBars(MqlRates &bars[], const datetime firstServer)
{
   double highs[] = {1.1010, 1.1012, 1.1015, 1.1011, 1.1009, 1.1013, 1.1008};
   double lows[]  = {1.0990, 1.0988, 1.0992, 1.0985, 1.0991, 1.0989, 1.0994};
   for(int i = 0; i < ASIAN_RANGE_BARS; i++)
      AddBar(bars, firstServer + i * TH_HOUR, highs[i], lows[i]);
}

void TestAsianRange()
{
   // Summer: London = server - 2h, so the range bars open 02:00-08:00 server
   MqlRates bars[];
   AddBar(bars, D'2026.07.15 01:00', 1.1100, 1.0900);   // 23:00 London the day before: excluded
   AddRangeBars(bars, D'2026.07.15 02:00');
   AddBar(bars, D'2026.07.15 09:00', 1.1050, 1.0950);   // 07:00 London: excluded
   AsianRange r;
   BuildAsianRange(bars, D'2026.07.15', r);
   Check("summer range valid", r.valid);
   CheckNum("summer range high", r.high, 1.1015);
   CheckNum("summer range low", r.low, 1.0985);

   // Autumn mismatch week: London = UTC, server = UTC+3, so the range opens at 03:00 server
   MqlRates m[];
   AddBar(m, D'2025.10.27 02:00', 1.1100, 1.0900);      // 23:00 London the day before
   AddRangeBars(m, D'2025.10.27 03:00');
   AddBar(m, D'2025.10.27 10:00', 1.1050, 1.0950);      // 07:00 London
   AsianRange rm;
   BuildAsianRange(m, D'2025.10.27', rm);
   Check("mismatch range valid", rm.valid);
   CheckNum("mismatch range high", rm.high, 1.1015);
   CheckNum("mismatch range low", rm.low, 1.0985);

   // Winter: London = server - 2h as in summer (both shifted); range opens 02:00 server
   MqlRates w[];
   AddRangeBars(w, D'2026.01.14 02:00');
   AsianRange rw;
   BuildAsianRange(w, D'2026.01.14', rw);
   Check("winter range valid", rw.valid);

   // A missing bar invalidates the day rather than shrinking the range
   MqlRates gap[];
   AddRangeBars(gap, D'2026.07.15 02:00');
   ArrayRemove(gap, 3, 1);
   AsianRange rg;
   BuildAsianRange(gap, D'2026.07.15', rg);
   Check("range with a missing bar is invalid", !rg.valid);

   // Wrong date gives nothing
   AsianRange rx;
   BuildAsianRange(bars, D'2026.07.16', rx);
   Check("range for another date is invalid", !rx.valid);
}

void TestBreakout()
{
   MqlRates bars[];
   AddRangeBars(bars, D'2026.07.15 02:00');
   AsianRange r;
   BuildAsianRange(bars, D'2026.07.15', r);

   // Bar 1 opened 09:00 server = 07:00 London
   CheckSignal("close above range high: long",   BreakoutSignal(r, D'2026.07.15 09:00', 1.1016), SIGNAL_LONG);
   CheckSignal("close equal to range high: none", BreakoutSignal(r, D'2026.07.15 09:00', 1.1015), SIGNAL_NONE);
   CheckSignal("close inside range: none",        BreakoutSignal(r, D'2026.07.15 09:00', 1.1000), SIGNAL_NONE);
   CheckSignal("close equal to range low: none",  BreakoutSignal(r, D'2026.07.15 09:00', 1.0985), SIGNAL_NONE);
   CheckSignal("close below range low: short",    BreakoutSignal(r, D'2026.07.15 09:00', 1.0984), SIGNAL_SHORT);
   CheckSignal("bar 1 opened 06:00 London: none", BreakoutSignal(r, D'2026.07.15 08:00', 1.1020), SIGNAL_NONE);
   CheckSignal("bar 1 at 14:00 London: long",     BreakoutSignal(r, D'2026.07.15 16:00', 1.1020), SIGNAL_LONG);
   CheckSignal("bar 1 on the next London day: none", BreakoutSignal(r, D'2026.07.16 09:00', 1.1020), SIGNAL_NONE);

   AsianRange invalid = r;
   invalid.valid = false;
   CheckSignal("invalid range: none", BreakoutSignal(invalid, D'2026.07.15 09:00', 1.1020), SIGNAL_NONE);

   // First breakout only: an earlier post-07:00 close outside the range blocks later ones
   MqlRates day[];
   AddRangeBars(day, D'2026.07.15 02:00');
   AddBar(day, D'2026.07.15 09:00', 1.1012, 1.0995);    // 07:00 London, closes 1.10035 inside
   CheckSignal("first close outside the range: long",
               FirstBreakoutSignal(day, r, D'2026.07.15 10:00', 1.1020), SIGNAL_LONG);
   AddBar(day, D'2026.07.15 10:00', 1.1030, 1.1010);    // 08:00 London, closes 1.1020 above the range
   CheckSignal("second close outside the range: none",
               FirstBreakoutSignal(day, r, D'2026.07.15 11:00', 1.1025), SIGNAL_NONE);
   CheckSignal("even in the other direction: none",
               FirstBreakoutSignal(day, r, D'2026.07.15 11:00', 1.0970), SIGNAL_NONE);
   CheckSignal("range-bar closes don't count as breakouts",
               FirstBreakoutSignal(bars, r, D'2026.07.15 09:00', 1.1016), SIGNAL_LONG);

   CheckNum("long stop: range low minus 3 pips",   BreakoutStop(r, SIGNAL_LONG, PIP), 1.0982);
   CheckNum("short stop: range high plus 3 pips",  BreakoutStop(r, SIGNAL_SHORT, PIP), 1.1018);
}

void BaseGrailLong(GrailBars &g)
{
   g.adx1 = 32; g.adx2 = 31; g.plusDi1 = 28; g.minusDi1 = 15;
   g.high1 = 1.1010; g.low1 = 1.0995; g.ema20_1 = 1.0996;
}

void TestGrail()
{
   GrailBars g;
   BaseGrailLong(g);
   CheckSignal("grail base long", GrailSignal(g), SIGNAL_LONG);
   CheckNum("grail buy stop 1 pip above bar 1 high", GrailOrderPrice(g, SIGNAL_LONG, PIP), 1.1011);

   BaseGrailLong(g); g.adx1 = 30;
   CheckSignal("ADX exactly 30: none", GrailSignal(g), SIGNAL_NONE);
   BaseGrailLong(g); g.adx2 = 32;
   CheckSignal("ADX flat (not rising): none", GrailSignal(g), SIGNAL_NONE);
   BaseGrailLong(g); g.low1 = 1.0997;
   CheckSignal("low above EMA20 (no touch): none", GrailSignal(g), SIGNAL_NONE);
   BaseGrailLong(g); g.low1 = 1.0996;
   CheckSignal("low exactly on EMA20 is a touch", GrailSignal(g), SIGNAL_LONG);
   BaseGrailLong(g); g.minusDi1 = 28;
   CheckSignal("DI equal: none", GrailSignal(g), SIGNAL_NONE);

   // Short: -DI above +DI and the high reaches EMA20
   GrailBars s;
   s.adx1 = 35; s.adx2 = 33; s.plusDi1 = 14; s.minusDi1 = 30;
   s.high1 = 1.1000; s.low1 = 1.0985; s.ema20_1 = 1.1000;
   CheckSignal("grail short, high exactly on EMA20", GrailSignal(s), SIGNAL_SHORT);
   CheckNum("grail sell stop 1 pip below bar 1 low", GrailOrderPrice(s, SIGNAL_SHORT, PIP), 1.0984);
   s.high1 = 1.0999;
   CheckSignal("short, high below EMA20 (no touch): none", GrailSignal(s), SIGNAL_NONE);

   Check("order 2h59m old: still live",  !GrailOrderExpired(D'2026.07.15 09:00:03', D'2026.07.15 11:59:59'));
   Check("order 3h old: expired",          GrailOrderExpired(D'2026.07.15 09:00:03', D'2026.07.15 12:00:03'));
}

void OnStart()
{
   g_file = FileOpen("CandidateTests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("Candidate tests, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   TestAsianRange();
   TestBreakout();
   TestGrail();
   Out(StringFormat("RESULT: %d passed, %d failed", g_passed, g_failed));
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
