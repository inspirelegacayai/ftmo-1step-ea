//+------------------------------------------------------------------+
//| Logger.mqh                                                       |
//| Trade log and daily log CSVs (SPEC section 9).                   |
//|                                                                  |
//| Closed trades are read back from the account history, not        |
//| remembered in memory, so trades that closed while the EA was     |
//| offline are still logged when it starts again. Two facts are     |
//| not in the history and are kept in terminal global variables     |
//| per position: the risk % and spread at entry, and why the EA     |
//| closed it (time stop, Friday close, kill switch).                |
//|                                                                  |
//| Files go to the terminal's common Files folder (FILE_COMMON) so  |
//| tester runs and live runs land in one place.                     |
//+------------------------------------------------------------------+
#ifndef LOGGER_MQH
#define LOGGER_MQH

#include "RiskManager.mqh"

enum ENUM_EXIT_REASON
{
   EXIT_UNKNOWN,
   EXIT_TP,
   EXIT_SL,
   EXIT_TIME_STOP,
   EXIT_FRIDAY_CLOSE,
   EXIT_KILL_SWITCH,
   EXIT_MANUAL,
   EXIT_STOP_OUT
};

string ExitReasonText(const ENUM_EXIT_REASON r)
{
   switch(r)
   {
      case EXIT_TP:           return "TP";
      case EXIT_SL:           return "SL";
      case EXIT_TIME_STOP:    return "time stop";
      case EXIT_FRIDAY_CLOSE: return "Friday close";
      case EXIT_KILL_SWITCH:  return "kill switch";
      case EXIT_MANUAL:       return "manual";
      case EXIT_STOP_OUT:     return "stop out";
      default:                return "unknown";
   }
}

struct TradeRecord
{
   ulong            positionId;
   datetime         entryTime;
   string           symbol;
   bool             isLong;
   double           entryPrice;
   double           stop;
   double           target;
   double           lots;
   double           riskPct;      // -1 when not recorded
   double           spreadPips;   // -1 when not recorded
   datetime         exitTime;
   double           exitPrice;
   ENUM_EXIT_REASON exitReason;
   double           pips;
   double           pnl;          // net: profit + commission + swap + fees over all deals
};

#define TRADE_LOG_HEADER "position,entry_time,symbol,direction,entry_price,stop,target,lots,risk_pct,spread_pips,exit_time,exit_price,exit_reason,pips,pnl"
#define DAILY_LOG_HEADER "ftmo_date,start_balance,end_balance,lowest_equity,trades_taken,kill_switch"

class CLogger
{
private:
   string m_prefix;      // global variable prefix, shared with CRiskManager
   long   m_magic;
   string m_tradeFile;
   string m_dailyFile;
   ulong    m_pendingDeal;   // newest deal seen by NewClosedPositions
   datetime m_pendingTime;

   string Key(const ulong positionId, const string field) const
   {
      return StringFormat("%sp%I64u_%s", m_prefix, positionId, field);
   }

   bool AppendLine(const string file, const string header, const string line) const
   {
      int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE)
      {
         Print("Logger: cannot open ", file, ", error ", GetLastError());
         return false;
      }
      if(FileSize(h) == 0)
         FileWriteString(h, header + "\r\n");
      FileSeek(h, 0, SEEK_END);
      FileWriteString(h, line + "\r\n");
      FileClose(h);
      return true;
   }

   static string Num(const double v, const int digits) { return DoubleToString(v, digits); }
   static string TimeText(const datetime t) { return TimeToString(t, TIME_DATE | TIME_SECONDS); }
   static string Optional(const double v, const int digits) { return v < 0 ? "" : DoubleToString(v, digits); }

public:
   // baseName e.g. "TrendPullback_600060614_20261002". fresh=true empties both files (tester runs).
   void Init(const string prefix, const long magic, const string baseName, const bool fresh)
   {
      m_prefix    = prefix;
      m_magic     = magic;
      m_tradeFile = baseName + "_trades.csv";
      m_dailyFile = baseName + "_daily.csv";
      m_pendingDeal = (ulong)GlobalVariableGet(prefix + "lastDeal");
      m_pendingTime = (datetime)GlobalVariableGet(prefix + "lastDealTime");
      if(fresh)
      {
         FileDelete(m_tradeFile, FILE_COMMON);
         FileDelete(m_dailyFile, FILE_COMMON);
      }
   }

   string TradeFile() const { return m_tradeFile; }
   string DailyFile() const { return m_dailyFile; }

   //--- Facts the account history doesn't keep
   void SaveEntryMeta(const ulong positionId, const double riskPct, const double spreadPips) const
   {
      GlobalVariableSet(Key(positionId, "risk"), riskPct);
      GlobalVariableSet(Key(positionId, "spread"), spreadPips);
   }

   // Call just before the EA closes a position itself
   void SetCloseReason(const ulong positionId, const ENUM_EXIT_REASON reason) const
   {
      GlobalVariableSet(Key(positionId, "why"), (double)reason);
   }

   //--- Reads a closed position back from the account history
   bool ReadClosedTrade(const ulong positionId, TradeRecord &r) const
   {
      if(!HistorySelectByPosition(positionId))
         return false;
      ZeroMemory(r);
      r.positionId = positionId;
      r.riskPct    = GlobalVariableCheck(Key(positionId, "risk"))   ? GlobalVariableGet(Key(positionId, "risk"))   : -1;
      r.spreadPips = GlobalVariableCheck(Key(positionId, "spread")) ? GlobalVariableGet(Key(positionId, "spread")) : -1;
      bool haveIn = false, haveOut = false;
      ENUM_DEAL_REASON outReason = DEAL_REASON_EXPERT;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong d = HistoryDealGetTicket(i);
         r.pnl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) +
                  HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
         {
            haveIn       = true;
            r.entryTime  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            r.symbol     = HistoryDealGetString(d, DEAL_SYMBOL);
            r.isLong     = HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_BUY;
            r.entryPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            r.lots       = HistoryDealGetDouble(d, DEAL_VOLUME);
         }
         else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            haveOut     = true;
            r.exitTime  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            r.exitPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            // Exit deals carry the position's SL/TP at the moment it closed
            r.stop      = HistoryDealGetDouble(d, DEAL_SL);
            r.target    = HistoryDealGetDouble(d, DEAL_TP);
            outReason   = (ENUM_DEAL_REASON)HistoryDealGetInteger(d, DEAL_REASON);
         }
      }
      if(!haveIn || !haveOut)
         return false;

      switch(outReason)
      {
         case DEAL_REASON_TP:     r.exitReason = EXIT_TP; break;
         case DEAL_REASON_SL:     r.exitReason = EXIT_SL; break;
         case DEAL_REASON_SO:     r.exitReason = EXIT_STOP_OUT; break;
         case DEAL_REASON_CLIENT:
         case DEAL_REASON_MOBILE:
         case DEAL_REASON_WEB:    r.exitReason = EXIT_MANUAL; break;
         default:
            r.exitReason = GlobalVariableCheck(Key(positionId, "why"))
                           ? (ENUM_EXIT_REASON)(int)GlobalVariableGet(Key(positionId, "why"))
                           : EXIT_UNKNOWN;
      }
      double pip = PipSizeFor((int)SymbolInfoInteger(r.symbol, SYMBOL_DIGITS), SymbolInfoDouble(r.symbol, SYMBOL_POINT));
      r.pips = pip > 0 ? (r.exitPrice - r.entryPrice) / pip * (r.isLong ? 1 : -1) : 0;
      return true;
   }

   bool LogTrade(const TradeRecord &r) const
   {
      int digits = (int)SymbolInfoInteger(r.symbol, SYMBOL_DIGITS);
      string line = StringFormat("%I64u,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                                 r.positionId, TimeText(r.entryTime), r.symbol, r.isLong ? "long" : "short",
                                 Num(r.entryPrice, digits), Num(r.stop, digits), Num(r.target, digits),
                                 Num(r.lots, 2), Optional(r.riskPct, 2), Optional(r.spreadPips, 1),
                                 TimeText(r.exitTime), Num(r.exitPrice, digits), ExitReasonText(r.exitReason),
                                 Num(r.pips, 1), Num(r.pnl, 2));
      return AppendLine(m_tradeFile, TRADE_LOG_HEADER, line);
   }

   // Removes the per-position globals once the trade is in the log
   void ForgetPosition(const ulong positionId) const
   {
      GlobalVariableDel(Key(positionId, "risk"));
      GlobalVariableDel(Key(positionId, "spread"));
      GlobalVariableDel(Key(positionId, "why"));
   }

   bool LogDay(const DaySummary &d) const
   {
      if(!d.valid)
         return false;
      string line = StringFormat("%s,%s,%s,%s,%d,%s",
                                 TimeToString(d.ftmoDate, TIME_DATE), Num(d.startBalance, 2), Num(d.endBalance, 2),
                                 Num(d.lowestEquity, 2), d.entries, d.killSwitch ? "yes" : "no");
      return AppendLine(m_dailyFile, DAILY_LOG_HEADER, line);
   }

   //--- Finds this EA's positions closed since the last MarkProcessed() and returns their
   //--- ids, oldest first. Call MarkProcessed() after logging them, so a crash in between
   //--- means they are found again rather than lost.
   int NewClosedPositions(ulong &ids[])
   {
      ArrayResize(ids, 0);
      ulong    lastDeal = (ulong)GlobalVariableGet(m_prefix + "lastDeal");
      datetime lastTime = (datetime)GlobalVariableGet(m_prefix + "lastDealTime");
      if(!HistorySelect(lastTime, TimeCurrent() + TH_DAY))
         return 0;
      ulong newestDeal = lastDeal;
      datetime newestTime = lastTime;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d <= lastDeal || HistoryDealGetInteger(d, DEAL_MAGIC) != m_magic)
            continue;
         if(d > newestDeal)
         {
            newestDeal = d;
            newestTime = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         }
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
            continue;
         int n = ArraySize(ids);
         ArrayResize(ids, n + 1);
         ids[n] = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      }
      m_pendingDeal = newestDeal;
      m_pendingTime = newestTime;
      return ArraySize(ids);
   }

   void MarkProcessed() const
   {
      GlobalVariableSet(m_prefix + "lastDeal", (double)m_pendingDeal);
      GlobalVariableSet(m_prefix + "lastDealTime", (double)m_pendingTime);
      GlobalVariablesFlush();
   }
};

#endif
