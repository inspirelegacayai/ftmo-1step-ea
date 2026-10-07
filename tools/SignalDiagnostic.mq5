//+------------------------------------------------------------------+
//| SignalDiagnostic.mq5                                             |
//| Read-only. Replays the EA's entry rules on every H1 bar since    |
//| InpFrom, using the same rule code (TrendPullbackSignals.mqh) and |
//| the bars that were closed when each bar opened. Shows which      |
//| condition held each signal back, and whether indicator data      |
//| loads at all. Writes MQL5\Files\SignalDiagnostic.txt.            |
//| Places no orders and does not touch the running EA.              |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include "..\ea\include\TrendPullbackSignals.mqh"

input string   InpSymbols = "EURUSD.sim,GBPUSD.sim";
input datetime InpFrom    = D'2026.10.05 00:00';   // server time

int g_file = INVALID_HANDLE;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

// Values as of bar index `shift` (1 = the last closed bar when bar shift-1 opened)
bool CopyAt(const int handle, const int shift, const int count, double &out[])
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, count, buf) != count)
      return false;
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
      out[i] = buf[i];
   return true;
}

// Same loading as the EA, but as of H1 bar `k` opening instead of the current bar
bool LoadAsOf(const string sym, const int k, const int hFast, const int hSlow, const int h20, const int h50,
              const int hRsi, H4Trend &t, H1Bars &b, string &err)
{
   datetime barOpen = iTime(sym, PERIOD_H1, k);
   int h4 = iBarShift(sym, PERIOD_H4, barOpen, false);   // H4 bar in progress at that moment
   double v[];
   if(h4 < 0 || !CopyAt(hFast, h4 + 1, 1, v)) { err = "H4 EMA50 copy failed " + IntegerToString(GetLastError()); return false; }
   t.emaFast = v[0];
   if(!CopyAt(hSlow, h4 + 1, 1, v)) { err = "H4 EMA200 copy failed " + IntegerToString(GetLastError()); return false; }
   t.emaSlow = v[0];
   t.close = iClose(sym, PERIOD_H4, h4 + 1);

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(sym, PERIOD_H1, k + 1, PULLBACK_BARS, r) != PULLBACK_BARS) { err = "H1 rates copy failed"; return false; }
   double e20[], e50[], rsi[];
   if(!CopyAt(h20, k + 1, PULLBACK_BARS, e20) || !CopyAt(h50, k + 1, PULLBACK_BARS, e50) ||
      !CopyAt(hRsi, k + 1, PULLBACK_BARS, rsi))
   {
      err = "H1 indicator copy failed " + IntegerToString(GetLastError());
      return false;
   }
   for(int i = 0; i < PULLBACK_BARS; i++)
   {
      b.open[i] = r[i].open; b.high[i] = r[i].high; b.low[i] = r[i].low; b.close[i] = r[i].close;
      b.ema20[i] = e20[i]; b.ema50[i] = e50[i]; b.rsi[i] = rsi[i];
   }
   return true;
}

string Mark(const bool ok) { return ok ? "yes" : "no "; }

void Diagnose(const string sym)
{
   Out("");
   Out("===== " + sym);
   if(!SymbolSelect(sym, true)) { Out("symbol not found"); return; }
   int hFast = iMA(sym, PERIOD_H4, TREND_EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   int hSlow = iMA(sym, PERIOD_H4, TREND_EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
   int h20   = iMA(sym, PERIOD_H1, PULLBACK_EMA, 0, MODE_EMA, PRICE_CLOSE);
   int h50   = iMA(sym, PERIOD_H1, PULLBACK_GUARD_EMA, 0, MODE_EMA, PRICE_CLOSE);
   int hRsi  = iRSI(sym, PERIOD_H1, RSI_PERIOD, PRICE_CLOSE);
   // Indicators calculate in the background; wait until they report ready
   for(int w = 0; w < 50 && (BarsCalculated(hSlow) <= 0 || BarsCalculated(hRsi) <= 0); w++)
      Sleep(200);

   int first = iBarShift(sym, PERIOD_H1, InpFrom, false);
   Out(StringFormat("H1 bars to check: %d (from %s server)", first + 1, TimeToString(InpFrom)));
   Out("bar open (server) | London | H4 trend | long: pullback trigger | short: pullback trigger | minRSI maxRSI | signal");
   int signals = 0, failures = 0, trendBars = 0;
   for(int k = first; k >= 0; k--)
   {
      H4Trend t;
      H1Bars b;
      string err = "";
      datetime open = iTime(sym, PERIOD_H1, k);
      if(!LoadAsOf(sym, k, hFast, hSlow, h20, h50, hRsi, t, b, err))
      {
         failures++;
         Out(TimeToString(open) + "  DATA FAILED: " + err);
         continue;
      }
      double minRsi = MathMin(b.rsi[0], MathMin(b.rsi[1], b.rsi[2]));
      double maxRsi = MathMax(b.rsi[0], MathMax(b.rsi[1], b.rsi[2]));
      string trend = TrendUp(t) ? "UP  " : (TrendDown(t) ? "DOWN" : "none");
      if(trend != "none")
         trendBars++;
      ENUM_SIGNAL s = EvaluateSignal(t, b);
      if(s != SIGNAL_NONE)
         signals++;
      Out(StringFormat("%s | %02d:00%s | %s | %s %s | %s %s | %5.1f %5.1f | %s",
                       TimeToString(open), LondonHour(open), IsEntrySession(open) ? "*" : " ", trend,
                       Mark(PullbackLong(b)), Mark(TriggerLong(b)), Mark(PullbackShort(b)), Mark(TriggerShort(b)),
                       minRsi, maxRsi, SignalText(s)));
   }
   Out(StringFormat("%s: %d signals, %d bars with an H4 trend, %d data failures. (* = inside the London entry session)",
                    sym, signals, trendBars, failures));
   IndicatorRelease(hFast); IndicatorRelease(hSlow); IndicatorRelease(h20); IndicatorRelease(h50); IndicatorRelease(hRsi);
}

void OnStart()
{
   g_file = FileOpen("SignalDiagnostic.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("Signal diagnostic, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   string syms[];
   StringSplit(InpSymbols, ',', syms);
   for(int i = 0; i < ArraySize(syms); i++)
      Diagnose(syms[i]);
   Out("Done.");
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
