//+------------------------------------------------------------------+
//| MT5 Expert Advisor: London & New York Session Breakout EA       |
//| - Opens a single buy or sell per session based on previous bar  |
//| - Risk per trade (percent of balance)                           |
//| - Separate magic numbers for buy & sell                         |
//| - SL = previous candle range; TP = 2 x previous candle range    |
//| - Trailing stop in points                                        |
//|                                                                |
// Place this file in: MQL5/Experts and compile in MetaEditor       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input double   InpRiskPercent      = 1.0;          // Risk percent per trade (e.g. 1 = 1%)
input int      InpLondonStartHour  = 5;            // London session start hour (server time)
input int      InpLondonEndHour    = 16;           // London session end hour (server time)
input int      InpNYStartHour      = 12;           // New York session start hour (server time)
input int      InpNYEndHour        = 21;           // New York session end hour (server time)
input ulong    InpBuyMagic         = 123456;       // Magic number for buy orders
input ulong    InpSellMagic        = 654321;       // Magic number for sell orders
input int      InpTrailingPoints   = 100;          // Trailing stop in points
input int      InpMinDistanceToSL  = 10;           // Minimum distance to SL in points to allow trade
input string   InpComment          = "HOLO";

CTrade         trade;
datetime       lastBarTime = 0;
int            lastSessionID = 0; // 0 none, 1 London, 2 NY
bool           boughtThisSession = false;
bool           soldThisSession = false;

//+------------------------------------------------------------------+
int OnInit() {
   lastBarTime = 0;
   lastSessionID = GetCurrentSessionID();
   ResetSessionFlags(lastSessionID);
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick() {
   // act only on new closed bar
   datetime curBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (curBarTime == lastBarTime) // not new bar
   {
      // still handle trailing on ticks
      DoTrailing();
      return;
   }

   // we have a new bar
   // update
   lastBarTime = curBarTime;

   int session = GetCurrentSessionID();
   if (session != lastSessionID) {
      // session changed - reset flags
      lastSessionID = session;
      ResetSessionFlags(session);
   }

   // If not in London or NY sessions do nothing
   if (session == 0) return;
   
   double prevRange = 0;
   
   if(SignalBuy()) {
      prevRange = MathAbs(iClose(_Symbol, PERIOD_CURRENT, 1) - GetTodaysLowestH1());
      if (prevRange <= 0) return;
      if (!boughtThisSession) {
         TryOpenBuy(prevRange);
      }
   }
   
   if(SignalSell()) {
      prevRange = MathAbs(GetTodaysHighestH1() - iClose(_Symbol, PERIOD_CURRENT, 1));
      if (prevRange <= 0) return;
      if (!soldThisSession) {
         TryOpenSell(prevRange);
      }
   }

   // Finally handle trailing after potential trade
   DoTrailing();
}

//+------------------------------------------------------------------+
int GetCurrentSessionID() {
   // returns 0 none, 1 London, 2 NewYork based on server time hours
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hr = dt.hour;

   // Note: input hours are server time. Adjust if you want broker-local mapping.
   if (InpLondonStartHour <= InpLondonEndHour) {
      if (hr >= InpLondonStartHour && hr < InpLondonEndHour) return 1;
   } else // over midnight
   {
      if (hr >= InpLondonStartHour || hr < InpLondonEndHour) return 1;
   }

   if (InpNYStartHour <= InpNYEndHour) {
      if (hr >= InpNYStartHour && hr < InpNYEndHour) return 2;
   } else {
      if (hr >= InpNYStartHour || hr < InpNYEndHour) return 2;
   }

   return 0;
}

//+------------------------------------------------------------------+
void ResetSessionFlags(int session) {
   // when session changes allow new trades for both sides
   boughtThisSession = false;
   soldThisSession = false;
}

//+------------------------------------------------------------------+
void TryOpenBuy(double prevRange) {
   string sym = _Symbol;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double digits = (double) SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // compute SL and TP as distances based on previous candle range
   double slPrice = ask - prevRange; // SL distance = prevRange below entry
   double tpPrice = ask + prevRange * 2.0;

   double slDistance = ask - slPrice; // positive
   double slDistancePoints = slDistance / point;
   if (slDistancePoints < InpMinDistanceToSL) return; // too small

   // calculate lot size based on risk
   double lot = CalculateLotByRisk(prevRange);
   if (lot <= 0) return;

   // normalize lot to allowed volume step
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if (lot < minLot) return;
   if (lot > maxLot) lot = maxLot;
   // round down to nearest step
   lot = MathFloor(lot / lotStep + 0.0000001) * lotStep;

   trade.SetExpertMagicNumber(InpBuyMagic);
   bool ok = trade.Buy(lot, sym, ask, slPrice, tpPrice, InpComment);
   if (ok) {
      boughtThisSession = true;
   } else {
      // failed - you may check GetLastError() for info
   }
}

//+------------------------------------------------------------------+
void TryOpenSell(double prevRange) {
   string sym = _Symbol;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   double slPrice = bid + prevRange; // SL distance = prevRange above entry
   double tpPrice = bid - prevRange * 2.0;

   double slDistance = slPrice - bid; // positive
   double slDistancePoints = slDistance / point;
   if (slDistancePoints < InpMinDistanceToSL) return;

   double lot = CalculateLotByRisk(prevRange);
   if (lot <= 0) return;

   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if (lot < minLot) return;
   if (lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep + 0.0000001) * lotStep;

   trade.SetExpertMagicNumber(InpSellMagic);
   bool ok = trade.Sell(lot, sym, bid, slPrice, tpPrice, InpComment);
   if (ok) {
      soldThisSession = true;
   }
}

//+------------------------------------------------------------------+
double CalculateLotByRisk(double prevRange) {
   // prevRange is price difference (price units). We compute value lost per lot
   string sym = _Symbol;
   double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);

   if (tick_size <= 0 || tick_value <= 0) return (0);

   // value per 1.0 price movement per lot
   double valuePerPricePerLot = tick_value / tick_size;
   double lossPerLot = valuePerPricePerLot * prevRange;
   if (lossPerLot <= 0) return (0);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);

   double rawLot = riskAmount / lossPerLot;
   return rawLot;
}

//+------------------------------------------------------------------+
void DoTrailing() {
   // iterate through open positions for this symbol
   ulong tickets[];
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; --i) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (!PositionSelectByTicket(ticket)) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      if (posSym != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      double volume = PositionGetDouble(POSITION_VOLUME);
      int type = (int) PositionGetInteger(POSITION_TYPE);
      double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // only handle our EA orders by magic numbers
      if (magic != (long) InpBuyMagic && magic != (long) InpSellMagic) continue;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double newSL = 0.0;

      if (type == POSITION_TYPE_BUY) {
         double desiredSL = currentPrice - InpTrailingPoints * point; // price
         // only move SL up (toward profit) and not above open price
         if (desiredSL > sl && desiredSL > price_open) {
            newSL = desiredSL;
         }
      } else if (type == POSITION_TYPE_SELL) {
         double desiredSL = currentPrice + InpTrailingPoints * point;
         if (desiredSL < sl || sl == 0.0) // for sells sl is above - move down (toward profit) if lower
         {
            // make sure we don't move SL below open price (for sell open price is higher than current)
            if (desiredSL < PositionGetDouble(POSITION_PRICE_OPEN)) newSL = desiredSL;
         }
      }

      if (newSL != 0.0) {
         // modify position
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol = _Symbol;
         request.sl = NormalizeDouble(newSL, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         request.tp = PositionGetDouble(POSITION_TP);
         request.type_filling = ORDER_FILLING_FOK;
         request.type = ORDER_TYPE_BUY; // not used for SLTP but keep valid

         if (!SendOrderRequest(request, result)) {
            // failed to modify, ignore
         } else {
            // success
         }
      }
   }
}

//+------------------------------------------------------------------+
// Helper: wrapper for OrderSend (SL/TP updates)
bool SendOrderRequest(const MqlTradeRequest & request, MqlTradeResult & result) {
   if (!::OrderSend(request, result)) // use built-in OrderSend with scope operator
   {
      Print("OrderSend failed. Error: ", _LastError);
      return (false);
   }
   return (true);
}

//+------------------------------------------------------------------+
// On deinit
void OnDeinit(const int reason) {}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// Functions
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get today's highest HIGH on H1 timeframe                         |
//+------------------------------------------------------------------+
double GetTodaysHighestH1()
  {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   // Calculate start of today (server time)
   datetime startToday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec);

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if(totalBars <= 0) return 0.0;

   double highestHigh = -DBL_MAX;

   for(int i = 0; i < totalBars; i++)
     {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if(barTime < startToday) break; // older than today → stop loop
      double highPrice = iHigh(_Symbol, PERIOD_H1, i);
      if(highPrice > highestHigh) highestHigh = highPrice;
     }

   if(highestHigh == -DBL_MAX) return 0.0;
   return highestHigh;
  }

//+------------------------------------------------------------------+
//| Get today's lowest LOW on H1 timeframe                           |
//+------------------------------------------------------------------+
double GetTodaysLowestH1()
  {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   datetime startToday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec);

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if(totalBars <= 0) return 0.0;

   double lowestLow = DBL_MAX;

   for(int i = 0; i < totalBars; i++)
     {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if(barTime < startToday) break; // older than today → stop loop
      double lowPrice = iLow(_Symbol, PERIOD_H1, i);
      if(lowPrice < lowestLow) lowestLow = lowPrice;
     }

   if(lowestLow == DBL_MAX) return 0.0;
   return lowestLow;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get today's highest Open on H1 timeframe                         |
//+------------------------------------------------------------------+
double GetTodaysHighestOpenH1() {
   datetime t0 = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t0, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   int i = 0;
   double TodayHighest = 0;
   while (true) {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      if (t == 0 || t < dayStart) break;
      double open = iOpen(_Symbol, PERIOD_H1, i);
      if (open > TodayHighest || TodayHighest == 0) TodayHighest = open;
      i++;
      if (i > 10000) break;
   }
   return TodayHighest;
}

//+------------------------------------------------------------------+
//| Get today's lowest Open on H1 timeframe                          |
//+------------------------------------------------------------------+
double GetTodaysLowestOpenH1() {
   datetime t0 = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t0, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   int i = 0;
   double TodayLowest = 0;
   while (true) {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      if (t == 0 || t < dayStart) break;
      double open = iOpen(_Symbol, PERIOD_H1, i);
      if (open < TodayLowest || TodayLowest == 0) TodayLowest = open;
      i++;
      if (i > 10000) break;
   }
   return TodayLowest;
}

//+------------------------------------------------------------------+
//| Get yesterday's highest OPEN on H1                              |
//+------------------------------------------------------------------+
double GetYesterdayHighestOpenH1() {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   // get start and end of yesterday
   datetime startYesterday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec) - 86400;
   datetime endYesterday = startYesterday + 86400;

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if (totalBars <= 0) return 0.0;

   double highestOpen = -DBL_MAX;

   for (int i = 0; i < totalBars; i++) {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if (barTime < startYesterday) break; // older than yesterday
      if (barTime >= startYesterday && barTime < endYesterday) {
         double openPrice = iOpen(_Symbol, PERIOD_H1, i);
         if (openPrice > highestOpen) highestOpen = openPrice;
      }
   }

   if (highestOpen == -DBL_MAX) return 0.0;
   return highestOpen;
}

//+------------------------------------------------------------------+
//| Get yesterday's lowest OPEN on H1                               |
//+------------------------------------------------------------------+
double GetYesterdayLowestOpenH1() {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   // get start and end of yesterday
   datetime startYesterday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec) - 86400;
   datetime endYesterday = startYesterday + 86400;

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if (totalBars <= 0) return 0.0;

   double lowestOpen = DBL_MAX;

   for (int i = 0; i < totalBars; i++) {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if (barTime < startYesterday) break; // older than yesterday
      if (barTime >= startYesterday && barTime < endYesterday) {
         double openPrice = iOpen(_Symbol, PERIOD_H1, i);
         if (openPrice < lowestOpen) lowestOpen = openPrice;
      }
   }

   if (lowestOpen == DBL_MAX) return 0.0;
   return lowestOpen;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get yesterday's highest HIGH on H1 timeframe                     |
//+------------------------------------------------------------------+
double GetYesterdayHighestH1()
  {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);

   // Calculate start and end of yesterday (server time)
   datetime startYesterday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec) - 86400;
   datetime endYesterday   = startYesterday + 86400;

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if(totalBars <= 0) return 0.0;

   double highestHigh = -DBL_MAX;

   for(int i = 0; i < totalBars; i++)
     {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if(barTime < startYesterday) break; // older than yesterday → stop loop
      if(barTime >= startYesterday && barTime < endYesterday)
        {
         double highPrice = iHigh(_Symbol, PERIOD_H1, i);
         if(highPrice > highestHigh) highestHigh = highPrice;
        }
     }

   if(highestHigh == -DBL_MAX) return 0.0;
   return highestHigh;
  }

//+------------------------------------------------------------------+
//| Get yesterday's lowest LOW on H1 timeframe                       |
//+------------------------------------------------------------------+
double GetYesterdayLowestH1()
  {
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);

   datetime startYesterday = StructToTime(dtNow) - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec) - 86400;
   datetime endYesterday   = startYesterday + 86400;

   int totalBars = iBars(_Symbol, PERIOD_H1);
   if(totalBars <= 0) return 0.0;

   double lowestLow = DBL_MAX;

   for(int i = 0; i < totalBars; i++)
     {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if(barTime < startYesterday) break; // older than yesterday → stop loop
      if(barTime >= startYesterday && barTime < endYesterday)
        {
         double lowPrice = iLow(_Symbol, PERIOD_H1, i);
         if(lowPrice < lowestLow) lowestLow = lowPrice;
        }
     }

   if(lowestLow == DBL_MAX) return 0.0;
   return lowestLow;
  }
//+------------------------------------------------------------------+


bool SignalSell() {
   
   double CandleClose1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double CandleClose2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   double TodayHighestOpen = GetTodaysHighestOpenH1();
   double YesterdayHighest = GetYesterdayHighestH1();
   
   if((CandleClose2 > TodayHighestOpen) && (CandleClose1 <= TodayHighestOpen) && (CandleClose2 > CandleClose1) && (YesterdayHighest > TodayHighestOpen)) {
   //if((CandleClose2 > TodayHighestOpen) && (CandleClose1 <= TodayHighestOpen) && (CandleClose2 > CandleClose1)) {
      return true;
   }
   
   return false;
      
}

bool SignalBuy() {
   
   double CandleClose1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double CandleClose2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   double TodayLowestOpen = GetTodaysLowestOpenH1();
   double YesterdayLowest = GetYesterdayLowestH1();
   
   if((CandleClose2 < TodayLowestOpen) && (CandleClose1 >= TodayLowestOpen) && (CandleClose2 < CandleClose1) && (YesterdayLowest < TodayLowestOpen)) {
   //if((CandleClose2 < TodayLowestOpen) && (CandleClose1 >= TodayLowestOpen) && (CandleClose2 < CandleClose1)) {
      return true;
   }
   
   return false;
      
}