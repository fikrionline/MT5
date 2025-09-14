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
input int HourToPlace = 10; // Hour (server time) to place pending orders
input int MinuteToPlace = 01; // Minute at that hour
input int SL_Pips = 15; // Stop Loss in pips
input int TP_Pips = 30; // Take Profit in pips
input int EntryOffset_Pips = 5; // Distance from current price to set pending order (in pips)
input double Lots = 0.1; // Lot size

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

   // only once per day
   if (today_midnight == last_placed_day) return;

   // check if it's the configured time (only trigger during that minute)
   if (dt.hour == HourToPlace && dt.min == MinuteToPlace) {
      // close all order position, if there are position
      CloseAllPositions();
      // place orders
      bool ok = PlaceDailyPendingOrders();
      if (ok) {
         last_placed_day = today_midnight;
         Print("Pending orders placed for ", TimeToString(now, TIME_DATE | TIME_MINUTES));
      } else {
         Print("Failed to place some pending orders at ", TimeToString(now, TIME_DATE | TIME_MINUTES));
      }
   }
}

//+------------------------------------------------------------------+
bool PlaceDailyPendingOrders() {
   string symbol = _Symbol;

   // get current prices
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if (ask == 0 || bid == 0) {
      Print("Error getting market prices for ", symbol);
      return (false);
   }

   // point and pip handling
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pip = point * 10.0; // typical pip = 10 * point for FX symbols with 5/3 digits
   if (pip <= 0) pip = point; // fallback

   double entry_offset = EntryOffset_Pips * pip;
   double sl_distance = SL_Pips * pip;
   double tp_distance = TP_Pips * pip;

   // calculate buy stop price (above ask)
   double buy_entry = NormalizeDouble(ask + entry_offset, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double buy_sl = NormalizeDouble(buy_entry - sl_distance, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double buy_tp = NormalizeDouble(buy_entry + tp_distance, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   // calculate sell stop price (below bid)
   double sell_entry = NormalizeDouble(bid - entry_offset, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double sell_sl = NormalizeDouble(sell_entry + sl_distance, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double sell_tp = NormalizeDouble(sell_entry - tp_distance, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   // remove existing pending orders placed by this EA for the same symbol (OPTIONAL)
   CancelExistingDailyPendings();

   bool all_ok = true;

   // prepare and send BUY_STOP pending order
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = symbol;
   req.volume = Lots;
   req.type = ORDER_TYPE_BUY_STOP;
   req.price = buy_entry;
   req.sl = buy_sl;
   req.tp = buy_tp;
   req.deviation = 10; // max slippage in points
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time = ORDER_TIME_GTC; // keep until cancelled

   if (!SendOrderCustom(req, res)) {
      PrintFormat("OrderSend BUY_STOP failed. retcode=%d comment=%s", res.retcode, res.comment);
      all_ok = false;
   } else {
      PrintFormat("BUY_STOP placed at %G SL=%G TP=%G ticket=%I64d", buy_entry, buy_sl, buy_tp, res.order);
   }

   // prepare and send SELL_STOP pending order
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = symbol;
   req.volume = Lots;
   req.type = ORDER_TYPE_SELL_STOP;
   req.price = sell_entry;
   req.sl = sell_sl;
   req.tp = sell_tp;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time = ORDER_TIME_GTC;

   if (!OrderSend(req, res)) {
      PrintFormat("OrderSend SELL_STOP failed. retcode=%d comment=%s", res.retcode, res.comment);
      all_ok = false;
   } else {
      PrintFormat("SELL_STOP placed at %G SL=%G TP=%G ticket=%I64d", sell_entry, sell_sl, sell_tp, res.order);
   }

   return (all_ok);
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
// helper: wrapper for OrderSend to cope with platform differences
bool SendOrderCustom(MqlTradeRequest & request, MqlTradeResult & result) {
   if (!::OrderSend(request, result)) {
      return (false);
   }
   if (result.retcode == 10009 || result.retcode == 10004 || result.retcode == 10006 ||
      result.retcode == 10002 || result.retcode == 10008) {
      return (true);
   }
   if (result.order > 0) return (true);
   return (false);
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
