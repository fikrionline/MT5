//+------------------------------------------------------------------+
//| GoldEMA_Rebuild_v2.mq5                                           |
//| Reconstructed EMA+VWAP EA with session filters, 1 trade/session, |
//| risk-based sizing (1% default) and VWAP charting & logging.      |
//| Save as GoldEMA_Rebuild_v2.mq5 and compile in MetaEditor (MT5).  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input ENUM_TIMEFRAMES High_Timeframe         = PERIOD_H1;
input int    High_EMA_Fast_Period            = 20;
input int    High_EMA_Slow_Period            = 50;
input ENUM_APPLIED_PRICE High_EMA_Applied_Price = PRICE_CLOSE;

input ENUM_TIMEFRAMES Low_Timeframe          = PERIOD_M5;
input int    Low_EMA_Fast_Period             = 9;
input int    Low_EMA_Slow_Period             = 20;
input ENUM_APPLIED_PRICE Low_EMA_Applied_Price  = PRICE_CLOSE;

input bool   Use_VWAP_Filter                 = true;
input bool   Use_ADX_Filter                  = true;
input int    ADX_Period                      = 14;
input int    ADX_Min_Threshold               = 11;
input int    ADX_Max_Threshold               = 53;

input bool   Use_News_Filter                 = false;    // News filter stub (not implemented)
input int    News_Buffer_Minutes             = 30;
input string News_Currency                   = "USD";

input double Fixed_Lot                       = 0.10;     // fallback lot
input double Risk_Percent                    = 1.0;      // percent of equity per trade (default 1%)
input double TakeProfit_Points               = 1000.0;
input double StopLoss_Points                 = 500.0;    // used for risk calc; if 0 => uses Fixed_Lot

// Session times (server time)
input int    London_Start_Hour               = 7;   // 07:00
input int    London_End_Hour                 = 16;  // 16:00
input int    NewYork_Start_Hour              = 13;  // 13:00
input int    NewYork_End_Hour                = 22;  // 22:00

input ulong  Magic_Number                    = 12345;
input bool   Draw_VWAP_On_Chart              = true;
CTrade trade;

//--- object names
string VWAP_HLINE_NAME() {
   return StringFormat("VWAP_HLINE_%d", (int) Magic_Number);
}

//+------------------------------------------------------------------+
//| NormalizeLot(lots)             |
//+------------------------------------------------------------------+
double NormalizeLot(double lots) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if (step <= 0) step = 0.01;
   if (minlot <= 0) minlot = 0.01;
   if (maxlot <= 0) maxlot = 100.0;

   lots = MathMax(minlot, MathMin(maxlot, lots));
   lots = MathFloor(lots / step) * step;
   return lots;
}

//+------------------------------------------------------------------+
//| Utility: Create and release indicator handles safely             |
//+------------------------------------------------------------------+
double GetEMA(string symbol, ENUM_TIMEFRAMES timeframe, int period, ENUM_APPLIED_PRICE applied_price, int shift) {
   int handle = iMA(symbol, timeframe, period, 0, MODE_EMA, applied_price);
   if (handle == INVALID_HANDLE) {
      PrintFormat("GetEMA: iMA handle failed: Err=%d", GetLastError());
      return 0.0;
   }
   double buf[];
   int copied = CopyBuffer(handle, 0, shift, 1, buf);
   IndicatorRelease(handle);
   if (copied != 1) {
      PrintFormat("GetEMA: CopyBuffer failed/cnt=%d Err=%d", copied, GetLastError());
      return 0.0;
   }
   return buf[0];
}

double GetADXValue(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
   int handle = iADX(symbol, timeframe, period);
   if (handle == INVALID_HANDLE) {
      PrintFormat("GetADXValue: iADX handle failed: Err=%d", GetLastError());
      return 0.0;
   }
   double buf[];
   int copied = CopyBuffer(handle, 0, shift, 1, buf);
   IndicatorRelease(handle);
   if (copied != 1) {
      PrintFormat("GetADXValue: CopyBuffer failed/cnt=%d Err=%d", copied, GetLastError());
      return 0.0;
   }
   return buf[0];
}

//+------------------------------------------------------------------+
//| Daily VWAP using tick volume (robust)                            |
//+------------------------------------------------------------------+
double GetDailyVWAP(string symbol, ENUM_TIMEFRAMES timeframe) {
   datetime dayStart = iTime(symbol, PERIOD_D1, 0);
   if (dayStart == 0) {
      Print("GetDailyVWAP: dayStart retrieval failed");
      return 0.0;
   }

   int startShift = iBarShift(symbol, timeframe, dayStart, false);
   if (startShift < 0) {
      // timeframe too big or data issue
      return 0.0;
   }

   int barsToCopy = startShift + 1;
   if (barsToCopy <= 0) return 0.0;

   double highs[], lows[], closes[];
   long tickVols[];

   int got = CopyHigh(symbol, timeframe, 0, barsToCopy, highs);
   if (got != barsToCopy) {
      /*PrintFormat("CopyHigh got=%d expected=%d",got,barsToCopy);*/
      return 0.0;
   }
   got = CopyLow(symbol, timeframe, 0, barsToCopy, lows);
   if (got != barsToCopy) {
      return 0.0;
   }
   got = CopyClose(symbol, timeframe, 0, barsToCopy, closes);
   if (got != barsToCopy) {
      return 0.0;
   }
   got = CopyTickVolume(symbol, timeframe, 0, barsToCopy, tickVols);
   if (got != barsToCopy) {
      return 0.0;
   }

   int n = ArraySize(closes);
   if (n <= 0) return 0.0;

   double cumTPV = 0.0;
   double cumVol = 0.0;
   // arrays indexed 0 -> current bar, n-1 -> oldest copied bar
   for (int i = 0; i < n; i++) {
      double tp = (highs[i] + lows[i] + closes[i]) / 3.0;
      double vol = (double) tickVols[i];
      cumTPV += tp * vol;
      cumVol += vol;
   }

   if (cumVol <= 0.0) return 0.0;
   return cumTPV / cumVol;
}

//+------------------------------------------------------------------+
//| Draw VWAP as a horizontal line on chart (updated each tick)      |
//+------------------------------------------------------------------+
void UpdateVWAPLine(double vwap) {
   string name = VWAP_HLINE_NAME();
   if (!Draw_VWAP_On_Chart) {
      // remove if exists
      if (ObjectFind(0, name) != -1) ObjectDelete(0, name);
      return;
   }

   if (ObjectFind(0, name) == -1) {
      // create hline
      if (!ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), vwap))
         PrintFormat("UpdateVWAPLine: failed to create HLINE err=%d", GetLastError());
      else {
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetString(0, name, OBJPROP_TEXT, "Daily VWAP");
      }
   }
   // set price of hline
   ObjectSetDouble(0, name, OBJPROP_PRICE, vwap);
}

//+------------------------------------------------------------------+
//| Session utilities (server time)                                  |
//+------------------------------------------------------------------+
enum SessionId {
   SESSION_NONE = 0, SESSION_LONDON = 1, SESSION_NY = 2
};

SessionId CurrentSessionNow(datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int h = dt.hour;

   // London
   if (London_Start_Hour <= London_End_Hour) {
      if (h >= London_Start_Hour && h < London_End_Hour) return SESSION_LONDON;
   } else {
      // wrap-around (not expected, but supported)
      if (h >= London_Start_Hour || h < London_End_Hour) return SESSION_LONDON;
   }

   // New York
   if (NewYork_Start_Hour <= NewYork_End_Hour) {
      if (h >= NewYork_Start_Hour && h < NewYork_End_Hour) return SESSION_NY;
   } else {
      if (h >= NewYork_Start_Hour || h < NewYork_End_Hour) return SESSION_NY;
   }

   return SESSION_NONE;
}

// compute start datetime of the current session for today
datetime SessionStartDatetime(SessionId sid, datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.sec = 0;
   dt.min = 0;
   if (sid == SESSION_LONDON) {
      dt.hour = London_Start_Hour;
      return StructToTime(dt);
   } else if (sid == SESSION_NY) {
      dt.hour = NewYork_Start_Hour;
      return StructToTime(dt);
   }
   return 0;
}

// compute end datetime of the current session for today
datetime SessionEndDatetime(SessionId sid, datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.sec = 0;
   dt.min = 0;
   if (sid == SESSION_LONDON) {
      dt.hour = London_End_Hour;
      return StructToTime(dt);
   } else if (sid == SESSION_NY) {
      dt.hour = NewYork_End_Hour;
      return StructToTime(dt);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Check if any position (with our Magic_Number) was opened during  |
//| the current session (prevents multiple position per session).     |
//+------------------------------------------------------------------+
bool HasPositionThisSession(SessionId sid) {
   if (sid == SESSION_NONE) return false;

   datetime now = TimeCurrent();
   datetime sStart = SessionStartDatetime(sid, now);
   datetime sEnd = SessionEndDatetime(sid, now);

   // if session end < start (wrap), make end = start + 24h
   if (sEnd <= sStart) sEnd = sStart + 24 * 3600;

   int total = PositionsTotal();
   for (int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         ulong posMagic = (ulong) PositionGetInteger(POSITION_MAGIC);
         if (posMagic != Magic_Number) continue;

         datetime open_time = (datetime) PositionGetInteger(POSITION_TIME);
         if (open_time >= sStart && open_time <= sEnd)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate lot size given risk percent and stoploss in points     |
//+------------------------------------------------------------------+
double CalcLotFromRisk(double risk_percent, double stoploss_points) {
   if (risk_percent <= 0.0) return Fixed_Lot;
   if (stoploss_points <= 0.0) return Fixed_Lot;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (risk_percent / 100.0);

   // Determine value per point per 1.0 lot:
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tick_value <= 0 || tick_size <= 0) {
      // can't compute, fallback
      return Fixed_Lot;
   }
   double value_per_point_per_lot = tick_value / tick_size;

   double loss_per_lot = stoploss_points * value_per_point_per_lot;
   if (loss_per_lot <= 0.0) return Fixed_Lot;

   double lots = risk_amount / loss_per_lot;
   // normalize to broker step/min/max
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0) step = 0.01;
   if (minlot <= 0) minlot = 0.01;
   if (maxlot <= 0) maxlot = 100.0;

   if (lots < minlot) lots = minlot;
   if (lots > maxlot) lots = maxlot;

   // round to step
   lots = MathFloor(lots / step) * step;
   if (lots < minlot) lots = minlot;
   return lots;
}

//+------------------------------------------------------------------+
//| Trading: Open buy/sell with SL/TP                                 |
//+------------------------------------------------------------------+
bool OpenBuyPosition(double lots) {
   trade.SetExpertMagicNumber(Magic_Number);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0.0, tp = 0.0;
   if (StopLoss_Points > 0) sl = ask - StopLoss_Points * _Point;
   if (TakeProfit_Points > 0) tp = ask + TakeProfit_Points * _Point;

   if (sl > 0 && sl < SymbolInfoDouble(_Symbol, SYMBOL_BID)) {
      /* ok */ }
   bool ok = trade.Buy(lots, NULL, ask, sl, tp);
   if (!ok) PrintFormat("OpenBuyPosition failed: code=%d desc=%s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else PrintFormat("Opened BUY lots=%.2f at price=%.5f SL=%.5f TP=%.5f", lots, ask, sl, tp);
   return ok;
}

bool OpenSellPosition(double lots) {
   trade.SetExpertMagicNumber(Magic_Number);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0, tp = 0.0;
   if (StopLoss_Points > 0) sl = bid + StopLoss_Points * _Point;
   if (TakeProfit_Points > 0) tp = bid - TakeProfit_Points * _Point;

   bool ok = trade.Sell(lots, NULL, bid, sl, tp);
   if (!ok) PrintFormat("OpenSellPosition failed: code=%d desc=%s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else PrintFormat("Opened SELL lots=%.2f at price=%.5f SL=%.5f TP=%.5f", lots, bid, sl, tp);
   return ok;
}

//+------------------------------------------------------------------+
//| EMA bias & cross detection                                       |
//+------------------------------------------------------------------+
int GetHighBias() {
   double fast = GetEMA(_Symbol, High_Timeframe, High_EMA_Fast_Period, High_EMA_Applied_Price, 1);
   double slow = GetEMA(_Symbol, High_Timeframe, High_EMA_Slow_Period, High_EMA_Applied_Price, 1);
   if (fast > slow) return 1;
   if (fast < slow) return -1;
   return 0;
}

int DetectLowCrossover() {
   double f2 = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Fast_Period, Low_EMA_Applied_Price, 2);
   double s2 = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Slow_Period, Low_EMA_Applied_Price, 2);
   double f1 = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Fast_Period, Low_EMA_Applied_Price, 1);
   double s1 = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Slow_Period, Low_EMA_Applied_Price, 1);
   if (f2 <= s2 && f1 > s1) return 1;
   if (f2 >= s2 && f1 < s1) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| OnInit / OnDeinit                                                |
//+------------------------------------------------------------------+
int OnInit() {
   Print("GoldEMA_Rebuild_v2 initialized (Magic=", Magic_Number, ").");
   // delete old VWAP line for fresh start
   string name = VWAP_HLINE_NAME();
   if (ObjectFind(0, name) != -1) ObjectDelete(0, name);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   // cleanup chart object optionally
   string name = VWAP_HLINE_NAME();
   if (ObjectFind(0, name) != -1) ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
//| Main logic on tick                                                |
//+------------------------------------------------------------------+
void OnTick() {
   datetime now = TimeCurrent();
   SessionId sid = CurrentSessionNow(now);
   if (sid == SESSION_NONE) {
      // outside trading sessions: nothing to do (but update VWAP object we can)
      if (Use_VWAP_Filter) {
         double vwap_now = GetDailyVWAP(_Symbol, Low_Timeframe);
         if (vwap_now > 0.0) UpdateVWAPLine(vwap_now);
      }
      return;
   }

   // compute VWAP and draw/log
   double vwap = 0.0;
   if (Use_VWAP_Filter) {
      vwap = GetDailyVWAP(_Symbol, Low_Timeframe);
      if (vwap > 0.0) {
         UpdateVWAPLine(vwap);
         // optional debug print every tick (can be noisy); kept minimal
         static datetime lastPrint = 0;
         if (TimeCurrent() - lastPrint >= 300) // every 5 minutes
         {
            lastPrint = TimeCurrent();
            PrintFormat("VWAP: %.5f (time=%s)", vwap, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
         }
      }
   }

   // ADX check
   if (Use_ADX_Filter) {
      double adx = GetADXValue(_Symbol, Low_Timeframe, ADX_Period, 1);
      if (adx <= 0.0) return;
      if (adx < ADX_Min_Threshold || adx > ADX_Max_Threshold) return;
   }

   // Determine bias & cross
   int bias = GetHighBias();
   int cross = DetectLowCrossover();

   // VWAP gating (if enabled): buys only if price > VWAP, sells only if price < VWAP
   double lastClose = iClose(_Symbol, Low_Timeframe, 0);
   if (Use_VWAP_Filter && vwap > 0.0) {
      if (cross == 1 && bias == 1 && lastClose <= vwap) return; // bull but below vwap
      if (cross == -1 && bias == -1 && lastClose >= vwap) return; // bear but above vwap
   }

   // prevent more than one trade per session:
   if (HasPositionThisSession(sid)) {
      // already have a position opened during this session -> do not open more
      return;
   }

   // If signal matches bias, open position with risk sizing
   if (cross == 1 && bias == 1) {
      double lots = Fixed_Lot;
      if (StopLoss_Points > 0) lots = CalcLotFromRisk(Risk_Percent, StopLoss_Points);
      lots = NormalizeLot(lots);
      OpenBuyPosition(lots);
   } else if (cross == -1 && bias == -1) {
      double lots = Fixed_Lot;
      if (StopLoss_Points > 0) lots = CalcLotFromRisk(Risk_Percent, StopLoss_Points);
      lots = NormalizeLot(lots);
      OpenSellPosition(lots);
   }
}

//+------------------------------------------------------------------+
