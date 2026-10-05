//+------------------------------------------------------------------+
//| LoggerTests.mq5                                                  |
//| Script. Checks Logger.mqh CSV output and its saved markers.      |
//| Reading trades back from account history needs real trades, so   |
//| that part is checked in the first Strategy Tester run instead.   |
//| Writes Common\Files\LoggerTest_*.csv (deleted after) and         |
//| MQL5\Files\LoggerTests.txt. Uses TEST_LG_ globals. No orders.    |
//+------------------------------------------------------------------+
#property strict

#include "..\ea\include\Logger.mqh"

const string TEST_PREFIX = "TEST_LG_";
#define TEST_BASE   "LoggerTest"

int g_file   = INVALID_HANDLE;
int g_passed = 0;
int g_failed = 0;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

void CheckStr(const string label, const string actual, const string expected)
{
   if(actual == expected)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label + "\r\n  got:      " + actual + "\r\n  expected: " + expected);
}

void CheckTrue(const string label, const bool condition)
{
   CheckStr(label, condition ? "true" : "false", "true");
}

// Reads a common-folder text file into lines
int ReadLines(const string name, string &lines[])
{
   ArrayResize(lines, 0);
   int h = FileOpen(name, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return 0;
   while(!FileIsEnding(h))
   {
      string s = FileReadString(h);
      if(s == "")
         continue;
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = s;
   }
   FileClose(h);
   return ArraySize(lines);
}

void TestTradeLog(CLogger &log)
{
   TradeRecord r;
   ZeroMemory(r);
   r.positionId = 123456;
   r.entryTime  = D'2026.07.15 09:00:01';
   r.symbol     = "EURUSD.sim";
   r.isLong     = true;
   r.entryPrice = 1.09963;
   r.stop       = 1.09690;
   r.target     = 1.10363;
   r.lots       = 1.83;
   r.riskPct    = 0.5;
   r.spreadPips = 0.3;
   r.exitTime   = D'2026.07.15 13:42:10';
   r.exitPrice  = 1.10363;
   r.exitReason = EXIT_TP;
   r.pips       = 40.0;
   r.pnl        = 725.32;
   CheckTrue("trade row written", log.LogTrade(r));

   r.positionId = 123457;
   r.isLong     = false;
   r.riskPct    = -1;    // not recorded: blank, not -1
   r.spreadPips = -1;
   r.exitReason = EXIT_TIME_STOP;
   r.pips       = -12.4;
   r.pnl        = -230.5;
   CheckTrue("second trade row written", log.LogTrade(r));

   string lines[];
   int n = ReadLines(log.TradeFile(), lines);
   CheckTrue("trade log has header and 2 rows", n == 3);
   if(n < 3)
      return;
   CheckStr("trade log header", lines[0], TRADE_LOG_HEADER);
   CheckStr("trade row 1", lines[1],
            "123456,2026.07.15 09:00:01,EURUSD.sim,long,1.09963,1.09690,1.10363,1.83,0.50,0.3,2026.07.15 13:42:10,1.10363,TP,40.0,725.32");
   CheckStr("trade row 2 blanks unknown risk and spread", lines[2],
            "123457,2026.07.15 09:00:01,EURUSD.sim,short,1.09963,1.09690,1.10363,1.83,,,2026.07.15 13:42:10,1.10363,time stop,-12.4,-230.50");
}

void TestDailyLog(CLogger &log)
{
   DaySummary d;
   ZeroMemory(d);
   CheckTrue("invalid day not written", !log.LogDay(d));
   d.valid        = true;
   d.ftmoDate     = D'2026.07.15';
   d.startBalance = 100000;
   d.endBalance   = 98600;
   d.lowestEquity = 98500;
   d.entries      = 2;
   d.killSwitch   = true;
   CheckTrue("day row written", log.LogDay(d));

   string lines[];
   int n = ReadLines(log.DailyFile(), lines);
   CheckTrue("daily log has header and 1 row", n == 2);
   if(n < 2)
      return;
   CheckStr("daily log header", lines[0], DAILY_LOG_HEADER);
   CheckStr("daily row", lines[1], "2026.07.15,100000.00,98600.00,98500.00,2,yes");
}

void TestMarkersAndReasons(CLogger &log)
{
   CheckStr("exit reason TP",           ExitReasonText(EXIT_TP), "TP");
   CheckStr("exit reason SL",           ExitReasonText(EXIT_SL), "SL");
   CheckStr("exit reason time stop",    ExitReasonText(EXIT_TIME_STOP), "time stop");
   CheckStr("exit reason Friday close", ExitReasonText(EXIT_FRIDAY_CLOSE), "Friday close");
   CheckStr("exit reason kill switch",  ExitReasonText(EXIT_KILL_SWITCH), "kill switch");

   log.SaveEntryMeta(42, 0.25, 1.4);
   log.SetCloseReason(42, EXIT_KILL_SWITCH);
   CheckTrue("entry risk saved",   GlobalVariableGet(TEST_PREFIX + "p42_risk") == 0.25);
   CheckTrue("entry spread saved", GlobalVariableGet(TEST_PREFIX + "p42_spread") == 1.4);
   CheckTrue("close reason saved", (int)GlobalVariableGet(TEST_PREFIX + "p42_why") == EXIT_KILL_SWITCH);
   log.ForgetPosition(42);
   CheckTrue("position globals removed", !GlobalVariableCheck(TEST_PREFIX + "p42_risk") &&
                                         !GlobalVariableCheck(TEST_PREFIX + "p42_spread") &&
                                         !GlobalVariableCheck(TEST_PREFIX + "p42_why"));

   // The processed-deal marker only moves on MarkProcessed
   ulong ids[];
   log.NewClosedPositions(ids);
   CheckTrue("no closed positions for a test magic", ArraySize(ids) == 0);
   CheckTrue("marker not written before MarkProcessed", !GlobalVariableCheck(TEST_PREFIX + "lastDeal"));
   log.MarkProcessed();
   CheckTrue("marker written by MarkProcessed", GlobalVariableCheck(TEST_PREFIX + "lastDeal"));
}

void OnStart()
{
   g_file = FileOpen("LoggerTests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("Logger tests, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   GlobalVariablesDeleteAll(TEST_PREFIX);

   CLogger log;
   // Magic 1 is never used for trading, so the history scan must find nothing
   log.Init(TEST_PREFIX, 1, TEST_BASE, true);
   TestTradeLog(log);
   TestDailyLog(log);
   TestMarkersAndReasons(log);

   FileDelete(log.TradeFile(), FILE_COMMON);
   FileDelete(log.DailyFile(), FILE_COMMON);
   GlobalVariablesDeleteAll(TEST_PREFIX);
   Out(StringFormat("RESULT: %d passed, %d failed", g_passed, g_failed));
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
