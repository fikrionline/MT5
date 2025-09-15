//+------------------------------------------------------------------+
//| MT5 Expert Advisor: Daily BuyStop & SellStop at specific time    |
//| Places one BUY_STOP and one SELL_STOP every day at a given hour   |
//| Inputs: time (hour:minute), SL (pips), TP (pips), Entry offset    |
//+------------------------------------------------------------------+
#property copyright ""
#property link ""
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//--- user inputs
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1; // Time Frame use for Bar
input uint NumberOfBar = 1; // Number or Candle (1 = Last Candle)
input int HourToPlace = 8; // Hour (server time) to place pending orders
input int MinuteToPlace = 2; // Minute at that hour
input double Lots = 0.1; // Lot size
input double cRiskReward = 2; // Risk Reward Ratio

//--- internal
datetime last_placed_day = 0; // day when orders were placed (midnight timestamp)

//+------------------------------------------------------------------+
int OnInit() {
   last_placed_day = 0;
   Print("EA initialized. Will place BUY_STOP and SELL_STOP every day at ", HourToPlace, ":", MinuteToPlace);
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // nothing to do
}

//+------------------------------------------------------------------+
void OnTick() {
   // get server time
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // compute midnight timestamp for today
   MqlDateTime dt_mid = dt;
   dt_mid.hour = 0;
   dt_mid.min = 0;
   dt_mid.sec = 0;
   datetime today_midnight = StructToTime(dt_mid);
   
   CloseAllPendingOrders();

   // only once per day
   if (today_midnight == last_placed_day) return;

   // check if it's the configured time (only trigger during that minute)
   if (dt.hour == HourToPlace && dt.min == MinuteToPlace) {
   
      CloseAllPositions();
      
      PlaceBuyStop();
   
      PlaceSellStop();
      
      bool ok = true;
      if (ok) {
         last_placed_day = today_midnight;
         Print("Pending orders placed for ", TimeToString(now, TIME_DATE | TIME_MINUTES));
      } else {
         Print("Failed to place some pending orders at ", TimeToString(now, TIME_DATE | TIME_MINUTES));
      }
   }
}

//+------------------------------------------------------------------+
void CancelExistingDailyPendings() {
   // Cancel pending orders for this symbol that are of type BUY_STOP or SELL_STOP
   ulong total = OrdersTotal();
   for (int i = (int) total - 1; i >= 0; i--) {
      if (OrderGetTicket(i) <= 0) continue;
      ulong ticket = OrderGetTicket(i);
      if (!OrderSelect(ticket)) continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      int type = (int) OrderGetInteger(ORDER_TYPE);
      if (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP) {
         // cancel
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = TRADE_ACTION_REMOVE;
         req.order = ticket;
         if (!OrderSend(req, res)) {
            PrintFormat("Failed to remove pending ticket %I64d ret=%d comment=%s", ticket, res.retcode, res.comment);
         } else {
            PrintFormat("Removed existing pending ticket %I64d", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
void PlaceBuyStop() {

   double digits = (double) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double cHigh = iHigh(_Symbol, TimeFrame, NumberOfBar);
   double cLow = iLow(_Symbol, TimeFrame, NumberOfBar);

   double cSLPips = NormalizeDouble(cHigh - cLow, (int) digits);
   double cTPPips = cSLPips * cRiskReward;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_BUY_STOP;
   request.price = cHigh + (ask - bid);
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   // stoploss and takeprofit in price terms
   double sl = cLow - (ask - bid);
   double tp = cHigh + cTPPips + ((ask - bid) * 2);
   request.sl = NormalizeDouble(sl, (int) digits);
   request.tp = NormalizeDouble(tp, (int) digits);

   if (!OrderSend(request, result)) {
      PrintFormat("BuyStop send failed: ret=%d, comment=%s", result.retcode, result.comment);
   } else {
      PrintFormat("BuyStop placed @%G ticket=%I64u", request.price, result.order);
   }
}

//+------------------------------------------------------------------+
void PlaceSellStop() {

   double digits = (double) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double cHigh = iHigh(_Symbol, TimeFrame, NumberOfBar);
   double cLow = iLow(_Symbol, TimeFrame, NumberOfBar);

   double cSLPips = NormalizeDouble(cHigh - cLow, (int) digits);
   double cTPPips = cSLPips * cRiskReward;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_SELL_STOP;
   request.price = cLow - (ask - bid);
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   double sl = cHigh + (ask - bid);
   double tp = cLow - cTPPips - ((ask - bid) * 2);
   request.sl = NormalizeDouble(sl, (int) digits);
   request.tp = NormalizeDouble(tp, (int) digits);

   if (!OrderSend(request, result)) {
      PrintFormat("SellStop send failed: ret=%d, comment=%s", result.retcode, result.comment);
   } else {
      PrintFormat("SellStop placed @%G ticket=%I64u", request.price, result.order);
   }
}

void CloseAllPositions() {
   CTrade m_trade; // Trades Info and Executions library
   COrderInfo m_order; //Library for Orders information
   CPositionInfo m_position; // Library for all position features and information
   //--Đóng Positions
   for (int i = PositionsTotal() - 1; i >= 0; i--) // loop all Open Positions
      if (m_position.SelectByIndex(i)) // select a position
   {
      m_trade.PositionClose(m_position.Ticket()); // then close it --period
      Sleep(100); // Relax for 100 ms
   }
   //--End Đóng Positions

   //--Đóng Orders
   for (int i = OrdersTotal() - 1; i >= 0; i--) // loop all Orders
      if (m_order.SelectByIndex(i)) // select an order
   {
      m_trade.OrderDelete(m_order.Ticket()); // then delete it --period
      Sleep(100); // Relax for 100 ms
   }
   //--End Đóng Orders
   //--Đóng Positions lần 2 cho chắc
   for (int i = PositionsTotal() - 1; i >= 0; i--) // loop all Open Positions
      if (m_position.SelectByIndex(i)) // select a position
   {
      m_trade.PositionClose(m_position.Ticket()); // then close it --period
      Sleep(100); // Relax for 100 ms
   }
   //--End Đóng Positions lần 2 cho chắc
} // End func Close_all
//+------------------------------------------------------------------+

void CloseAllPendingOrders() {
   CTrade m_trade; // Trades Info and Executions library
   COrderInfo m_order; //Library for Orders information
   CPositionInfo m_position; // Library for all position features and information
   
   //--End Đóng Orders
   //--Đóng Positions lần 2 cho chắc
   for (int i = PositionsTotal() - 1; i >= 0; i--) // loop all Open Positions
      if (m_position.SelectByIndex(i)) // select a position
   {
      //--Đóng Orders
      for (int i = OrdersTotal() - 1; i >= 0; i--) // loop all Orders
         if (m_order.SelectByIndex(i)) // select an order
      {
         m_trade.OrderDelete(m_order.Ticket()); // then delete it --period
         Sleep(100); // Relax for 100 ms
      }
      Sleep(100); // Relax for 100 ms
   }
   //--End Đóng Positions lần 2 cho chắc
} // End func Close_all
//+------------------------------------------------------------------+
