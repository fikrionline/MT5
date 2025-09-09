//+------------------------------------------------------------------+
//| MT5 EA: Buttons for Buy Stop, Sell Stop and Close All            |
//| Filename: MT5_EA_Buttons_Stop_Close_All.mq5                       |
//| Author: ChatGPT (generated)                                       |
//| Description: Simple Expert Advisor that places a Buy Stop or     |
//| Sell Stop pending order with configurable distance in pips and    |
//| a Close All button to close all open positions.                  |
//+------------------------------------------------------------------+
#property copyright "ChatGPT and Googling"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//--- input parameters
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input uint NumberOfBar = 1;
input double cRiskReward = 2;
input int StopPips = 20; // distance for pending orders (pips)
input double Lots = 0.01; // default lot size
input int SlPips = 50; // default stop loss (pips)
input int TpPips = 100; // default take profit (pips)
input int ButtonX = 10; // X offset for first button (pixels)
input int ButtonY = 30; // Y offset (pixels)
input int ButtonW = 90; // button width
input int ButtonH = 24; // button height

double cOpen, cClose, cHigh, cLow, cSLPips, cTPPips;

//--- object names
string BTN_BUY = "btn_buy_stop";
string BTN_SELL = "btn_sell_stop";
string BTN_CLOSE = "btn_close_all";

//+------------------------------------------------------------------+
int OnInit() {
   // create buttons on chart using OBJ_BUTTON objects
   CreateButton(BTN_BUY, "Buy Stop", ButtonX, ButtonY);
   CreateButton(BTN_SELL, "Sell Stop", ButtonX + ButtonW + 10, ButtonY);
   CreateButton(BTN_CLOSE, "Close All", ButtonX + 2 * (ButtonW + 10), ButtonY);

   EventSetMillisecondTimer(200);
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // delete buttons
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_CLOSE);
   EventKillTimer();
}

//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y) {
   // if exists, just update
   if (ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   }
   // set properties
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, ButtonW);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, ButtonH);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
void OnTimer() {
   // keep buttons visible on chart refresh (optional)
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id,
   const long & lparam,
      const double & dparam,
         const string & sparam) {
   if (id == CHARTEVENT_OBJECT_CLICK) {
      string obj = sparam;
      if (obj == BTN_BUY)
         PlaceBuyStop();
      else if (obj == BTN_SELL)
         PlaceSellStop();
      else if (obj == BTN_CLOSE)
         CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
void PlaceBuyStop() {

   double digits = (double) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   cOpen = iOpen(NULL, TimeFrame, NumberOfBar);
   cClose = iClose(NULL, TimeFrame, NumberOfBar);
   cHigh = iHigh(NULL, TimeFrame, NumberOfBar);
   cLow = iLow(NULL, TimeFrame, NumberOfBar);
   
   cSLPips = NormalizeDouble(cHigh - cLow, (int) digits);
   cTPPips = cSLPips * cRiskReward;
   
   // place a buy stop at Ask + StopPips
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = cHigh; // multiply by 10 for pip -> point on some FX pairs

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_BUY_STOP;
   request.price = price;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   // stoploss and takeprofit in price terms
   double sl = price - cSLPips;
   double tp = price + cTPPips;
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double digits = (double) SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = NormalizeDouble(bid - StopPips * point * 10, (int) digits);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_SELL_STOP;
   request.price = price;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;

   double sl = price + SlPips * point * 10;
   double tp = price - TpPips * point * 10;
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

//+------------------------------------------------------------------+
// Note: Some brokers and symbols use different point/pip definitions. If the EA
// places orders at unexpected distances, adjust the multiplication factor used
// when converting pips to points (the code currently uses `*10` which is common
// for 5-digit/3-digit brokers). Test the EA in the Strategy Tester or on a demo
// account and tweak StopPips/SlPips/TpPips accordingly.
//+------------------------------------------------------------------+
