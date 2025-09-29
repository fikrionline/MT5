//+------------------------------------------------------------------+
//| MT5 Expert Advisor: H1 Session Pending Limits with Risk %        |
//| Added filter: Only buy if today's lowest open > yesterday's,     |
//| and only sell if today's highest open < yesterday's.             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| MT5 Expert Advisor: H1 Session Pending Limits with Risk %        |
//| Updated: Skip non-trading days for yesterday's data (Monday fix). |
//+------------------------------------------------------------------+
#property version   "1.40"
#property strict
  
input int    LondonStartHour = 7;
input int    LondonEndHour   = 16;
input int    NewYorkStartHour= 12;
input int    NewYorkEndHour  = 21;
input bool   UseLondon = true;
input bool   UseNewYork = true;
input uint   MagicBuy  = 123001;
input uint   MagicSell = 123002;
input int    SlTpMultiplier = 1;
input int    TrailingStopPoints = 0;
input int    MinDistancePoints = 10;
input double RiskPercent = 1.0;
input ENUM_TIMEFRAMES TF = PERIOD_H1;

datetime lastH1BarTime = 0;

int OnInit() {
   lastH1BarTime = iTime(_Symbol, TF, 0);
   Print("[EA INIT] EA initialized.");
   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   PrintFormat("[EA DEINIT] EA removed. Reason=%d", reason);
}

void OnTick() {
   datetime curH1 = iTime(_Symbol, TF, 0);
   if (curH1 != lastH1BarTime) {
      OnH1Close();
      lastH1BarTime = curH1;
   }
   if (TrailingStopPoints > 0)
      ApplyTrailingStops();
}

void OnH1Close() {
   if (!IsWithinTradingSessions()) {
      DeleteHourlyPendingIfAny();
      Print("[EA INFO] Outside trading session. Pending orders deleted.");
      return;
   }
   double todayHighestOpen = GetTodaysHighestOpen();
   double todayLowestOpen = GetTodaysLowestOpen();
   double yestHighestOpen = GetYesterdaysHighestOpen();
   double yestLowestOpen = GetYesterdaysLowestOpen();
   if (todayHighestOpen == 0 || todayLowestOpen == 0 || yestLowestOpen == 0 || yestHighestOpen == 0) {
      Print("[EA WARN] Could not determine today's/yesterday's high/low opens.");
      return;
   }
   double rng = iHigh(_Symbol, TF, 1) - iLow(_Symbol, TF, 1);
   if (rng <= 0) {
      Print("[EA WARN] Previous H1 range zero or invalid.");
      return;
   }
   double sltpPriceDistance = rng * SlTpMultiplier;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool hasOpenBuy = ExistsOpenPosition(POSITION_TYPE_BUY, MagicBuy);
   bool hasOpenSell = ExistsOpenPosition(POSITION_TYPE_SELL, MagicSell);
   DeleteHourlyPendingIfAny();
   // filter for sell: only if today's highest open < yesterday's highest open
   if (!hasOpenSell && todayHighestOpen < yestHighestOpen) {
      double sellPrice = todayHighestOpen;
      if (sellPrice > bid + MinDistancePoints * _Point) {
         if (!CreatePendingOrder(ORDER_TYPE_SELL_LIMIT, sellPrice, MagicSell, sltpPriceDistance))
            Print("[EA ERROR] Failed to create SellLimit order.");
      }
   }
   // filter for buy: only if today's lowest open > yesterday's lowest open
   if (!hasOpenBuy && todayLowestOpen > yestLowestOpen) {
      double buyPrice = todayLowestOpen;
      if (buyPrice < ask - MinDistancePoints * _Point) {
         if (!CreatePendingOrder(ORDER_TYPE_BUY_LIMIT, buyPrice, MagicBuy, sltpPriceDistance))
            Print("[EA ERROR] Failed to create BuyLimit order.");
      }
   }
}

bool IsWithinTradingSessions() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   bool inLondon = false, inNewYork = false;
   if (UseLondon) inLondon = (hour >= LondonStartHour && hour < LondonEndHour);
   if (UseNewYork) inNewYork = (hour >= NewYorkStartHour && hour < NewYorkEndHour);
   return (inLondon || inNewYork);
}

// helper: find last trading day start before today

datetime GetLastTradingDayStart() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   for (int back = 1; back <= 7; back++) {
      datetime prevDayStart = todayStart - 86400 * back;
      // check if there is at least one H1 bar for that day
      int shift = iBarShift(_Symbol, TF, prevDayStart, true);
      if (shift >= 0) {
         datetime barTime = iTime(_Symbol, TF, shift);
         if (barTime > 0 && barTime < todayStart)
            return prevDayStart;
      }
   }
   return (0);
}

double GetTodaysHighestOpen() {
   datetime t0 = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t0, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   int i = 0;
   double highest = 0;
   while (true) {
      datetime t = iTime(_Symbol, TF, i);
      if (t == 0 || t < dayStart) break;
      double open = iOpen(_Symbol, TF, i);
      if (open > highest || highest == 0) highest = open;
      i++;
      if (i > 10000) break;
   }
   return highest;
}

double GetTodaysLowestOpen() {
   datetime t0 = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t0, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   int i = 0;
   double lowest = 0;
   while (true) {
      datetime t = iTime(_Symbol, TF, i);
      if (t == 0 || t < dayStart) break;
      double open = iOpen(_Symbol, TF, i);
      if (open < lowest || lowest == 0) lowest = open;
      i++;
      if (i > 10000) break;
   }
   return lowest;
}

double GetYesterdaysHighestOpen() {
   datetime yesterdayStart = GetLastTradingDayStart();
   if (yesterdayStart == 0) return 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   int i = 0;
   double highest = 0;
   while (true) {
      datetime t = iTime(_Symbol, TF, i);
      if (t == 0 || t < yesterdayStart) break;
      if (t >= todayStart) {
         i++;
         continue;
      }
      double open = iOpen(_Symbol, TF, i);
      if (open > highest || highest == 0) highest = open;
      i++;
      if (i > 10000) break;
   }
   return highest;
}

double GetYesterdaysLowestOpen() {
   datetime yesterdayStart = GetLastTradingDayStart();
   if (yesterdayStart == 0) return 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   int i = 0;
   double lowest = 0;
   while (true) {
      datetime t = iTime(_Symbol, TF, i);
      if (t == 0 || t < yesterdayStart) break;
      if (t >= todayStart) {
         i++;
         continue;
      }
      double open = iOpen(_Symbol, TF, i);
      if (open < lowest || lowest == 0) lowest = open;
      i++;
      if (i > 10000) break;
   }
   return lowest;
}

// rest of functions (DeleteHourlyPendingIfAny, CalculateLotSize, CreatePendingOrder, ExistsOpenPosition, ApplyTrailingStops, ModifyPositionSL) remain unchanged
//+------------------------------------------------------------------+

void DeleteHourlyPendingIfAny() {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (!OrderSelect(ticket)) continue;
      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);
      ulong magic = OrderGetInteger(ORDER_MAGIC);
      if ((otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT) &&
         (magic == MagicBuy || magic == MagicSell)) {
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = TRADE_ACTION_REMOVE;
         req.order = ticket;
         if (!OrderSend(req, res))
            PrintFormat("[EA ERROR] Failed to delete pending order ticket=%I64u ret=%d", ticket, res.retcode);
      }
   }
}

double CalculateLotSize(double sltpPriceDistance) {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if (tickValue <= 0 || contractSize <= 0 || sltpPriceDistance <= 0)
      return (SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   double oneLotLoss = (sltpPriceDistance / _Point) * tickValue;
   double lots = riskMoney / oneLotLoss;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = NormalizeDouble(lots, 2);
   lots = MathFloor(lots / lotStep) * lotStep;
   return lots;
}

bool CreatePendingOrder(int type, double price, uint magic, double sltpPriceDistance) {
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.magic = magic;
   req.type = (ENUM_ORDER_TYPE) type;
   req.price = NormalizeDouble(price, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   req.deviation = 10;
   req.volume = CalculateLotSize(sltpPriceDistance);
   double sl = 0, tp = 0;
   if (type == ORDER_TYPE_BUY_LIMIT) {
      sl = req.price - sltpPriceDistance;
      tp = req.price + sltpPriceDistance;
   } else if (type == ORDER_TYPE_SELL_LIMIT) {
      sl = req.price + sltpPriceDistance;
      tp = req.price - sltpPriceDistance;
   }
   int dig = (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   req.sl = NormalizeDouble(sl, dig);
   req.tp = NormalizeDouble(tp, dig);
   if (!OrderSend(req, res)) {
      PrintFormat("[EA ERROR] OrderSend failed retcode=%d", res.retcode);
      return false;
   }
   PrintFormat("[EA INFO] Pending order placed type=%d price=%.5f lots=%.2f", type, req.price, req.volume);
   return true;
}

bool ExistsOpenPosition(ENUM_POSITION_TYPE ptype, uint magic) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      string sym = PositionGetSymbol(i);
      if (!PositionSelect(sym)) continue;
      if (sym != _Symbol) continue;
      ulong pmagic = PositionGetInteger(POSITION_MAGIC);
      long ppos_type = PositionGetInteger(POSITION_TYPE);
      if (pmagic == magic && ppos_type == ptype) return true;
   }
   return false;
}

void ApplyTrailingStops() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      string sym = PositionGetSymbol(i);
      if (!PositionSelect(sym)) continue;
      if (sym != _Symbol) continue;
      ulong pos_magic = (ulong) PositionGetInteger(POSITION_MAGIC);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double current_sl = PositionGetDouble(POSITION_SL);
      if (pos_magic != MagicBuy && pos_magic != MagicSell) continue;
      int dig = (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if (pos_type == POSITION_TYPE_BUY) {
         double desired_sl = current_price - TrailingStopPoints * _Point;
         if (desired_sl > current_sl + _Point * 0.5)
            ModifyPositionSL((ulong) PositionGetInteger(POSITION_TICKET), NormalizeDouble(desired_sl, dig));
      } else if (pos_type == POSITION_TYPE_SELL) {
         double desired_sl = current_price + TrailingStopPoints * _Point;
         if (desired_sl < current_sl - _Point * 0.5 || current_sl == 0)
            ModifyPositionSL((ulong) PositionGetInteger(POSITION_TICKET), NormalizeDouble(desired_sl, dig));
      }
   }
}

bool ModifyPositionSL(ulong ticket, double newSL) {
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl = newSL;
   if (!OrderSend(req, res)) {
      PrintFormat("[EA ERROR] Failed to modify SL ticket=%I64u retcode=%d", ticket, res.retcode);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
