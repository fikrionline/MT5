//+------------------------------------------------------------------+
//|                                             CandleSeries_v2.mq5  |
//|                      © 2025 YourName                             |
//|  Marks candles when there are X consecutive bullish or bearish   |
//+------------------------------------------------------------------+
#property copyright "© 2025 YourName"
#property version   "1.03"
#property indicator_chart_window
#property indicator_plots 2       // <--- Define 2 plots (bullish + bearish)
#property indicator_buffers 2

//---- input parameters
input int  ConsecutiveCandles = 5;       // Number of consecutive candles
input color BullMarkColor      = clrLime;// Color for bullish sequence
input color BearMarkColor      = clrRed; // Color for bearish sequence
input int  MarkSize            = 2;      // Arrow size
input int  BullArrow           = 241;    // Up arrow symbol (Wingdings)
input int  BearArrow           = 242;    // Down arrow symbol (Wingdings)

//---- indicator buffers
double BullBuffer[];
double BearBuffer[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Candle Series Mark (" + IntegerToString(ConsecutiveCandles) + ")");

   // Plot 0 - Bullish series
   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, BullArrow);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, BullMarkColor);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MarkSize);
   PlotIndexSetString(0, PLOT_LABEL, "Bullish Series");

   // Plot 1 - Bearish series
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_ARROW, BearArrow);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, BearMarkColor);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MarkSize);
   PlotIndexSetString(1, PLOT_LABEL, "Bearish Series");

   ArrayInitialize(BullBuffer, EMPTY_VALUE);
   ArrayInitialize(BearBuffer, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],        // must be included
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < ConsecutiveCandles) return(0);

   int start = (prev_calculated > ConsecutiveCandles) ? prev_calculated - 1 : ConsecutiveCandles - 1;
   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = pointSize * 10.0;

   for(int i = start; i < rates_total; i++)
   {
      bool allBull = true;
      bool allBear = true;

      for(int j = 0; j < ConsecutiveCandles; j++)
      {
         int idx = i - j;
         if(idx < 0) break;

         if(close[idx] <= open[idx]) allBull = false;
         if(close[idx] >= open[idx]) allBear = false;
      }

      if(allBull)
      {
         BullBuffer[i] = low[i] - offset;  // mark below
         BearBuffer[i] = EMPTY_VALUE;
      }
      else if(allBear)
      {
         BearBuffer[i] = high[i] + offset; // mark above
         BullBuffer[i] = EMPTY_VALUE;
      }
      else
      {
         BullBuffer[i] = EMPTY_VALUE;
         BearBuffer[i] = EMPTY_VALUE;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
