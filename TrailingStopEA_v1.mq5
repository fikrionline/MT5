//+------------------------------------------------------------------+
//|                Trailing Stop EA (MT5)                           |
//|                Author: ChatGPT (2025)                           |
//+------------------------------------------------------------------+
#property copyright "ChatGPT"
#property version   "1.00"
#property strict

//--- input settings
input int TrailingStop = 200;   // Trailing Stop in points
input int TrailingStep = 50;    // Step in points (to avoid too many modifications)

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   Print("Trailing Stop EA started. Trailing: ", TrailingStop, " points");
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Loop through all open positions
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double stopLoss = PositionGetDouble(POSITION_SL);
         double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
         long type = PositionGetInteger(POSITION_TYPE);

         // Point & Digits
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

         // Trailing logic for BUY
         if (type == POSITION_TYPE_BUY) {
            double newStop = currentPrice - TrailingStop * point;
            if (currentPrice - openPrice > TrailingStop * point) // in profit
            {
               if (stopLoss < newStop - TrailingStep * point || stopLoss == 0.0) {
                  ModifyPosition(ticket, newStop);
               }
            }
         }

         // Trailing logic for SELL
         if (type == POSITION_TYPE_SELL) {
            double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
            double newStop = askPrice + TrailingStop * point;
            if (openPrice - askPrice > TrailingStop * point) // in profit
            {
               if (stopLoss > newStop + TrailingStep * point || stopLoss == 0.0) {
                  ModifyPosition(ticket, newStop);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify position SL                                               |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl) {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   if (!PositionSelectByTicket(ticket))
      return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   double tp = PositionGetDouble(POSITION_TP);

   request.action = TRADE_ACTION_SLTP;
   request.symbol = symbol;
   request.sl = NormalizeDouble(sl, (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   request.tp = tp;
   request.position = ticket;

   if (!OrderSend(request, result)) {
      Print("ModifyPosition failed. Code: ", result.retcode);
   } else {
      Print("Trailing stop updated. Ticket: ", ticket, " | New SL: ", request.sl);
   }
}
//+------------------------------------------------------------------+
