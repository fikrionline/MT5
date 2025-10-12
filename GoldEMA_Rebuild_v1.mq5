//+------------------------------------------------------------------+
//|                                          GoldEMA_Rebuild_v1.mq5 |
//| Reconstructed EMA Strategy EA with Daily VWAP Filter (MQL5)     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input ENUM_TIMEFRAMES High_Timeframe        = PERIOD_H4;
input int    High_EMA_Fast_Period           = 9;
input int    High_EMA_Slow_Period           = 20;
input ENUM_APPLIED_PRICE High_EMA_Applied_Price = PRICE_CLOSE;

input ENUM_TIMEFRAMES Low_Timeframe         = PERIOD_M15;
input int    Low_EMA_Fast_Period            = 9;
input int    Low_EMA_Slow_Period            = 20;
input ENUM_APPLIED_PRICE Low_EMA_Applied_Price  = PRICE_CLOSE;

input bool   Use_VWAP_Filter                = true;
input bool   Use_ADX_Filter                 = true;
input int    ADX_Period                     = 14;
input int    ADX_Min_Threshold              = 11;
input int    ADX_Max_Threshold              = 53;

input bool   Use_News_Filter                = false;

input double Fixed_Lot                      = 0.10;
input double TakeProfit_Points              = 1000.0;
input double StopLoss_Points                = 500.0;

input ulong  Magic_Number                   = 12345;
CTrade trade;

//+------------------------------------------------------------------+
//| EMA Calculation (MQL5 style)                                     |
//+------------------------------------------------------------------+
double GetEMA(string symbol, ENUM_TIMEFRAMES timeframe, int period, ENUM_APPLIED_PRICE applied_price, int shift) {
   int handle = iMA(symbol, timeframe, period, 0, MODE_EMA, applied_price);
   if (handle == INVALID_HANDLE) {
      Print("Failed to create EMA handle. Error: ", GetLastError());
      return 0.0;
   }
   double buffer[];
   if (CopyBuffer(handle, 0, shift, 1, buffer) != 1) {
      Print("Failed to copy EMA buffer. Error: ", GetLastError());
      return 0.0;
   }
   return buffer[0];
}

//+------------------------------------------------------------------+
//| ADX Calculation (MQL5 style)                                     |
//+------------------------------------------------------------------+
double GetADX(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
   int handle = iADX(symbol, timeframe, period);
   if (handle == INVALID_HANDLE) {
      Print("Failed to create ADX handle. Error: ", GetLastError());
      return 0.0;
   }
   double buffer[];
   if (CopyBuffer(handle, 0, shift, 1, buffer) != 1) {
      Print("Failed to copy ADX buffer. Error: ", GetLastError());
      return 0.0;
   }
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Daily VWAP Calculation (fixed types)                             |
//+------------------------------------------------------------------+
double GetDailyVWAP(string symbol, ENUM_TIMEFRAMES timeframe) {
   // Find the start-of-day bar time (D1 time of current day)
   datetime dayStart = iTime(symbol, PERIOD_D1, 0);
   if (dayStart == 0) {
      Print("GetDailyVWAP: failed to get day start");
      return 0.0;
   }

   // Find the shift (index) of the bar that started at or after dayStart on the requested timeframe
   int startShift = iBarShift(symbol, timeframe, dayStart, false);
   if (startShift < 0) {
      // If not found, return fail-safe
      return 0.0;
   }

   // Number of bars from current (shift 0) back to the day-start bar inclusive
   int barsToCopy = startShift + 1;
   if (barsToCopy <= 0)
      return 0.0;

   // Arrays to receive data
   double highs[], lows[], closes[];
   long vols[]; // tick volumes must be long

   // Copy data starting from shift 0 (current bar) going back `barsToCopy` bars
   int got;
   got = CopyHigh(symbol, timeframe, 0, barsToCopy, highs);
   if (got != barsToCopy) {
      PrintFormat("GetDailyVWAP: CopyHigh returned %d (expected %d)", got, barsToCopy);
      return 0.0;
   }
   got = CopyLow(symbol, timeframe, 0, barsToCopy, lows);
   if (got != barsToCopy) {
      PrintFormat("GetDailyVWAP: CopyLow returned %d (expected %d)", got, barsToCopy);
      return 0.0;
   }
   got = CopyClose(symbol, timeframe, 0, barsToCopy, closes);
   if (got != barsToCopy) {
      PrintFormat("GetDailyVWAP: CopyClose returned %d (expected %d)", got, barsToCopy);
      return 0.0;
   }
   // Use tick volume (long array)
   got = CopyTickVolume(symbol, timeframe, 0, barsToCopy, vols);
   if (got != barsToCopy) {
      PrintFormat("GetDailyVWAP: CopyTickVolume returned %d (expected %d)", got, barsToCopy);
      return 0.0;
   }

   int n = ArraySize(closes);
   if (n <= 0) return 0.0;

   double cumulativeTPV = 0.0;
   double cumulativeVolume = 0.0;

   // arrays indexed 0 -> current bar, n-1 -> oldest copied bar
   for (int i = 0; i < n; i++) {
      double typicalPrice = (highs[i] + lows[i] + closes[i]) / 3.0;
      double vol = (double) vols[i]; // cast long -> double for math
      cumulativeTPV += typicalPrice * vol;
      cumulativeVolume += vol;
   }

   if (cumulativeVolume <= 0.0) return 0.0;

   return cumulativeTPV / cumulativeVolume;
}

//+------------------------------------------------------------------+
//| VWAP Filter Condition                                             |
//+------------------------------------------------------------------+
bool IsPriceAboveVWAP() {
   double vwap = GetDailyVWAP(_Symbol, Low_Timeframe);
   if (vwap <= 0.0) // fail-safe: if VWAP couldn't be computed, don't block trades
      return true;

   double lastClose = iClose(_Symbol, Low_Timeframe, 0);
   return (lastClose > vwap);
}

//+------------------------------------------------------------------+
//| Placeholder News Filter                                           |
//+------------------------------------------------------------------+
bool IsNewsBlocked() {
   if (!Use_News_Filter) return false;
   // If you want an actual news filter, we must integrate a WebRequest to a calendar provider
   return false;
}

//+------------------------------------------------------------------+
//| Determine bias from high timeframe EMAs                           |
//+------------------------------------------------------------------+
int GetHighBias() {
   double fast = GetEMA(_Symbol, High_Timeframe, High_EMA_Fast_Period, High_EMA_Applied_Price, 1);
   double slow = GetEMA(_Symbol, High_Timeframe, High_EMA_Slow_Period, High_EMA_Applied_Price, 1);

   if (fast > slow) return 1;
   if (fast < slow) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Detect crossover on low timeframe                                 |
//+------------------------------------------------------------------+
int DetectLowCrossover() {
   double fast_prev = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Fast_Period, Low_EMA_Applied_Price, 2);
   double slow_prev = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Slow_Period, Low_EMA_Applied_Price, 2);
   double fast_now = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Fast_Period, Low_EMA_Applied_Price, 1);
   double slow_now = GetEMA(_Symbol, Low_Timeframe, Low_EMA_Slow_Period, Low_EMA_Applied_Price, 1);

   if (fast_prev <= slow_prev && fast_now > slow_now) return 1; // bullish cross
   if (fast_prev >= slow_prev && fast_now < slow_now) return -1; // bearish cross
   return 0;
}

//+------------------------------------------------------------------+
//| Normalize Lot                                                     |
//+------------------------------------------------------------------+
double NormalizeLot(double lots) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if (step <= 0) step = 0.01;
   if (minlot <= 0) minlot = 0.01;
   if (maxlot <= 0) maxlot = 100.0;

   lots = MathMax(lots, minlot);
   lots = MathMin(lots, maxlot);
   lots = MathRound(lots / step) * step;
   return lots;
}

//+------------------------------------------------------------------+
//| Trade functions                                                   |
//+------------------------------------------------------------------+
bool OpenBuy(double lots) {
   trade.SetExpertMagicNumber(Magic_Number);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0.0, tp = 0.0;
   if (StopLoss_Points > 0) sl = price - StopLoss_Points * _Point;
   if (TakeProfit_Points > 0) tp = price + TakeProfit_Points * _Point;
   bool res = trade.Buy(lots, _Symbol, price, sl, tp);
   if (!res) Print("OpenBuy failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   return res;
}

bool OpenSell(double lots) {
   trade.SetExpertMagicNumber(Magic_Number);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0, tp = 0.0;
   if (StopLoss_Points > 0) sl = price + StopLoss_Points * _Point;
   if (TakeProfit_Points > 0) tp = price - TakeProfit_Points * _Point;
   bool res = trade.Sell(lots, _Symbol, price, sl, tp);
   if (!res) Print("OpenSell failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   return res;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
   Print("GoldEMA_Rebuild_v1 with Daily VWAP initialized successfully");
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick Trading Logic                                              |
//+------------------------------------------------------------------+
void OnTick() {
   if (IsNewsBlocked()) return;

   int bias = GetHighBias();
   int cross = DetectLowCrossover();

   if (Use_ADX_Filter) {
      double adx = GetADX(_Symbol, Low_Timeframe, ADX_Period, 1);
      if (adx < ADX_Min_Threshold || adx > ADX_Max_Threshold)
         return; // skip if ADX out of range
   }

   // VWAP gating: for buys require price above VWAP; for sells require price below VWAP
   if (Use_VWAP_Filter) {
      bool above = IsPriceAboveVWAP();
      if (cross == 1 && bias == 1 && !above) return; // bullish setup but below VWAP -> skip
      if (cross == -1 && bias == -1 && above) return; // bearish setup but above VWAP -> skip
   }

   if (cross == 1 && bias == 1)
      OpenBuy(NormalizeLot(Fixed_Lot));
   else if (cross == -1 && bias == -1)
      OpenSell(NormalizeLot(Fixed_Lot));
}
