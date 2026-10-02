//+------------------------------------------------------------------+
//| RiskManagerTests.mq5                                             |
//| Script. Checks FtmoRules.mqh and RiskManager.mqh. Expected       |
//| values are worked by hand from SPEC sections 2 and 6, on a       |
//| 100,000 initial balance. Writes MQL5\Files\RiskManagerTests.txt. |
//| Uses its own TEST_ global variables and deletes them. No orders. |
//+------------------------------------------------------------------+
#property strict

#include "..\ea\include\RiskManager.mqh"

#define INITIAL 100000.0
#define TEST_PREFIX "TEST_RM_"

int g_file   = INVALID_HANDLE;
int g_passed = 0;
int g_failed = 0;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

void CheckNum(const string label, const double actual, const double expected)
{
   if(MathAbs(actual - expected) < 1e-6)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out(StringFormat("FAIL %s: got %.8f, expected %.8f", label, actual, expected));
}

void CheckTrue(const string label, const bool condition)
{
   if(condition)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label);
}

void CheckEntry(const string label, const ENUM_ENTRY_CHECK actual, const ENUM_ENTRY_CHECK expected)
{
   if(actual == expected)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label + ": got '" + EntryCheckText(actual) + "', expected '" + EntryCheckText(expected) + "'");
}

bool Has(const int events, const int flag) { return (events & flag) != 0; }

void TestSizing()
{
   CheckNum("pip size 5 digits", PipSizeFor(5, 0.00001), 0.0001);
   CheckNum("pip size 3 digits", PipSizeFor(3, 0.001), 0.01);
   CheckNum("pip size 4 digits", PipSizeFor(4, 0.0001), 0.0001);
   CheckNum("pip value EURUSD.sim", PipValuePerLot(1.0, 0.00001, 0.0001), 10.0);

   // risk money, stop pips, pip value, min, max, step
   CheckNum("500 at 25 pips",          CalcLots(500, 25, 10, 0.01, 50, 0.01), 2.00);
   CheckNum("500 at 40 pips",          CalcLots(500, 40, 10, 0.01, 50, 0.01), 1.25);
   CheckNum("500 at 30 pips rounds down", CalcLots(500, 30, 10, 0.01, 50, 0.01), 1.66);
   CheckNum("250 at 35 pips rounds down", CalcLots(250, 35, 10, 0.01, 50, 0.01), 0.71);
   CheckNum("exact 1.20 survives float", CalcLots(120, 10, 10, 0.01, 50, 0.01), 1.20);
   CheckNum("exact 0.12 survives float", CalcLots(12, 10, 10, 0.01, 50, 0.01), 0.12);
   CheckNum("below min skips trade",   CalcLots(1, 40, 10, 0.01, 50, 0.01), 0.0);
   CheckNum("capped at max volume",    CalcLots(1e7, 15, 10, 0.01, 50, 0.01), 50.0);
   CheckNum("zero stop is no trade",   CalcLots(500, 0, 10, 0.01, 50, 0.01), 0.0);
   CheckNum("risk money 0.5%",         PctOfInitial(INITIAL, 0.5), 500.0);

   // Live symbol, if this terminal has it
   if(SymbolSelect("EURUSD.sim", true))
   {
      CRiskManager rm;
      rm.Init(TEST_PREFIX, INITIAL, 0.5);
      double lots = rm.LotsFor("EURUSD.sim", 25, 0.5);
      Out(StringFormat("info: LotsFor(EURUSD.sim, 25 pips, 0.5%% of 100k) = %.2f (2.00 if tick value is 1 USD)", lots));
      CheckNum("LotsFor EURUSD.sim 25 pips", lots, 2.00);
   }
}

void TestFtmoRules()
{
   CheckNum("profit target",                 FtmoProfitTargetBalance(INITIAL), 110000);
   CheckNum("daily floor from 101k start",   FtmoDailyFloor(101000, INITIAL), 98000);
   CheckNum("trailing floor at start",       FtmoTrailingFloor(100000, INITIAL), 90000);
   CheckNum("trailing floor after 105k EOD", FtmoTrailingFloor(105000, INITIAL), 95000);
   CheckNum("trailing floor locks at initial", FtmoTrailingFloor(112000, INITIAL), 100000);

   double a[] = {100, -50, 300, 100};
   CheckNum("best day share 300/500", BestDayShare(a), 0.6);
   CheckTrue("best day rule broken at 60%", !BestDayRuleMet(a));
   double b[] = {100, 100, 100, -20};
   CheckTrue("best day rule met at 33%", BestDayRuleMet(b));
   double c[] = {250, 250};
   CheckTrue("best day rule met at exactly 50%", BestDayRuleMet(c));
   double none[];
   CheckNum("best day share with no positive days", BestDayShare(none), 0.0);
}

void TestEffectiveRisk()
{
   // base, streak, equity, highest EOD, initial. Trailing floor 90,000 at highest EOD 100,000.
   CheckNum("normal risk",             EffectiveRiskPct(0.5, 2, 100000, 100000, INITIAL), 0.5);
   CheckNum("streak of 3 brakes",      EffectiveRiskPct(0.5, 3, 100000, 100000, INITIAL), 0.25);
   CheckNum("headroom exactly 3% brakes", EffectiveRiskPct(0.5, 0, 93000, 100000, INITIAL), 0.25);
   CheckNum("headroom just over 3% normal", EffectiveRiskPct(0.5, 0, 93001, 100000, INITIAL), 0.5);
   CheckNum("brake never raises 0.25", EffectiveRiskPct(0.25, 5, 100000, 100000, INITIAL), 0.25);
   CheckNum("brake never raises 0.1",  EffectiveRiskPct(0.1, 5, 100000, 100000, INITIAL), 0.1);
}

void TestDailyFlow()
{
   CRiskManager rm;
   rm.Init(TEST_PREFIX, INITIAL, 0.5);
   rm.DeleteSaved();
   CheckTrue("no saved state after delete", !rm.Load());

   int ev = rm.OnTick(D'2026.07.15 10:00', 100000, 100000);
   CheckTrue("first tick starts a day", Has(ev, RISK_EVENT_NEW_DAY));
   CheckEntry("fresh day allows entry", rm.CheckNewEntry(0, 0), ENTRY_ALLOWED);
   CheckEntry("one per symbol",         rm.CheckNewEntry(1, 1), ENTRY_BLOCKED_SYMBOL_POSITION);
   CheckEntry("two in total",           rm.CheckNewEntry(0, 2), ENTRY_BLOCKED_TOTAL_POSITIONS);

   rm.OnEntryOpened();
   CheckEntry("one entry used",         rm.CheckNewEntry(0, 1), ENTRY_ALLOWED);
   rm.OnEntryOpened();
   CheckEntry("two entries used",       rm.CheckNewEntry(0, 0), ENTRY_BLOCKED_DAILY_ENTRIES);

   // Kill switch at start-of-day balance minus 1.5% = 98,500
   ev = rm.OnTick(D'2026.07.15 12:00', 100000, 98501);
   CheckTrue("98,501 does not trigger kill switch", !Has(ev, RISK_EVENT_KILL_SWITCH));
   ev = rm.OnTick(D'2026.07.15 12:01', 100000, 98500);
   CheckTrue("98,500 triggers kill switch", Has(ev, RISK_EVENT_KILL_SWITCH));
   ev = rm.OnTick(D'2026.07.15 12:02', 98600, 98600);
   CheckTrue("kill switch event fires once", !Has(ev, RISK_EVENT_KILL_SWITCH));
   CheckEntry("kill switch blocks", rm.CheckNewEntry(0, 0), ENTRY_BLOCKED_KILL_SWITCH);

   // FTMO day starts 01:00 server in summer
   ev = rm.OnTick(D'2026.07.16 00:59', 98600, 98600);
   CheckTrue("00:59 server is still the old FTMO day", !Has(ev, RISK_EVENT_NEW_DAY));
   CheckTrue("kill switch still active at 00:59", rm.KillSwitchActive());
   ev = rm.OnTick(D'2026.07.16 01:00', 98600, 98600);
   CheckTrue("01:00 server starts new FTMO day", Has(ev, RISK_EVENT_NEW_DAY));
   CheckTrue("kill switch cleared on new day", !rm.KillSwitchActive());
   CheckEntry("entries reset on new day", rm.CheckNewEntry(0, 0), ENTRY_ALLOWED);
   CheckNum("daily floor from 98,600", rm.DailyFloor(), 95600);
   CheckNum("highest EOD unchanged by a lower close", rm.TrailingFloor(), 90000);

   // Highest end-of-day balance trails up
   rm.OnTick(D'2026.07.17 01:00', 104000, 104000);
   CheckNum("trailing floor after 104k EOD", rm.TrailingFloor(), 94000);

   // Day opens at 95,600: headroom 1,600 is inside the 3% reduce band, outside the 1.5% block band
   rm.OnTick(D'2026.07.20 01:00', 95600, 95600);
   CheckNum("risk reduced near floor", rm.RiskPctForNextTrade(95600), 0.25);
   CheckTrue("floor guard not latched at 1,600 headroom", !rm.FloorGuardLatched());
   ev = rm.OnTick(D'2026.07.20 10:00', 95600, 95500);
   CheckTrue("floor guard fires at 1,500 headroom", Has(ev, RISK_EVENT_FLOOR_GUARD));
   CheckTrue("kill switch not hit (needs 94,100)", !Has(ev, RISK_EVENT_KILL_SWITCH));
   CheckEntry("floor guard blocks", rm.CheckNewEntry(0, 0), ENTRY_BLOCKED_FLOOR_GUARD);
   ev = rm.OnTick(D'2026.07.21 01:00', 96000, 96000);
   CheckTrue("floor guard survives a new day", rm.FloorGuardLatched());
   CheckTrue("floor guard event fires once", !Has(ev, RISK_EVENT_FLOOR_GUARD));

   // Restart: reload into a new instance
   RiskState before, after;
   rm.GetState(before);
   CRiskManager rm2;
   rm2.Init(TEST_PREFIX, INITIAL, 0.5);
   CheckTrue("saved state loads", rm2.Load());
   rm2.GetState(after);
   CheckTrue("reload ftmoDate",   before.ftmoDate == after.ftmoDate);
   CheckNum("reload start balance", after.startOfDayBalance, before.startOfDayBalance);
   CheckNum("reload highest EOD",   after.highestEodBalance, before.highestEodBalance);
   CheckTrue("reload streak",     before.losingStreak == after.losingStreak);
   CheckTrue("reload entries",    before.entriesToday == after.entriesToday);
   CheckTrue("reload kill switch", before.killSwitchActive == after.killSwitchActive);
   CheckTrue("reload floor guard", after.floorGuardLatched);

   // Manual review clears the latch; it re-latches only if still inside the band
   rm2.ClearFloorGuardAfterReview();
   ev = rm2.OnTick(D'2026.07.21 10:00', 96000, 95550);
   CheckTrue("after review, 1,550 headroom stays clear", !rm2.FloorGuardLatched());
   ev = rm2.OnTick(D'2026.07.21 10:01', 96000, 95400);
   CheckTrue("after review, re-latches at 1,400 headroom", Has(ev, RISK_EVENT_FLOOR_GUARD));

   rm.DeleteSaved();
}

void TestStreak()
{
   CRiskManager rm;
   rm.Init(TEST_PREFIX, INITIAL, 0.5);
   rm.DeleteSaved();
   rm.OnTick(D'2026.07.15 10:00', 100000, 100000);
   rm.OnPositionClosed(-10);
   rm.OnPositionClosed(-10);
   CheckNum("two losses, normal risk", rm.RiskPctForNextTrade(100000), 0.5);
   rm.OnPositionClosed(-10);
   CheckNum("three losses, reduced risk", rm.RiskPctForNextTrade(100000), 0.25);
   rm.OnPositionClosed(0);
   CheckNum("zero result keeps the brake", rm.RiskPctForNextTrade(100000), 0.25);
   rm.OnPositionClosed(5);
   CheckNum("a win releases the brake", rm.RiskPctForNextTrade(100000), 0.5);
   rm.DeleteSaved();
}

void TestMismatchDayBoundary()
{
   CRiskManager rm;
   rm.Init(TEST_PREFIX, INITIAL, 0.5);
   rm.DeleteSaved();
   rm.OnTick(D'2025.10.27 12:00', 100000, 100000);
   int ev = rm.OnTick(D'2025.10.28 01:30', 100000, 100000);
   CheckTrue("mismatch week: 01:30 server is still the old day", !Has(ev, RISK_EVENT_NEW_DAY));
   ev = rm.OnTick(D'2025.10.28 02:00', 100000, 100000);
   CheckTrue("mismatch week: 02:00 server starts the new day", Has(ev, RISK_EVENT_NEW_DAY));
   rm.DeleteSaved();
}

void OnStart()
{
   g_file = FileOpen("RiskManagerTests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("RiskManager tests, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   TestSizing();
   TestFtmoRules();
   TestEffectiveRisk();
   TestDailyFlow();
   TestStreak();
   TestMismatchDayBoundary();
   Out(StringFormat("RESULT: %d passed, %d failed", g_passed, g_failed));
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
