//+------------------------------------------------------------------+
//| SignalTests.mq5                                                  |
//| Script. Checks TrendPullbackSignals.mqh against SPEC sections    |
//| 4, 5 and 7 on hand-built bars. One valid long setup is broken    |
//| one condition at a time; shorts reuse every case by mirroring    |
//| prices around 1.1 and RSI around 50. Writes                      |
//| MQL5\Files\SignalTests.txt. Places no orders.                    |
//+------------------------------------------------------------------+
#property strict

#include "..\ea\include\TrendPullbackSignals.mqh"

#define PIP 0.0001
#define MIRROR 2.2   // price p becomes 2.2 - p, i.e. reflected around 1.1

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

void SetBar(H1Bars &b, const int i, const double o, const double h, const double l, const double c,
            const double e20, const double e50, const double rsi)
{
   b.open[i] = o; b.high[i] = h; b.low[i] = l; b.close[i] = c;
   b.ema20[i] = e20; b.ema50[i] = e50; b.rsi[i] = rsi;
}

// Moves EMA20 below every low (1.0972 is the lowest) so no bar touches it
void SetEma20(H1Bars &b, const double value)
{
   for(int i = 0; i < PULLBACK_BARS; i++)
      b.ema20[i] = value;
}

// A valid long: H4 uptrend, bar 3 dips to EMA20 with RSI 44, bar 1 breaks bar 2's high
void BaseLong(H4Trend &t, H1Bars &b)
{
   t.close = 1.1000; t.emaFast = 1.0950; t.emaSlow = 1.0900;
   //        bar  open    high    low     close   ema20   ema50   rsi
   SetBar(b, 0, 1.0978, 1.0998, 1.0976, 1.0995, 1.0979, 1.0962, 55);   // bar 1, trigger
   SetBar(b, 1, 1.0980, 1.0988, 1.0972, 1.0976, 1.0977, 1.0961, 46);   // bar 2
   SetBar(b, 2, 1.0990, 1.1000, 1.0975, 1.0980, 1.0978, 1.0960, 44);   // bar 3, touches EMA20
}

void Mirror(H4Trend &t, H1Bars &b)
{
   t.close = MIRROR - t.close; t.emaFast = MIRROR - t.emaFast; t.emaSlow = MIRROR - t.emaSlow;
   for(int i = 0; i < PULLBACK_BARS; i++)
   {
      double high = b.high[i];
      b.high[i]  = MIRROR - b.low[i];
      b.low[i]   = MIRROR - high;
      b.open[i]  = MIRROR - b.open[i];
      b.close[i] = MIRROR - b.close[i];
      b.ema20[i] = MIRROR - b.ema20[i];
      b.ema50[i] = MIRROR - b.ema50[i];
      b.rsi[i]   = 100.0 - b.rsi[i];
   }
}

// Applies mutation n to a long setup. Returns its description, "" when n is past the end.
string Mutate(const int n, H4Trend &t, H1Bars &b)
{
   switch(n)
   {
      case 0: t.close = 1.0899;                 return "H4 close below EMA200";
      case 1: t.close = 1.0900;                 return "H4 close equal to EMA200";
      case 2: t.emaFast = 1.0899;               return "H4 EMA50 below EMA200";
      case 3: SetEma20(b, 1.0970);              return "no bar touches EMA20";
      case 4: b.ema50[1] = 1.0977;              return "bar 2 closed below EMA50";
      case 5: b.ema50[0] = 1.0996;              return "bar 1 closed below EMA50";
      case 6: b.rsi[2] = 45;                    return "lowest RSI exactly 45";
      case 7: b.close[0] = 1.0988;              return "bar 1 close equal to bar 2 high";
      case 8: b.open[0] = 1.0995;               return "bar 1 doji (close equal to open)";
      case 9: b.open[0] = 1.0997;               return "bar 1 bearish";
      case 10: b.ema20[0] = 1.0995;             return "bar 1 close equal to EMA20";
   }
   return "";
}

void TestSignals()
{
   H4Trend t;
   H1Bars b;

   BaseLong(t, b);
   Check("base setup is LONG", EvaluateSignal(t, b) == SIGNAL_LONG);
   Mirror(t, b);
   Check("mirrored base setup is SHORT", EvaluateSignal(t, b) == SIGNAL_SHORT);

   // Boundary cases that must still pass
   BaseLong(t, b);
   SetEma20(b, 1.0970); // all lows above EMA20 ...
   b.low[1] = 1.0970;   // ... except bar 2, exactly on it: the only touch
   Check("low equal to EMA20 is a touch (long)", EvaluateSignal(t, b) == SIGNAL_LONG);
   Mirror(t, b);
   Check("high equal to EMA20 is a touch (short)", EvaluateSignal(t, b) == SIGNAL_SHORT);

   BaseLong(t, b);
   b.ema50[1] = 1.0976; // close exactly on EMA50 is not below it
   Check("close equal to EMA50 allowed (long)", EvaluateSignal(t, b) == SIGNAL_LONG);
   Mirror(t, b);
   Check("close equal to EMA50 allowed (short)", EvaluateSignal(t, b) == SIGNAL_SHORT);

   for(int n = 0; ; n++)
   {
      BaseLong(t, b);
      string what = Mutate(n, t, b);
      if(what == "")
         break;
      ENUM_SIGNAL s = EvaluateSignal(t, b);
      Check("long, " + what + ": no signal (got " + SignalText(s) + ")", s == SIGNAL_NONE);
      Mirror(t, b);
      s = EvaluateSignal(t, b);
      Check("short mirror, " + what + ": no signal (got " + SignalText(s) + ")", s == SIGNAL_NONE);
   }
}

void TestStops()
{
   H4Trend t;
   H1Bars b;
   BaseLong(t, b);
   // Lowest low 1.0972 minus 3 pips
   CheckNum("long stop", StopLossLong(b, PIP), 1.0969);
   CheckNum("long stop pips from 1.0996", StopPips(1.0996, StopLossLong(b, PIP), PIP), 27.0);
   Mirror(t, b);
   // Highest high is the mirror of 1.0972 = 1.1028, plus 3 pips
   CheckNum("short stop", StopLossShort(b, PIP), 1.1031);
   CheckNum("short stop pips from 1.1004", StopPips(1.1004, StopLossShort(b, PIP), PIP), 27.0);

   Check("stop 14.9 pips rejected", !StopSizeOk(14.9));
   Check("stop 15.0 pips allowed",   StopSizeOk(15.0));
   Check("stop 40.0 pips allowed",   StopSizeOk(40.0));
   Check("stop 40.1 pips rejected", !StopSizeOk(40.1));
   Check("stop 15 pips with float noise allowed", StopSizeOk((1.10150 - 1.10000) / PIP));
}

void TestFilters()
{
   Check("spread 2.0 at max 2.0 allowed",  SpreadOk(2.0, 2.0));
   Check("spread 2.1 at max 2.0 rejected", !SpreadOk(2.1, 2.0));
   Check("spread 2.5 at max 2.5 allowed",  SpreadOk((1.27025 - 1.27000) / PIP, 2.5));

   Check("Dec 23 23:59 London open",       !IsHolidayBlackoutLondon(D'2025.12.23 23:59'));
   Check("Dec 24 00:00 London blacked out", IsHolidayBlackoutLondon(D'2025.12.24 00:00'));
   Check("Dec 31 blacked out",              IsHolidayBlackoutLondon(D'2025.12.31 12:00'));
   Check("Jan 2 23:59 London blacked out",  IsHolidayBlackoutLondon(D'2026.01.02 23:59'));
   Check("Jan 3 00:00 London open",        !IsHolidayBlackoutLondon(D'2026.01.03 00:00'));
   // Winter: server = London + 2h, so Dec 24 00:00 London is 02:00 server
   Check("server Dec 24 01:59 is Dec 23 London", !IsHolidayBlackout(D'2025.12.24 01:59'));
   Check("server Dec 24 02:00 is Dec 24 London",  IsHolidayBlackout(D'2025.12.24 02:00'));

   // Session window is covered in detail by TimeHelperTests; spot checks through this wrapper
   Check("summer 09:00 server bar (07:00 London) in session",   IsEntrySession(D'2026.07.15 09:00'));
   Check("summer 17:00 server bar (15:00 London) out",         !IsEntrySession(D'2026.07.15 17:00'));
   Check("autumn mismatch 09:00 server (06:00 London) out",    !IsEntrySession(D'2025.10.27 09:00'));
   Check("autumn mismatch 10:00 server (07:00 London) in",      IsEntrySession(D'2025.10.27 10:00'));
}

void TestExits()
{
   Check("23h59 open: no time stop", !TimeStopDue(D'2026.07.14 10:00', D'2026.07.15 09:59'));
   Check("24h open: time stop",       TimeStopDue(D'2026.07.14 10:00', D'2026.07.15 10:00'));

   Check("summer Fri 21:59 server (19:59 London): hold",   !IsFridayCloseTime(D'2026.07.17 21:59'));
   Check("summer Fri 22:00 server (20:00 London): close",   IsFridayCloseTime(D'2026.07.17 22:00'));
   Check("winter Fri 22:00 server (20:00 London): close",   IsFridayCloseTime(D'2026.01.16 22:00'));
   Check("Thu 22:00 server: hold",                         !IsFridayCloseTime(D'2026.07.16 22:00'));
   Check("autumn mismatch Fri 22:00 server (19:00 London): hold", !IsFridayCloseTime(D'2025.10.31 22:00'));
   Check("autumn mismatch Fri 23:00 server (20:00 London): close", IsFridayCloseTime(D'2025.10.31 23:00'));
}

void OnStart()
{
   g_file = FileOpen("SignalTests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("Signal tests, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   TestSignals();
   TestStops();
   TestFilters();
   TestExits();
   Out(StringFormat("RESULT: %d passed, %d failed", g_passed, g_failed));
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
