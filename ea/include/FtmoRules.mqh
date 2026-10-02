//+------------------------------------------------------------------+
//| FtmoRules.mqh                                                    |
//| FTMO 1-Step account limits (SPEC section 2). The only place      |
//| these numbers live. All percentages are of INITIAL balance.      |
//+------------------------------------------------------------------+
#ifndef FTMO_RULES_MQH
#define FTMO_RULES_MQH

#define FTMO_PROFIT_TARGET_PCT    10.0   // pass at initial balance + 10%
#define FTMO_MAX_DAILY_LOSS_PCT    3.0   // below start-of-day balance, floating P&L counts
#define FTMO_MAX_LOSS_PCT         10.0   // below highest end-of-day balance, trailing
#define FTMO_BEST_DAY_MAX_SHARE    0.50  // best day <= 50% of the sum of positive days

double PctOfInitial(const double initialBalance, const double pct)
{
   return initialBalance * pct / 100.0;
}

double FtmoProfitTargetBalance(const double initialBalance)
{
   return initialBalance + PctOfInitial(initialBalance, FTMO_PROFIT_TARGET_PCT);
}

// Equity at or below this breaches Maximum Daily Loss
double FtmoDailyFloor(const double startOfDayBalance, const double initialBalance)
{
   return startOfDayBalance - PctOfInitial(initialBalance, FTMO_MAX_DAILY_LOSS_PCT);
}

// Equity at or below this breaches Maximum Loss. Trails the highest end-of-day
// balance and stops trailing once it reaches the initial balance.
double FtmoTrailingFloor(const double highestEndOfDayBalance, const double initialBalance)
{
   double trailing = highestEndOfDayBalance - PctOfInitial(initialBalance, FTMO_MAX_LOSS_PCT);
   return MathMin(trailing, initialBalance);
}

// Best day as a share of the total of all positive days (0 when there are none).
// dailyProfits holds each FTMO day's closed P&L.
double BestDayShare(const double &dailyProfits[])
{
   double best = 0.0, positiveTotal = 0.0;
   for(int i = 0; i < ArraySize(dailyProfits); i++)
   {
      if(dailyProfits[i] <= 0.0)
         continue;
      positiveTotal += dailyProfits[i];
      best = MathMax(best, dailyProfits[i]);
   }
   return positiveTotal > 0.0 ? best / positiveTotal : 0.0;
}

bool BestDayRuleMet(const double &dailyProfits[])
{
   return BestDayShare(dailyProfits) <= FTMO_BEST_DAY_MAX_SHARE;
}

#endif
