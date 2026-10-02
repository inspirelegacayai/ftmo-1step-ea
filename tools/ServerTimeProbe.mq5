//+------------------------------------------------------------------+
//| ServerTimeProbe.mq5                                              |
//| Read-only diagnostic for SPEC section 15. Places no orders.      |
//| Writes MQL5\Files\ServerTimeProbe.txt with:                      |
//|  - live server time vs GMT (current offset)                      |
//|  - matching symbol names and contract specs                      |
//|  - history depth                                                 |
//|  - every weekly-open time on H1, to infer the DST schedule:      |
//|    the FX week opens at 17:00 New York, so if the server tracks  |
//|    US DST the open lands on the same server hour all year, and   |
//|    any shift shows the dates the server changes its offset.      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input string ProbeSymbol = "EURUSD";   // symbol to scan weekly opens on
input int    MaxYears    = 12;         // how far back to request history

int g_file = INVALID_HANDLE;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

string Weekday(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   static const string names[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   return names[d.day_of_week];
}

void ReportClock()
{
   datetime server = TimeTradeServer();
   datetime gmt    = TimeGMT();
   // Round to the nearest quarter hour; the two calls are not simultaneous
   int offsetMin = (int)MathRound((double)(server - gmt) / 900.0) * 15;
   Out("== Clock ==");
   Out("TimeTradeServer: " + TimeToString(server, TIME_DATE | TIME_SECONDS) + " " + Weekday(server));
   Out("TimeGMT:         " + TimeToString(gmt, TIME_DATE | TIME_SECONDS));
   Out("TimeLocal:       " + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   Out(StringFormat("Server offset from GMT now: %+d min (%+.2f h)", offsetMin, offsetMin / 60.0));
   Out("Account server: " + AccountInfoString(ACCOUNT_SERVER) + "  company: " + AccountInfoString(ACCOUNT_COMPANY));
   Out("Account currency: " + AccountInfoString(ACCOUNT_CURRENCY) + "  leverage: " + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)));
}

void ReportSymbols()
{
   Out("");
   Out("== Symbols matching EURUSD / GBPUSD ==");
   for(int i = 0; i < SymbolsTotal(false); i++)
   {
      string s = SymbolName(i, false);
      if(StringFind(s, "EURUSD") < 0 && StringFind(s, "GBPUSD") < 0)
         continue;
      Out(StringFormat("%s  digits=%d  contract=%.0f  vol min/step/max=%.2f/%.2f/%.2f  calcmode=%d  tickvalue=%.5f  ticksize=%.5f",
                       s,
                       (int)SymbolInfoInteger(s, SYMBOL_DIGITS),
                       SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE),
                       SymbolInfoDouble(s, SYMBOL_VOLUME_MIN),
                       SymbolInfoDouble(s, SYMBOL_VOLUME_STEP),
                       SymbolInfoDouble(s, SYMBOL_VOLUME_MAX),
                       (int)SymbolInfoInteger(s, SYMBOL_TRADE_CALC_MODE),
                       SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE),
                       SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE)));
   }
}

// Requests H1 history, retrying while the terminal downloads it
int LoadRates(MqlRates &rates[])
{
   datetime from = TimeTradeServer() - (datetime)MaxYears * 365 * 86400;
   int got = -1;
   for(int attempt = 0; attempt < 30 && !IsStopped(); attempt++)
   {
      got = CopyRates(ProbeSymbol, PERIOD_H1, from, TimeTradeServer(), rates);
      if(got > 0 && attempt >= 3)
         break;
      Sleep(1000);
   }
   return got;
}

void ReportWeeklyOpens()
{
   SymbolSelect(ProbeSymbol, true);
   Out("");
   Out("== History depth for " + ProbeSymbol + " ==");
   Out("SERVER_FIRSTDATE: " + TimeToString((datetime)SeriesInfoInteger(ProbeSymbol, PERIOD_H1, SERIES_SERVER_FIRSTDATE)));
   Out("TERMINAL_FIRSTDATE: " + TimeToString((datetime)SeriesInfoInteger(ProbeSymbol, PERIOD_H1, SERIES_TERMINAL_FIRSTDATE)));

   MqlRates rates[];
   int n = LoadRates(rates);
   Out(StringFormat("H1 bars loaded: %d", n));
   if(n < 2)
      return;
   Out("First bar: " + TimeToString(rates[0].time) + "  last bar: " + TimeToString(rates[n - 1].time));

   Out("");
   Out("== Weekly opens (gap > 24h). Full list, then changes only ==");
   string prevKey = "";
   string changes[];
   for(int i = 1; i < n; i++)
   {
      if(rates[i].time - rates[i - 1].time <= 86400)
         continue;
      MqlDateTime o, c;
      TimeToStruct(rates[i].time, o);
      TimeToStruct(rates[i - 1].time, c);
      string key = StringFormat("open %s %02d:00 | last bar before gap %s %02d:00",
                                Weekday(rates[i].time), o.hour, Weekday(rates[i - 1].time), c.hour);
      string line = TimeToString(rates[i].time, TIME_DATE) + "  " + key;
      Out(line);
      if(key != prevKey)
      {
         int k = ArraySize(changes);
         ArrayResize(changes, k + 1);
         changes[k] = line;
         prevKey = key;
      }
   }
   Out("");
   Out("== Pattern changes ==");
   for(int k = 0; k < ArraySize(changes); k++)
      Out(changes[k]);
}

void OnStart()
{
   g_file = FileOpen("ServerTimeProbe.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_file == INVALID_HANDLE)
      Print("Could not open output file, error ", GetLastError(), ". Printing to Experts log only.");
   ReportClock();
   ReportSymbols();
   ReportWeeklyOpens();
   Out("");
   Out("Done.");
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
