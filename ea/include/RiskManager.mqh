//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| EA risk rules (SPEC section 6): position sizing, entry limits,   |
//| losing streak brake, daily kill switch, trailing floor guard,    |
//| and the state that must survive a restart (section 8).           |
//|                                                                  |
//| The decision logic takes time, balance and equity as arguments   |
//| so tests can drive it without a market. The EA executes the      |
//| actions (closing positions, notifications) it returns.           |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "FtmoRules.mqh"
#include "TimeHelper.mqh"

//--- EA risk limits. All percentages are of INITIAL balance. ------------
#define RISK_DEFAULT_PCT            0.5    // default for the RiskPercent input
#define RISK_REDUCED_PCT            0.25   // streak brake and floor guard
#define LOSING_STREAK_LIMIT         3      // losses in a row before the brake
#define MAX_POSITIONS_PER_SYMBOL    1
#define MAX_POSITIONS_TOTAL         2
#define MAX_ENTRIES_PER_FTMO_DAY    2
#define KILL_SWITCH_LOSS_PCT        1.5    // below start-of-day balance
#define FLOOR_GUARD_REDUCE_PCT      3.0    // above the trailing floor
#define FLOOR_GUARD_BLOCK_PCT       1.5    // above the trailing floor

//--- Events returned by CRiskManager::OnTick (bit flags) ---------------
#define RISK_EVENT_NONE          0
#define RISK_EVENT_NEW_DAY       1
#define RISK_EVENT_KILL_SWITCH   2   // close all, block until next FTMO day, notify
#define RISK_EVENT_FLOOR_GUARD   4   // block until manual review, notify

enum ENUM_ENTRY_CHECK
{
   ENTRY_ALLOWED,
   ENTRY_BLOCKED_KILL_SWITCH,
   ENTRY_BLOCKED_FLOOR_GUARD,
   ENTRY_BLOCKED_DAILY_ENTRIES,
   ENTRY_BLOCKED_SYMBOL_POSITION,
   ENTRY_BLOCKED_TOTAL_POSITIONS
};

string EntryCheckText(const ENUM_ENTRY_CHECK check)
{
   switch(check)
   {
      case ENTRY_ALLOWED:                 return "allowed";
      case ENTRY_BLOCKED_KILL_SWITCH:     return "kill switch active";
      case ENTRY_BLOCKED_FLOOR_GUARD:     return "floor guard active, needs manual review";
      case ENTRY_BLOCKED_DAILY_ENTRIES:   return "max entries for this FTMO day reached";
      case ENTRY_BLOCKED_SYMBOL_POSITION: return "position already open on this symbol";
      case ENTRY_BLOCKED_TOTAL_POSITIONS: return "max total positions open";
   }
   return "unknown";
}

//--- Sizing -------------------------------------------------------------

// A pip is 10 points on 3- and 5-digit quotes
double PipSizeFor(const int digits, const double point)
{
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double PipValuePerLot(const double tickValue, const double tickSize, const double pipSize)
{
   if(tickSize <= 0.0)
      return 0.0;
   return tickValue * pipSize / tickSize;
}

// Rounds down to the volume step and caps at max volume. Returns 0 when the
// result is below min volume: rounding up to the minimum would risk more
// than allowed, so the trade is skipped instead.
double CalcLots(const double riskMoney, const double stopPips, const double pipValuePerLot,
                const double volMin, const double volMax, const double volStep)
{
   if(riskMoney <= 0.0 || stopPips <= 0.0 || pipValuePerLot <= 0.0 || volStep <= 0.0)
      return 0.0;
   double raw = riskMoney / (stopPips * pipValuePerLot);
   // Small epsilon so 0.12 / 0.01 = 11.9999999 still floors to 12 steps
   double lots = MathFloor(raw / volStep + 1e-7) * volStep;
   lots = MathMin(lots, MathFloor(volMax / volStep + 1e-7) * volStep);
   if(lots < volMin - 1e-9)
      return 0.0;
   return NormalizeDouble(lots, 8);
}

//--- Risk rules as pure functions ------------------------------------------

double KillSwitchEquity(const double startOfDayBalance, const double initialBalance)
{
   return startOfDayBalance - PctOfInitial(initialBalance, KILL_SWITCH_LOSS_PCT);
}

double FloorHeadroom(const double equity, const double highestEodBalance, const double initialBalance)
{
   return equity - FtmoTrailingFloor(highestEodBalance, initialBalance);
}

// Brakes only ever lower risk, never raise it above the configured base
double EffectiveRiskPct(const double baseRiskPct, const int losingStreak, const double equity,
                        const double highestEodBalance, const double initialBalance)
{
   bool streakBrake = losingStreak >= LOSING_STREAK_LIMIT;
   bool nearFloor   = FloorHeadroom(equity, highestEodBalance, initialBalance)
                      <= PctOfInitial(initialBalance, FLOOR_GUARD_REDUCE_PCT);
   if(streakBrake || nearFloor)
      return MathMin(baseRiskPct, RISK_REDUCED_PCT);
   return baseRiskPct;
}

//--- Persistent state ------------------------------------------------------

struct RiskState
{
   datetime ftmoDate;            // Prague date of the current FTMO day, 0 = not started
   double   startOfDayBalance;
   double   highestEodBalance;
   int      losingStreak;
   int      entriesToday;
   bool     killSwitchActive;
   bool     floorGuardLatched;
   double   lowestEquity;        // lowest equity seen this FTMO day
};

// One finished FTMO day, for the daily log (SPEC section 9)
struct DaySummary
{
   bool     valid;
   datetime ftmoDate;
   double   startBalance;
   double   endBalance;
   double   lowestEquity;
   int      entries;
   bool     killSwitch;
};

class CRiskManager
{
private:
   string     m_prefix;          // terminal global variable name prefix
   double     m_initialBalance;
   double     m_baseRiskPct;
   RiskState  m_state;
   DaySummary m_lastDay;         // filled when a day rolls over

   string Key(const string field) const { return m_prefix + field; }

public:
   // prefix should be unique per account and magic number, e.g. "TP_<login>_<magic>_"
   void Init(const string prefix, const double initialBalance, const double baseRiskPct)
   {
      m_prefix         = prefix;
      m_initialBalance = initialBalance;
      m_baseRiskPct    = baseRiskPct;
      ZeroMemory(m_state);
      ZeroMemory(m_lastDay);
      m_state.highestEodBalance = initialBalance;
   }

   //--- Persistence (terminal global variables; tester keeps its own set)
   bool Load()
   {
      if(!GlobalVariableCheck(Key("saved")))
         return false;
      m_state.ftmoDate          = (datetime)GlobalVariableGet(Key("ftmoDate"));
      m_state.startOfDayBalance = GlobalVariableGet(Key("sodBalance"));
      m_state.highestEodBalance = GlobalVariableGet(Key("highestEod"));
      m_state.losingStreak      = (int)GlobalVariableGet(Key("streak"));
      m_state.entriesToday      = (int)GlobalVariableGet(Key("entries"));
      m_state.killSwitchActive  = GlobalVariableGet(Key("kill")) != 0.0;
      m_state.floorGuardLatched = GlobalVariableGet(Key("guard")) != 0.0;
      m_state.lowestEquity      = GlobalVariableGet(Key("lowEquity"));
      return true;
   }

   // flush=false skips the disk write, for frequent low-stakes updates (new equity lows)
   bool Save(const bool flush = true) const
   {
      bool ok = true;
      ok &= GlobalVariableSet(Key("ftmoDate"),   (double)m_state.ftmoDate) > 0;
      ok &= GlobalVariableSet(Key("sodBalance"), m_state.startOfDayBalance) > 0;
      ok &= GlobalVariableSet(Key("highestEod"), m_state.highestEodBalance) > 0;
      ok &= GlobalVariableSet(Key("streak"),     m_state.losingStreak) > 0;
      ok &= GlobalVariableSet(Key("entries"),    m_state.entriesToday) > 0;
      ok &= GlobalVariableSet(Key("kill"),       m_state.killSwitchActive ? 1.0 : 0.0) > 0;
      ok &= GlobalVariableSet(Key("guard"),      m_state.floorGuardLatched ? 1.0 : 0.0) > 0;
      ok &= GlobalVariableSet(Key("lowEquity"),  m_state.lowestEquity) > 0;
      ok &= GlobalVariableSet(Key("saved"),      1.0) > 0;
      if(flush)
         GlobalVariablesFlush();
      return ok;
   }

   void DeleteSaved() const { GlobalVariablesDeleteAll(m_prefix); }

   // The floor guard resumes only after manual review: the owner sets the
   // review input, which clears the latch on the next init. OnTick latches it
   // again straight away if equity is still inside the block band.
   void ClearFloorGuardAfterReview() { m_state.floorGuardLatched = false; }

   // For attaching mid-challenge: the highest end-of-day balance from the FTMO
   // dashboard. Only ever raises the tracked value, so a stale input can't
   // loosen the trailing floor.
   void RaiseHighestEodBalance(const double value)
   {
      if(value > m_state.highestEodBalance)
         m_state.highestEodBalance = value;
   }

   //--- Call on every tick. Returns RISK_EVENT_* flags for the EA to act on.
   int OnTick(const datetime server, const double balance, const double equity)
   {
      int events = RISK_EVENT_NONE;
      datetime today = FtmoDate(server);

      if(m_state.ftmoDate == 0)
      {
         m_state.ftmoDate          = today;
         m_state.startOfDayBalance = balance;
         m_state.lowestEquity      = equity;
         events |= RISK_EVENT_NEW_DAY;
      }
      else if(today != m_state.ftmoDate)
      {
         // The balance now is the previous day's end-of-day balance
         SummariseDay(m_lastDay, balance);
         m_state.highestEodBalance = MathMax(m_state.highestEodBalance, balance);
         m_state.startOfDayBalance = balance;
         m_state.entriesToday      = 0;
         m_state.killSwitchActive  = false;
         m_state.ftmoDate          = today;
         m_state.lowestEquity      = equity;
         events |= RISK_EVENT_NEW_DAY;
      }

      bool newLow = equity < m_state.lowestEquity;
      if(newLow)
         m_state.lowestEquity = equity;

      if(!m_state.killSwitchActive && equity <= KillSwitchEquity(m_state.startOfDayBalance, m_initialBalance))
      {
         m_state.killSwitchActive = true;
         events |= RISK_EVENT_KILL_SWITCH;
      }

      if(!m_state.floorGuardLatched &&
         FloorHeadroom(equity, m_state.highestEodBalance, m_initialBalance)
            <= PctOfInitial(m_initialBalance, FLOOR_GUARD_BLOCK_PCT))
      {
         m_state.floorGuardLatched = true;
         events |= RISK_EVENT_FLOOR_GUARD;
      }

      if(events != RISK_EVENT_NONE)
         Save();
      else if(newLow)
         Save(false);
      return events;
   }

   // Summary of the FTMO day in progress, with balance as its end balance
   void SummariseDay(DaySummary &out, const double balance) const
   {
      out.valid        = m_state.ftmoDate != 0;
      out.ftmoDate     = m_state.ftmoDate;
      out.startBalance = m_state.startOfDayBalance;
      out.endBalance   = balance;
      out.lowestEquity = m_state.lowestEquity;
      out.entries      = m_state.entriesToday;
      out.killSwitch   = m_state.killSwitchActive;
   }

   // The day that ended at the last RISK_EVENT_NEW_DAY (valid=false before any rollover)
   void LastDaySummary(DaySummary &out) const { out = m_lastDay; }

   //--- Trade bookkeeping
   void OnEntryOpened()
   {
      m_state.entriesToday++;
      Save();
   }

   // profit = closed P&L including commission and swap. A zero result
   // neither extends nor resets the streak.
   void OnPositionClosed(const double profit)
   {
      if(profit < 0.0)
         m_state.losingStreak++;
      else if(profit > 0.0)
         m_state.losingStreak = 0;
      Save();
   }

   //--- Queries
   ENUM_ENTRY_CHECK CheckNewEntry(const int positionsOnSymbol, const int positionsTotal) const
   {
      if(m_state.killSwitchActive)                         return ENTRY_BLOCKED_KILL_SWITCH;
      if(m_state.floorGuardLatched)                        return ENTRY_BLOCKED_FLOOR_GUARD;
      if(m_state.entriesToday >= MAX_ENTRIES_PER_FTMO_DAY) return ENTRY_BLOCKED_DAILY_ENTRIES;
      if(positionsOnSymbol >= MAX_POSITIONS_PER_SYMBOL)    return ENTRY_BLOCKED_SYMBOL_POSITION;
      if(positionsTotal >= MAX_POSITIONS_TOTAL)            return ENTRY_BLOCKED_TOTAL_POSITIONS;
      return ENTRY_ALLOWED;
   }

   double RiskPctForNextTrade(const double equity) const
   {
      return EffectiveRiskPct(m_baseRiskPct, m_state.losingStreak, equity,
                              m_state.highestEodBalance, m_initialBalance);
   }

   double RiskMoney(const double riskPct) const { return PctOfInitial(m_initialBalance, riskPct); }

   // Lot size for a stop of stopPips on this symbol at riskPct of initial balance
   double LotsFor(const string symbol, const double stopPips, const double riskPct) const
   {
      double pip = PipSizeFor((int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), SymbolInfoDouble(symbol, SYMBOL_POINT));
      double pipValue = PipValuePerLot(SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE),
                                       SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE), pip);
      return CalcLots(RiskMoney(riskPct), stopPips, pipValue,
                      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                      SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
   }

   bool   KillSwitchActive() const  { return m_state.killSwitchActive; }
   bool   FloorGuardLatched() const { return m_state.floorGuardLatched; }
   double TrailingFloor() const     { return FtmoTrailingFloor(m_state.highestEodBalance, m_initialBalance); }
   double DailyFloor() const        { return FtmoDailyFloor(m_state.startOfDayBalance, m_initialBalance); }
   void   GetState(RiskState &out) const { out = m_state; }
};

#endif
