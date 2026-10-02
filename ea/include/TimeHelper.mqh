//+------------------------------------------------------------------+
//| TimeHelper.mqh                                                   |
//| Server time -> UTC, London and Prague, plus the FTMO day.        |
//|                                                                  |
//| Server clock (OANDA-Prop Trader, used by FTMO; verified          |
//| 2026-10-02 with tools/ServerTimeProbe.mq5 and FTMO's own notice):|
//| New York wall time + 7 hours. That is GMT+2 while the US is on   |
//| standard time and GMT+3 while the US is on daylight time, so the |
//| server switches on US dates, not EU dates.                       |
//|                                                                  |
//| Everything here is computed from server time only. TimeGMT()     |
//| returns server time in the Strategy Tester, so it is never used. |
//|                                                                  |
//| DST rules (all transitions given in UTC):                        |
//|  US: 2nd Sunday of March 07:00 to 1st Sunday of November 06:00   |
//|      (02:00 local wall time in New York both ways)               |
//|  UK and EU: last Sunday of March 01:00 to last Sunday of October |
//|      01:00                                                       |
//|                                                                  |
//| Tests: tests/TimeHelperTests.mq5, expected values generated from |
//| the IANA tz database by tests/gen_time_cases.py.                 |
//+------------------------------------------------------------------+
#ifndef TIME_HELPER_MQH
#define TIME_HELPER_MQH

#define TH_HOUR 3600
#define TH_DAY  86400

const int SERVER_UTC_OFFSET_US_STANDARD = 2 * TH_HOUR;
const int SERVER_UTC_OFFSET_US_DAYLIGHT = 3 * TH_HOUR;
const int PRAGUE_UTC_OFFSET_STANDARD    = 1 * TH_HOUR;
const int EU_DST_SHIFT                  = 1 * TH_HOUR;   // UK and EU both move one hour

//--- Calendar building blocks -------------------------------------

datetime MakeDate(const int year, const int month, const int day, const int hour = 0)
{
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year;
   d.mon  = month;
   d.day  = day;
   d.hour = hour;
   return StructToTime(d);
}

int YearOf(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year;
}

int DayOfWeek(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.day_of_week;   // 0 = Sunday
}

// n = 1 for the first Sunday, 2 for the second, and so on
datetime NthSundayOfMonth(const int year, const int month, const int n, const int hour)
{
   datetime first = MakeDate(year, month, 1);
   int daysToSunday = (7 - DayOfWeek(first)) % 7;
   return first + (daysToSunday + 7 * (n - 1)) * TH_DAY + hour * TH_HOUR;
}

datetime LastSundayOfMonth(const int year, const int month, const int hour)
{
   datetime firstOfNext = (month == 12) ? MakeDate(year + 1, 1, 1) : MakeDate(year, month + 1, 1);
   datetime lastDay = firstOfNext - TH_DAY;
   return lastDay - DayOfWeek(lastDay) * TH_DAY + hour * TH_HOUR;
}

//--- DST checks, taking a UTC instant --------------------------------

bool IsUsDaylightTime(const datetime utc)
{
   int y = YearOf(utc);
   return utc >= NthSundayOfMonth(y, 3, 2, 7) && utc < NthSundayOfMonth(y, 11, 1, 6);
}

bool IsEuSummerTime(const datetime utc)
{
   int y = YearOf(utc);
   return utc >= LastSundayOfMonth(y, 3, 1) && utc < LastSundayOfMonth(y, 10, 1);
}

//--- Conversions --------------------------------------------------

datetime UtcToServer(const datetime utc)
{
   return utc + (IsUsDaylightTime(utc) ? SERVER_UTC_OFFSET_US_DAYLIGHT : SERVER_UTC_OFFSET_US_STANDARD);
}

// When US clocks fall back, server times 08:00-08:59 on that Sunday occur twice.
// They resolve to the first (daylight) occurrence. The market is closed then.
datetime ServerToUtc(const datetime server)
{
   datetime asDaylight = server - SERVER_UTC_OFFSET_US_DAYLIGHT;
   if(IsUsDaylightTime(asDaylight))
      return asDaylight;
   return server - SERVER_UTC_OFFSET_US_STANDARD;
}

datetime UtcToLondon(const datetime utc)
{
   return utc + (IsEuSummerTime(utc) ? EU_DST_SHIFT : 0);
}

datetime UtcToPrague(const datetime utc)
{
   return utc + PRAGUE_UTC_OFFSET_STANDARD + (IsEuSummerTime(utc) ? EU_DST_SHIFT : 0);
}

// Valid for Prague wall times away from the 02:00-03:00 changeover hour,
// which covers midnight, the only time this is used for.
datetime PragueToUtc(const datetime prague)
{
   datetime asSummer = prague - PRAGUE_UTC_OFFSET_STANDARD - EU_DST_SHIFT;
   if(IsEuSummerTime(asSummer))
      return asSummer;
   return prague - PRAGUE_UTC_OFFSET_STANDARD;
}

datetime ServerToLondon(const datetime server) { return UtcToLondon(ServerToUtc(server)); }
datetime ServerToPrague(const datetime server) { return UtcToPrague(ServerToUtc(server)); }

//--- FTMO day (midnight to midnight, Prague time) -------------------

// Prague calendar date of the FTMO day containing this server time (as 00:00 of that date)
datetime FtmoDate(const datetime server)
{
   datetime prague = ServerToPrague(server);
   return prague - prague % TH_DAY;
}

// Server time at which the FTMO day containing this server time began.
// Usually 01:00 server; 02:00 during the weeks when US and EU DST disagree.
datetime FtmoDayStartServer(const datetime server)
{
   return UtcToServer(PragueToUtc(FtmoDate(server)));
}

// True when the two server times fall in different FTMO days
bool IsNewFtmoDay(const datetime previousServer, const datetime currentServer)
{
   return FtmoDate(previousServer) != FtmoDate(currentServer);
}

//--- London wall-clock fields -------------------------------------------

void ServerToLondonStruct(const datetime server, MqlDateTime &london)
{
   TimeToStruct(ServerToLondon(server), london);
}

int LondonHour(const datetime server)
{
   MqlDateTime d;
   ServerToLondonStruct(server, d);
   return d.hour;
}

int LondonDayOfWeek(const datetime server)
{
   MqlDateTime d;
   ServerToLondonStruct(server, d);
   return d.day_of_week;   // 0 = Sunday
}

// Session window on London wall-clock hours: start inclusive, end exclusive.
// With 7 and 15, H1 bars opening 07:00 to 14:00 London qualify and the 15:00 bar does not
// (SPEC section 5 "between 07:00 and 15:00"; see CHANGELOG 2026-10-02).
bool IsInLondonWindow(const datetime server, const int startHour, const int endHour)
{
   int hour = LondonHour(server);
   return hour >= startHour && hour < endHour;
}

#endif
