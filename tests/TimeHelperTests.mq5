//+------------------------------------------------------------------+
//| TimeHelperTests.mq5                                              |
//| Script. Checks TimeHelper.mqh against expected values generated  |
//| from the IANA tz database (tests/gen_time_cases.py).             |
//| Writes MQL5\Files\TimeHelperTests.txt. Places no orders.         |
//+------------------------------------------------------------------+
#property strict

#include "..\ea\include\TimeHelper.mqh"

struct TimeCase
{
   datetime server;
   datetime utc;
   datetime london;
   datetime prague;
   datetime ftmoDayStart;
   string   note;
};

struct DstYear
{
   int      year;
   datetime usStart;
   datetime usEnd;
   datetime euStart;
   datetime euEnd;
};

struct SessionCase
{
   datetime server;
   int      londonHour;
   bool     inside;
};

#include "TimeHelperCases.mqh"

int g_file   = INVALID_HANDLE;
int g_passed = 0;
int g_failed = 0;

void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

string Fmt(const datetime t) { return TimeToString(t, TIME_DATE | TIME_MINUTES); }

void CheckTime(const string label, const datetime actual, const datetime expected)
{
   if(actual == expected)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out("FAIL " + label + ": got " + Fmt(actual) + ", expected " + Fmt(expected));
}

void CheckInt(const string label, const long actual, const long expected)
{
   if(actual == expected)
   {
      g_passed++;
      return;
   }
   g_failed++;
   Out(StringFormat("FAIL %s: got %I64d, expected %I64d", label, actual, expected));
}

void CheckTrue(const string label, const bool condition)
{
   CheckInt(label, condition ? 1 : 0, 1);
}

void RunConversionCases()
{
   TimeCase c[];
   LoadTimeCases(c);
   for(int i = 0; i < ArraySize(c); i++)
   {
      string id = "[" + Fmt(c[i].server) + " " + c[i].note + "] ";
      MqlDateTime london;
      TimeToStruct(c[i].london, london);

      CheckTime(id + "ServerToUtc",        ServerToUtc(c[i].server),        c[i].utc);
      CheckTime(id + "UtcToServer",        UtcToServer(c[i].utc),           c[i].server);
      CheckTime(id + "ServerToLondon",     ServerToLondon(c[i].server),     c[i].london);
      CheckTime(id + "ServerToPrague",     ServerToPrague(c[i].server),     c[i].prague);
      CheckTime(id + "FtmoDayStartServer", FtmoDayStartServer(c[i].server), c[i].ftmoDayStart);
      CheckTime(id + "FtmoDate",           FtmoDate(c[i].server),           c[i].prague - c[i].prague % TH_DAY);
      CheckInt(id + "LondonHour",          LondonHour(c[i].server),         london.hour);
      CheckInt(id + "LondonDayOfWeek",     LondonDayOfWeek(c[i].server),    london.day_of_week);

      // A day boundary must sit exactly at the FTMO day start
      datetime start = c[i].ftmoDayStart;
      CheckTrue(id + "new FTMO day at start",       IsNewFtmoDay(start - 60, start));
      CheckTrue(id + "same FTMO day after start",  !IsNewFtmoDay(start, c[i].server));
   }
}

void RunDstYears()
{
   DstYear d[];
   LoadDstYears(d);
   for(int i = 0; i < ArraySize(d); i++)
   {
      string id = "[" + IntegerToString(d[i].year) + "] ";
      CheckTime(id + "US start", NthSundayOfMonth(d[i].year, 3, 2, 7), d[i].usStart);
      CheckTime(id + "US end",   NthSundayOfMonth(d[i].year, 11, 1, 6), d[i].usEnd);
      CheckTime(id + "EU start", LastSundayOfMonth(d[i].year, 3, 1), d[i].euStart);
      CheckTime(id + "EU end",   LastSundayOfMonth(d[i].year, 10, 1), d[i].euEnd);

      // Both sides of each change
      CheckTrue(id + "US std before start",  !IsUsDaylightTime(d[i].usStart - 60));
      CheckTrue(id + "US dst at start",       IsUsDaylightTime(d[i].usStart));
      CheckTrue(id + "US dst before end",     IsUsDaylightTime(d[i].usEnd - 60));
      CheckTrue(id + "US std at end",        !IsUsDaylightTime(d[i].usEnd));
      CheckTrue(id + "EU std before start",  !IsEuSummerTime(d[i].euStart - 60));
      CheckTrue(id + "EU summer at start",    IsEuSummerTime(d[i].euStart));
      CheckTrue(id + "EU summer before end",  IsEuSummerTime(d[i].euEnd - 60));
      CheckTrue(id + "EU std at end",        !IsEuSummerTime(d[i].euEnd));
   }
}

void RunSessionCases()
{
   SessionCase s[];
   LoadSessionCases(s);
   for(int i = 0; i < ArraySize(s); i++)
   {
      string id = "[session " + Fmt(s[i].server) + "] ";
      CheckInt(id + "LondonHour", LondonHour(s[i].server), s[i].londonHour);
      CheckInt(id + "IsInLondonWindow",
               IsInLondonWindow(s[i].server, SESSION_START_HOUR, SESSION_END_HOUR) ? 1 : 0,
               s[i].inside ? 1 : 0);
   }
}

// Every hour across the backtest span: server -> UTC -> server must round-trip,
// except inside the repeated hour when US clocks fall back.
void RunRoundTripSweep()
{
   datetime from = MakeDate(2014, 1, 1);
   datetime to   = MakeDate(2033, 1, 1);
   int bad = 0;
   for(datetime utc = from; utc < to; utc += TH_HOUR)
   {
      if(ServerToUtc(UtcToServer(utc)) == utc)
         continue;
      // Allowed: the second pass through 08:00-08:59 server on the US fall-back Sunday
      datetime usEnd = NthSundayOfMonth(YearOf(utc), 11, 1, 6);
      if(utc >= usEnd && utc < usEnd + TH_HOUR)
         continue;
      if(bad < 10)
         Out("FAIL round trip at UTC " + Fmt(utc));
      bad++;
   }
   CheckInt("round-trip sweep failures 2014-2032", bad, 0);
}

void OnStart()
{
   g_file = FileOpen("TimeHelperTests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("TimeHelper tests, run at server time " + TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   RunConversionCases();
   RunDstYears();
   RunSessionCases();
   RunRoundTripSweep();
   Out(StringFormat("RESULT: %d passed, %d failed", g_passed, g_failed));
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
