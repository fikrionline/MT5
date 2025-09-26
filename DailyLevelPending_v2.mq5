//+------------------------------------------------------------------+
//| MT5 EA: Daily Level Pending Orders with Trailing & Session Filter|
//| Author: ChatGPT (generated for user)                             |
//| Timeframe: H1                                                   |
//| Description:                                                     |
//| 1) On each H1 candle close places two pending orders:            |
//|    - Sell Limit at iHigh(Symbol, PERIOD_D1, 1)                  |
//|    - Buy  Limit at iLow (Symbol, PERIOD_D1, 1)                  |
//| 2) If any pending order fills, the opposite pending order is     |
//|    removed and a trailing stop is applied to the filled order.   |
//| 3) Position sizing aims to risk RiskPercent of account with a    |
//|    stop loss equal to the last H1 candle range (High-Low).       |
//| 4) Actual SL levels are placed on pending orders.                |
//| 5) TP is optional with RR >= 1:2 (adjustable).                   |
//| 6) EA only operates during configurable London & NewYork hours   |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
CTrade trade;

//---- input parameters
input double RiskPercent      = 0.25;       // Risk percent per trade (0.5 = 0.5%)
input bool   UseTakeProfit    = true;      // Enable/disable TP
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input double RRRatio          = 1.1;       // Risk-Reward ratio (TP = RR * SL)
input int    MagicNumber      = 19191919;  // Magic number
input bool DeletePendingOnNewH1 = true; // option to delete pending orders on new H1 candle
input int    ExpirationHours  = 24;        // Pending order expiration (hours)

// Session times (server time hours 0..23)
input int LondonStartHour = 7;  // London session start hour (server time)
input int LondonEndHour   = 16; // London session end hour (server time)
input int NYStartHour     = 12; // New York session start hour (server time)
input int NYEndHour       = 21; // New York session end hour (server time)

// Trailing stop params (in points)
input long TrailingStartPoints = 20;  // start trailing after this many points in profit
input long TrailingStepPoints  = 20;  // step size for moving stop

// Other safety
input double MinLot = 0.01;   // minimum lot
input double MaxLot = 10.0;   // maximum lot

//---- global state
datetime lastBarTime = 0;
datetime lastH1BarTime;

//+------------------------------------------------------------------+
int OnInit() {
   lastBarTime = 0;
   EventSetTimer(10); // for trailing checks every 10s
   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
}

void OnTick() {
   if (!IsAllowedSession()) return;

   datetime h1time = iTime(_Symbol, TimeFrame, 1);
   if (h1time == lastH1BarTime) return;
   lastH1BarTime = h1time;

   // Delete previous pending orders before placing new ones if enabled
   if (DeletePendingOnNewH1)
      DeletePendingOrders();

   MqlRates rates[];
   if (CopyRates(_Symbol, TimeFrame, 0, 2, rates) < 2) return;
   datetime closedBarTime = rates[1].time;
   if (closedBarTime == lastBarTime) return;
   lastBarTime = closedBarTime;

   if (PositionExists()) return;

   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
   if (dailyHigh == 0 || dailyLow == 0) return;

   double h1High = iHigh(_Symbol, TimeFrame, 1);
   double h1Low = iLow(_Symbol, TimeFrame, 1);
   long StopLossPoints = (long)((h1High - h1Low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   if (StopLossPoints <= 0) return;

   if (!HasPendingAtPrice(ORDER_TYPE_SELL_LIMIT, dailyHigh))
      PlacePending(ORDER_TYPE_SELL_LIMIT, h1High, dailyHigh, dailyLow, h1High, h1Low);
   if (!HasPendingAtPrice(ORDER_TYPE_BUY_LIMIT, dailyLow))
      PlacePending(ORDER_TYPE_BUY_LIMIT, h1Low, dailyHigh, dailyLow, h1High, h1Low);
}

void OnTimer() {
   for (int i = PositionsTotal() - 1; i >= 0; --i) {
      if (PositionGetTicket(i) <= 0) continue;
      ulong ticketIndex = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticketIndex)) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      string sym = PositionGetString(POSITION_SYMBOL);
      if (sym != _Symbol) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_price = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPoints = (ptype == POSITION_TYPE_BUY) ? (cur_price - open_price) / point : (open_price - cur_price) / point;

      if (profitPoints >= TrailingStartPoints) {
         double newSL = 0;
         if (ptype == POSITION_TYPE_BUY)
            newSL = cur_price - TrailingStepPoints * point;
         else
            newSL = cur_price + TrailingStepPoints * point;

         if (PositionModifySLTP(ticket, newSL, 0)) {
            CancelOppositePendings();
         }
      }
   }
}

void PlacePending(ENUM_ORDER_TYPE type, double price, double StopLossSellLimit, double StopLossBuyLimit, double h1High, double h1Low) {
   double lotsSellLimit = CalculateLot(StopLossSellLimit - price);
   double lotsBuyLimit = CalculateLot(price - StopLossBuyLimit);
   
   if (lotsSellLimit < MinLot) lotsSellLimit = MinLot;
   if (lotsSellLimit > MaxLot) lotsSellLimit = MaxLot;
   
   if (lotsBuyLimit < MinLot) lotsBuyLimit = MinLot;
   if (lotsBuyLimit > MaxLot) lotsBuyLimit = MaxLot;

   datetime expiration = TimeCurrent() + ExpirationHours * 3600;

   double sl = 0, tp = 0;
   if (type == ORDER_TYPE_SELL_LIMIT) {
      sl = StopLossSellLimit;
      if (UseTakeProfit)
         tp = price - ((StopLossSellLimit - price) * RRRatio);
   } else if (type == ORDER_TYPE_BUY_LIMIT) {
      sl = StopLossBuyLimit;
      if (UseTakeProfit)
         tp = price + ((price - StopLossBuyLimit) * RRRatio);
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.price = NormalizeDouble(price, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.deviation = 10;
   request.type = type;
   request.magic = MagicNumber;
   request.expiration = expiration;
   request.type_filling = ORDER_FILLING_FOK;
   request.sl = NormalizeDouble(sl, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp = (UseTakeProfit && tp > 0) ? NormalizeDouble(tp, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) : 0.0;

   if (!OrderSend(request, result)) {
      PrintFormat("OrderSend failed: code=%d ret=%s", result.retcode, result.comment);
   } else
      PrintFormat("Pending placed ticket=%I64u price=%.5f lots=%.2f SL=%.5f TP=%.5f", result.order, request.price, request.sl, request.tp);
}

bool IsAllowedSession() {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int hour = dt.hour;
   if (IsHourInRange(hour, LondonStartHour, LondonEndHour)) return true;
   if (IsHourInRange(hour, NYStartHour, NYEndHour)) return true;
   return false;
}

bool IsHourInRange(int h, int s, int e) {
   if (s <= e) return (h >= s && h < e);
   return (h >= s || h < e);
}

bool HasPendingAtPrice(ENUM_ORDER_TYPE type, double price) {
   for (int i = OrdersTotal() - 1; i >= 0; --i) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0) continue;
      if (!OrderSelect(ticket)) continue;
      if (OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if ((ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE) != type) continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      double op = OrderGetDouble(ORDER_PRICE_OPEN);
      if (MathAbs(op - price) <= SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) return true;
   }
   return false;
}

void CancelOppositePendings() {
   for (int i = OrdersTotal() - 1; i >= 0; --i) {
      ulong ticketIndex = OrderGetTicket(i);
      if (ticketIndex == 0) continue;
      if (!OrderSelect(ticketIndex)) continue;

      if (OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      ENUM_ORDER_STATE st = (ENUM_ORDER_STATE) OrderGetInteger(ORDER_STATE);
      if (st == ORDER_STATE_STARTED || st == ORDER_STATE_PLACED) {
         ulong ticket = OrderGetInteger(ORDER_TICKET);
         if (!trade.OrderDelete(ticket))
            PrintFormat("Failed to delete pending %I64u: %s", ticket, GetLastError());
         else
            PrintFormat("Deleted pending %I64u", ticket);
      }
   }
}

double NormalizeLot(double lots) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if (step <= 0) step = 0.01;
   double res = MathFloor(lots / step) * step;
   if (res < min) res = min;
   return (res);
}

bool PositionModifySLTP(ulong ticket, double sl, double tp) {
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl = (sl > 0) ? NormalizeDouble(sl, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) : 0.0;
   req.tp = (tp > 0) ? NormalizeDouble(tp, (int) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) : 0.0;
   if (!OrderSend(req, res)) {
      PrintFormat("Position SL/TP modify failed: %d - %s", res.retcode, res.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+

bool PositionExists() {
   for (int i = PositionsTotal() - 1; i >= 0; --i) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//--- check if within trading session
bool IsTradingSession() {

   datetime t = TimeCurrent();
   MqlDateTime str;
   TimeToStruct(t, str);
   int hour = str.hour;

   if ((hour >= LondonStartHour && hour < LondonEndHour) || (hour >= NYStartHour && hour < NYEndHour))
      return true;
   return false;
}

//--- delete all pending orders for this symbol
void DeletePendingOrders() {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0) continue;
      if (!OrderSelect(ticket)) continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);
      if (sym == _Symbol && (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)) {
         if (OrderGetInteger(ORDER_MAGIC) == MagicNumber)
            trade.OrderDelete(ticket);
      }
   }
}

//--- calculate lot size with RiskPercent
double CalculateLot(double stopPoints) {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // value of 1 point movement per 1 lot
   double valuePerPointPerLot = tickValue / (tickSize / point);

   // total loss in money if SL hit for 1 lot
   double lossPerLot = stopPoints * valuePerPointPerLot;

   if (lossPerLot <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskMoney / lossPerLot;

   // adjust to broker rules
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / step) * step;
   if (lots < minLot) lots = minLot;
   if (lots > maxLot) lots = maxLot;

   return lots;
}
