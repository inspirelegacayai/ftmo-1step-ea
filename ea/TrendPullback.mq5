//+------------------------------------------------------------------+
//| TrendPullback.mq5                                                |
//| Trend Pullback EA for FTMO 1-Step. SPEC.md v1.0 is the source    |
//| of truth.                                                        |
//|                                                                  |
//| One instance trades both symbols, so the shared limits (2 open   |
//| positions, 2 entries per FTMO day) are enforced in one place.    |
//| Attach to any chart; a 1-second timer drives the symbol that is  |
//| not on the chart.                                                |
//+------------------------------------------------------------------+
#property strict
#property version     "1.00"
#property description "Trend Pullback EA for FTMO 1-Step (SPEC v1.0)"

#include <Trade\Trade.mqh>
#include "include\TimeHelper.mqh"
#include "include\FtmoRules.mqh"
#include "include\RiskManager.mqh"
#include "include\TrendPullbackSignals.mqh"
#include "include\Logger.mqh"

#define SYMBOL_COUNT        2
#define MAX_SLIPPAGE_POINTS 20   // market order deviation, 2 pips on 5-digit quotes
#define NEWS_CURRENCIES     "USD,EUR,GBP"

input group "Symbols (FTMO names may carry a suffix)"
input string InpSymbol1        = "EURUSD.sim";
input double InpMaxSpreadPips1 = 2.0;
input string InpSymbol2        = "GBPUSD.sim";
input double InpMaxSpreadPips2 = 2.5;

input group "Risk"
input double InpInitialBalance     = 0;                 // FTMO initial balance (0 = tester deposit, tester only)
input double InpRiskPercent        = RISK_DEFAULT_PCT;  // % of initial balance per trade (0.25 for the first two weeks)
input double InpHighestEodBalance  = 0;                 // Highest end-of-day balance from FTMO dashboard (0 = keep tracked)
input bool   InpFloorGuardReviewed = false;             // Set true after reviewing a floor guard stop, then back to false

input group "Strategy"
input int    InpTakeProfitPips = 40;
input bool   InpUseNewsFilter  = true;                  // Calendar does not work in the tester; ignored there

input group "EA"
input long   InpMagic  = 20261002;
input string InpLogTag = "";                            // Added to log file names, e.g. "TP40_2016-2018"

struct SymbolContext
{
   string   name;
   double   maxSpreadPips;
   double   pip;
   int      digits;
   int      hEmaFastH4;
   int      hEmaSlowH4;
   int      hEma20H1;
   int      hEma50H1;
   int      hRsiH1;
   datetime lastBarTime;   // H1 bar already evaluated
};

CTrade        g_trade;
CRiskManager  g_risk;
CLogger       g_log;
SymbolContext g_sym[SYMBOL_COUNT];
bool          g_tester     = false;
bool          g_newsFilter = false;

//+------------------------------------------------------------------+
//| Notifications: journal always, push on a live terminal           |
//+------------------------------------------------------------------+
void Notify(const string message)
{
   string text = "TrendPullback " + AccountInfoString(ACCOUNT_SERVER) + ": " + message;
   Print(text);
   if(!g_tester && !SendNotification(text))
      Print("Push notification failed, error ", GetLastError(), ". Check Tools > Options > Notifications.");
}

//+------------------------------------------------------------------+
//| Setup                                                            |
//+------------------------------------------------------------------+
bool InitSymbol(SymbolContext &c, const string name, const double maxSpreadPips)
{
   c.name          = name;
   c.maxSpreadPips = maxSpreadPips;
   if(!SymbolSelect(name, true))
   {
      Print("Symbol ", name, " not found. Check the symbol name inputs.");
      return false;
   }
   c.digits      = (int)SymbolInfoInteger(name, SYMBOL_DIGITS);
   c.pip         = PipSizeFor(c.digits, SymbolInfoDouble(name, SYMBOL_POINT));
   c.hEmaFastH4  = iMA(name, PERIOD_H4, TREND_EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   c.hEmaSlowH4  = iMA(name, PERIOD_H4, TREND_EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
   c.hEma20H1    = iMA(name, PERIOD_H1, PULLBACK_EMA, 0, MODE_EMA, PRICE_CLOSE);
   c.hEma50H1    = iMA(name, PERIOD_H1, PULLBACK_GUARD_EMA, 0, MODE_EMA, PRICE_CLOSE);
   c.hRsiH1      = iRSI(name, PERIOD_H1, RSI_PERIOD, PRICE_CLOSE);
   // Start from the bar in progress: signals only fire on the first tick of a new bar
   c.lastBarTime = iTime(name, PERIOD_H1, 0);
   if(c.hEmaFastH4 == INVALID_HANDLE || c.hEmaSlowH4 == INVALID_HANDLE || c.hEma20H1 == INVALID_HANDLE ||
      c.hEma50H1 == INVALID_HANDLE || c.hRsiH1 == INVALID_HANDLE)
   {
      Print("Indicator handle failed for ", name, ", error ", GetLastError());
      return false;
   }
   return true;
}

void ReleaseSymbol(SymbolContext &c)
{
   IndicatorRelease(c.hEmaFastH4);
   IndicatorRelease(c.hEmaSlowH4);
   IndicatorRelease(c.hEma20H1);
   IndicatorRelease(c.hEma50H1);
   IndicatorRelease(c.hRsiH1);
}

int OnInit()
{
   g_tester     = (bool)MQLInfoInteger(MQL_TESTER);
   g_newsFilter = InpUseNewsFilter && !g_tester;
   if(InpUseNewsFilter && g_tester)
      Print("News filter is on but the economic calendar is unavailable in the tester. Running without it.");

   double initial = InpInitialBalance;
   if(initial <= 0.0)
   {
      if(!g_tester)
      {
         Print("Set InpInitialBalance to the FTMO account's initial balance.");
         return INIT_PARAMETERS_INCORRECT;
      }
      initial = AccountInfoDouble(ACCOUNT_BALANCE);
   }
   if(InpRiskPercent <= 0.0 || InpTakeProfitPips <= 0)
   {
      Print("InpRiskPercent and InpTakeProfitPips must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!InitSymbol(g_sym[0], InpSymbol1, InpMaxSpreadPips1) ||
      !InitSymbol(g_sym[1], InpSymbol2, InpMaxSpreadPips2))
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(MAX_SLIPPAGE_POINTS);

   string prefix = StringFormat("TP_%I64d_%I64d_", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic);
   g_risk.Init(prefix, initial, InpRiskPercent);
   bool restored = g_risk.Load();
   if(InpHighestEodBalance > 0.0)
      g_risk.RaiseHighestEodBalance(InpHighestEodBalance);
   if(InpFloorGuardReviewed && g_risk.FloorGuardLatched())
   {
      g_risk.ClearFloorGuardAfterReview();
      Notify("Floor guard cleared after manual review. Set InpFloorGuardReviewed back to false.");
   }
   g_risk.Save();

   // Tester runs start empty files; live runs append across restarts
   string logName = g_tester ? "TrendPullback_tester"
                             : StringFormat("TrendPullback_%I64d_%I64d", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic);
   if(InpLogTag != "")
      logName += "_" + InpLogTag;
   g_log.Init(prefix, InpMagic, logName, g_tester);
   ProcessClosedTrades();   // catch up on trades that closed while the EA was off

   EventSetTimer(1);
   Notify(StringFormat("started. Initial balance %.2f, risk %.2f%%, TP %d pips, state %s. Daily floor %.2f, trailing floor %.2f.",
                       initial, InpRiskPercent, InpTakeProfitPips, restored ? "restored" : "new",
                       g_risk.DailyFloor(), g_risk.TrailingFloor()));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < SYMBOL_COUNT; i++)
      ReleaseSymbol(g_sym[i]);
   ProcessClosedTrades();
   // A tester run ends mid-day; log that day so the daily log covers the whole run.
   // Live restarts don't: the day isn't over and would be logged twice.
   if(g_tester)
   {
      DaySummary d;
      g_risk.SummariseDay(d, AccountInfoDouble(ACCOUNT_BALANCE));
      g_log.LogDay(d);
   }
   g_risk.Save();
   Notify("stopped, reason code " + IntegerToString(reason) + ".");
}

//+------------------------------------------------------------------+
//| Positions (this EA's magic only)                                 |
//+------------------------------------------------------------------+
int CountPositions(const string symbol)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(symbol == "" || PositionGetString(POSITION_SYMBOL) == symbol)
         count++;
   }
   return count;
}

bool ClosePosition(const ulong ticket, const ENUM_EXIT_REASON why)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   string symbol = PositionGetString(POSITION_SYMBOL);
   string reason = ExitReasonText(why);
   g_log.SetCloseReason((ulong)PositionGetInteger(POSITION_IDENTIFIER), why);
   bool sent = g_trade.PositionClose(ticket, MAX_SLIPPAGE_POINTS);
   uint code = g_trade.ResultRetcode();
   if(sent && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("Closed #%I64u %s (%s) at %.5f", ticket, symbol, reason, g_trade.ResultPrice());
      return true;
   }
   Notify(StringFormat("ERROR closing #%I64u %s (%s): retcode %u %s", ticket, symbol, reason,
                       code, g_trade.ResultRetcodeDescription()));
   return false;
}

void CloseAll(const ENUM_EXIT_REASON reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         ClosePosition(ticket, reason);
   }
}

void ApplyTimeStops(const datetime now)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(TimeStopDue((datetime)PositionGetInteger(POSITION_TIME), now))
         ClosePosition(ticket, EXIT_TIME_STOP);
   }
}

//+------------------------------------------------------------------+
//| Data                                                             |
//+------------------------------------------------------------------+
bool CopyOne(const int handle, double &value)
{
   double buf[];
   if(CopyBuffer(handle, 0, 1, 1, buf) != 1)
      return false;
   value = buf[0];
   return true;
}

bool CopyClosedBars(const int handle, double &out[])
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 1, PULLBACK_BARS, buf) != PULLBACK_BARS)
      return false;
   for(int i = 0; i < PULLBACK_BARS; i++)
      out[i] = buf[i];
   return true;
}

// Closed bars only: every copy starts at index 1
bool LoadSignalData(const SymbolContext &c, H4Trend &t, H1Bars &b)
{
   double h4close[];
   if(CopyClose(c.name, PERIOD_H4, 1, 1, h4close) != 1)
      return false;
   t.close = h4close[0];
   if(!CopyOne(c.hEmaFastH4, t.emaFast) || !CopyOne(c.hEmaSlowH4, t.emaSlow))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(c.name, PERIOD_H1, 1, PULLBACK_BARS, rates) != PULLBACK_BARS)
      return false;
   for(int i = 0; i < PULLBACK_BARS; i++)
   {
      b.open[i]  = rates[i].open;
      b.high[i]  = rates[i].high;
      b.low[i]   = rates[i].low;
      b.close[i] = rates[i].close;
   }
   return CopyClosedBars(c.hEma20H1, b.ema20) && CopyClosedBars(c.hEma50H1, b.ema50) &&
          CopyClosedBars(c.hRsiH1, b.rsi);
}

//+------------------------------------------------------------------+
//| News filter: high-impact USD/EUR/GBP within +-30 minutes          |
//| Calendar times are in trade server time.                         |
//+------------------------------------------------------------------+
// Returns true when entries are blocked. A calendar error blocks too: unknown is not safe.
bool NewsBlackout(const datetime now, string &why)
{
   string currencies[];
   StringSplit(NEWS_CURRENCIES, ',', currencies);
   datetime from = now - NEWS_WINDOW_MINUTES * 60;
   datetime to   = now + NEWS_WINDOW_MINUTES * 60;
   for(int c = 0; c < ArraySize(currencies); c++)
   {
      MqlCalendarValue values[];
      ResetLastError();
      if(!CalendarValueHistory(values, from, to, NULL, currencies[c]))
      {
         int err = GetLastError();
         if(err == 0)
            continue;   // an empty window can report false without an error
         why = StringFormat("calendar error %d for %s", err, currencies[c]);
         return true;
      }
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            why = StringFormat("%s %s at %s", currencies[c], ev.name, TimeToString(values[i].time));
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Entries                                                          |
//+------------------------------------------------------------------+
void SkipLog(const SymbolContext &c, const ENUM_SIGNAL s, const string why)
{
   PrintFormat("%s %s signal skipped: %s", c.name, SignalText(s), why);
}

// Moves TP to TakeProfitPips from the actual fill. The stop is a fixed chart level and stays.
void AlignTakeProfitToFill(const SymbolContext &c, const ENUM_SIGNAL s, const ulong dealTicket)
{
   if(!HistoryDealSelect(dealTicket))
      return;
   ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(!PositionSelectByTicket(positionId))
      return;
   double fill = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double want = NormalizeDouble(s == SIGNAL_LONG ? fill + InpTakeProfitPips * c.pip
                                                  : fill - InpTakeProfitPips * c.pip, c.digits);
   if(MathAbs(tp - want) < SymbolInfoDouble(c.name, SYMBOL_POINT) / 2.0)
      return;
   if(!g_trade.PositionModify(positionId, sl, want) || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      Notify(StringFormat("ERROR aligning TP on %s #%I64u to %.5f: retcode %u %s", c.name, positionId, want,
                          g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
}

void TryEntry(SymbolContext &c, const ENUM_SIGNAL s, const H1Bars &b, const datetime barOpen, const datetime now)
{
   ENUM_ENTRY_CHECK limit = g_risk.CheckNewEntry(CountPositions(c.name), CountPositions(""));
   if(limit != ENTRY_ALLOWED)            { SkipLog(c, s, EntryCheckText(limit)); return; }
   if(IsHolidayBlackout(barOpen))        { SkipLog(c, s, "holiday blackout"); return; }
   if(!IsEntrySession(barOpen))          { SkipLog(c, s, "outside London session"); return; }

   double ask = SymbolInfoDouble(c.name, SYMBOL_ASK);
   double bid = SymbolInfoDouble(c.name, SYMBOL_BID);
   double spreadPips = (ask - bid) / c.pip;
   if(!SpreadOk(spreadPips, c.maxSpreadPips))
   {
      SkipLog(c, s, StringFormat("spread %.1f pips over %.1f", spreadPips, c.maxSpreadPips));
      return;
   }

   string newsWhy = "";
   if(g_newsFilter && NewsBlackout(now, newsWhy)) { SkipLog(c, s, "news: " + newsWhy); return; }

   bool   isLong = (s == SIGNAL_LONG);
   double entry  = isLong ? ask : bid;
   double sl     = NormalizeDouble(isLong ? StopLossLong(b, c.pip) : StopLossShort(b, c.pip), c.digits);
   double tp     = NormalizeDouble(isLong ? entry + InpTakeProfitPips * c.pip : entry - InpTakeProfitPips * c.pip, c.digits);
   double stopPips = StopPips(entry, sl, c.pip);
   if((isLong && sl >= entry) || (!isLong && sl <= entry))
   {
      SkipLog(c, s, StringFormat("price already through the stop level %.5f", sl));
      return;
   }
   if(!StopSizeOk(stopPips))
   {
      SkipLog(c, s, StringFormat("stop %.1f pips outside %.0f-%.0f", stopPips, STOP_MIN_PIPS, STOP_MAX_PIPS));
      return;
   }

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskPct = g_risk.RiskPctForNextTrade(equity);
   double lots    = g_risk.LotsFor(c.name, stopPips, riskPct);
   if(lots <= 0.0)
   {
      SkipLog(c, s, StringFormat("lot size below minimum at %.2f%% risk", riskPct));
      return;
   }

   g_trade.SetTypeFillingBySymbol(c.name);
   string comment = StringFormat("TP %s %.1fp %.2f%%", isLong ? "L" : "S", stopPips, riskPct);
   bool sent = isLong ? g_trade.Buy(lots, c.name, 0.0, sl, tp, comment)
                      : g_trade.Sell(lots, c.name, 0.0, sl, tp, comment);
   uint code = g_trade.ResultRetcode();
   if(!sent || (code != TRADE_RETCODE_DONE && code != TRADE_RETCODE_DONE_PARTIAL))
   {
      Notify(StringFormat("ERROR opening %s %s %.2f lots SL %.5f TP %.5f: retcode %u %s", c.name, SignalText(s),
                          lots, sl, tp, code, g_trade.ResultRetcodeDescription()));
      return;
   }

   g_risk.OnEntryOpened();
   if(HistoryDealSelect(g_trade.ResultDeal()))
      g_log.SaveEntryMeta((ulong)HistoryDealGetInteger(g_trade.ResultDeal(), DEAL_POSITION_ID), riskPct, spreadPips);
   PrintFormat("Opened %s %s %.2f lots at %.5f, SL %.5f (%.1f pips), TP %.5f, risk %.2f%%, spread %.1f pips",
               c.name, SignalText(s), lots, g_trade.ResultPrice(), sl, stopPips, tp, riskPct, spreadPips);
   AlignTakeProfitToFill(c, s, g_trade.ResultDeal());
}

// Evaluates a symbol once per new H1 bar
void CheckNewBar(SymbolContext &c, const datetime now)
{
   datetime barOpen = iTime(c.name, PERIOD_H1, 0);
   if(barOpen == 0 || barOpen == c.lastBarTime)
      return;

   H4Trend t;
   H1Bars  b;
   if(!LoadSignalData(c, t, b))
      return;   // history or indicators not ready; try again next tick
   c.lastBarTime = barOpen;

   ENUM_SIGNAL s = EvaluateSignal(t, b);
   if(s != SIGNAL_NONE)
      TryEntry(c, s, b, barOpen, now);
}

//+------------------------------------------------------------------+
//| Main loop                                                        |
//+------------------------------------------------------------------+
void Process()
{
   datetime now = TimeCurrent();
   int events = g_risk.OnTick(now, AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));

   if((events & RISK_EVENT_NEW_DAY) != 0)
   {
      DaySummary ended;
      g_risk.LastDaySummary(ended);
      g_log.LogDay(ended);
      PrintFormat("New FTMO day %s. Daily floor %.2f, trailing floor %.2f.",
                  TimeToString(FtmoDate(now), TIME_DATE), g_risk.DailyFloor(), g_risk.TrailingFloor());
   }
   if((events & RISK_EVENT_KILL_SWITCH) != 0)
      Notify(StringFormat("KILL SWITCH: equity %.2f hit start-of-day balance minus %.1f%%. Closing all, no entries until the next FTMO day.",
                          AccountInfoDouble(ACCOUNT_EQUITY), KILL_SWITCH_LOSS_PCT));
   if((events & RISK_EVENT_FLOOR_GUARD) != 0)
      Notify(StringFormat("FLOOR GUARD: equity %.2f within %.1f%% of the trailing floor %.2f. New entries blocked until manual review.",
                          AccountInfoDouble(ACCOUNT_EQUITY), FLOOR_GUARD_BLOCK_PCT, g_risk.TrailingFloor()));

   // Repeats every tick while active, in case a close failed
   if(g_risk.KillSwitchActive() && CountPositions("") > 0)
      CloseAll(EXIT_KILL_SWITCH);
   if(IsFridayCloseTime(now) && CountPositions("") > 0)
      CloseAll(EXIT_FRIDAY_CLOSE);
   ApplyTimeStops(now);

   for(int i = 0; i < SYMBOL_COUNT; i++)
      CheckNewBar(g_sym[i], now);
}

void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
//| Closed trades: trade log and losing streak                       |
//| Read from the account history, so trades that closed while the   |
//| EA was off are caught at the next start.                          |
//+------------------------------------------------------------------+
void ProcessClosedTrades()
{
   ulong ids[];
   if(g_log.NewClosedPositions(ids) == 0)
   {
      g_log.MarkProcessed();
      return;
   }
   for(int i = 0; i < ArraySize(ids); i++)
   {
      TradeRecord r;
      if(!g_log.ReadClosedTrade(ids[i], r))
      {
         Notify(StringFormat("ERROR reading closed position #%I64u from history; not logged, losing streak not updated", ids[i]));
         continue;
      }
      g_log.LogTrade(r);
      g_risk.OnPositionClosed(r.pnl);
      g_log.ForgetPosition(ids[i]);
      PrintFormat("Closed %s %s #%I64u: %s, %.1f pips, net %.2f", r.symbol, r.isLong ? "long" : "short",
                  ids[i], ExitReasonText(r.exitReason), r.pips, r.pnl);
   }
   g_log.MarkProcessed();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      ProcessClosedTrades();
}
