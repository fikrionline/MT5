//+------------------------------------------------------------------+
//|          Auto Fibo H1 Open High/Low.mq5                          |
//|   Fibo from Highest H1 Open (0%) to Lowest H1 Open (100%)        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0 // No plots, only objects

input int DaysBack = 2;
input color FiboHLineColor = clrDarkGreen;   // Horizontal Line Color
input int DaySkip1 = 3; // Skip Day 1
input int DaySkip2 = 4; // Skip Day 2
input color FiboColor = clrDimGray; // Fibo Color
input int FiboWidth = 1; // Line With
input int FiboStyle = STYLE_SOLID; // Line Style
input ENUM_TIMEFRAMES FiboTF = PERIOD_H1; // Time Frame

datetime day_start, day_end;
double highestOpen, lowestOpen;
string fiboName = "FiboOpenHighLow";

string fiboNameShift;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+

int OnInit() {
   for (int d = 0; d < DaysBack; d++) {
      fiboNameShift = fiboName + IntegerToString(d);
      if (ObjectFind(0, fiboNameShift) >= 0) {
         ObjectDelete(0, fiboNameShift);
      }
   }
   return (INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
   for (int d = 0; d < DaysBack; d++) {
      fiboNameShift = fiboName + IntegerToString(d);
      if (ObjectFind(0, fiboNameShift) >= 0) {
         ObjectDelete(0, fiboNameShift);
      }
      FiboLevelsDelete(0, fiboNameShift);
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
   const int prev_calculated,
      const datetime & time[],
         const double & open[],
            const double & high[],
               const double & low[],
                  const double & close[],
                     const long & tick_volume[],
                        const long & volume[],
                           const int & spread[]) {
   //--- determine selected day boundaries
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0;
   t.min = 0;
   t.sec = 0;
   datetime todayStart = StructToTime(t);

   for (int d = 0; d < DaysBack; d++) {
      if (d == DaySkip1) {

      } else if (d == DaySkip2) {

      } else {
         //--- get H1 rates for the selected day
         MqlRates rates[];
         fiboNameShift = fiboName + IntegerToString(d);
         day_start = todayStart - 86400 * (d);
         day_end = todayStart - 86400 * (d - 1);

         //--- get H1 rates for the selected day
         if (CopyRates(_Symbol, FiboTF, day_start, day_end, rates) <= 0)
            return prev_calculated;

         highestOpen = -DBL_MAX;
         lowestOpen = DBL_MAX;

         for (int i = 0; i < ArraySize(rates); i++) {
            if (rates[i].open > highestOpen) highestOpen = rates[i].open;
            if (rates[i].open < lowestOpen) lowestOpen = rates[i].open;
         }

         if (highestOpen == -DBL_MAX || lowestOpen == DBL_MAX)
            return prev_calculated;

         //--- create/update fibo object
         if (ObjectFind(0, fiboNameShift) < 0) {
            ObjectCreate(0, fiboNameShift, OBJ_FIBO, 0, day_start, highestOpen, day_end, lowestOpen);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_LEVELCOLOR, 0, FiboHLineColor);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_LEVELCOLOR, 1, FiboHLineColor);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_COLOR, FiboColor);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_STYLE, FiboStyle);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_WIDTH, FiboWidth);
            ObjectSetInteger(0, fiboNameShift, OBJPROP_RAY_RIGHT, true);

            // set only 2 levels: 0% and 100%
            ObjectSetInteger(0, fiboNameShift, OBJPROP_LEVELS, 2);

            ObjectSetDouble(0, fiboNameShift, OBJPROP_LEVELVALUE, 0, 0.0);
            ObjectSetString(0, fiboNameShift, OBJPROP_LEVELTEXT, 0, "L" + IntegerToString(d) + " = %$  ");

            ObjectSetDouble(0, fiboNameShift, OBJPROP_LEVELVALUE, 1, 1.0);
            ObjectSetString(0, fiboNameShift, OBJPROP_LEVELTEXT, 1, "H" + IntegerToString(d) + " = %$  ");
         } else {
            // update anchors if already created
            ObjectMove(0, fiboNameShift, 0, day_start, highestOpen);
            ObjectMove(0, fiboNameShift, 1, day_end, lowestOpen);
         }
      }
   }

   return (rates_total);
}
//+------------------------------------------------------------------+

bool FiboLevelsDelete(const long chart_ID = 0, // ID графика 
   const string name = "FiboLevels") // имя объекта 
{
   //--- сбросим значение ошибки 
   ResetLastError();
   //--- удалим объект 
   if (!ObjectDelete(chart_ID, name)) {
      Print(__FUNCTION__,
         ": не удалось удалить \"Уровни Фибоначчи\"! Код ошибки = ", GetLastError());
      return (false);
   }
   //--- успешное выполнение 
   return (true);
}
