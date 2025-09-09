//+------------------------------------------------------------------+
//|                                              Time_Bar_Custom.mq5 |
//|                               Copyright © 2018, Nikolay Kositsin | 
//|                              Khabarovsk,   farria@mail.redcom.ru | 
//+------------------------------------------------------------------+  
#property copyright "Copyright © 2018, Nikolay Kositsin"
#property link "farria@mail.redcom.ru"
//---- номер версии индикатора
#property version "1.9"
//---- отрисовка индикатора в главном окне
#property indicator_chart_window
//---- для расчёта и отрисовки индикатора использовано два буфера
#property indicator_buffers 2
//---- использовано всего одно графическое построение
#property indicator_plots 1
//+----------------------------------------------+
//|  Параметры отрисовки индикатора              |
//+----------------------------------------------+
//---- в качестве индикатора использованы бары гистограммы
#property indicator_type1 DRAW_HISTOGRAM
//---- в качестве цвета линии индикатора использован BlueViolet цвет
#property indicator_color1 clrBlueViolet
//---- линия индикатора - непрерывная кривая
#property indicator_style1 STYLE_DOT
//---- толщина линии индикатора равна 4
#property indicator_width1 1
//---- отображение метки индикатора
#property indicator_label1 "Time_Bar_Custom_Open;Time_Bar_Custom_High;Time_Bar_Custom_Low;Time_Bar_Custom_Close"
//+----------------------------------------------+
//|  Объявление перечисления часов суток         |
//+----------------------------------------------+
enum HOURS {
   ENUM_HOUR_0 = 0, //0
      ENUM_HOUR_1, //1
      ENUM_HOUR_2, //2
      ENUM_HOUR_3, //3
      ENUM_HOUR_4, //4
      ENUM_HOUR_5, //5
      ENUM_HOUR_6, //6
      ENUM_HOUR_7, //7
      ENUM_HOUR_8, //8
      ENUM_HOUR_9, //9
      ENUM_HOUR_10, //10
      ENUM_HOUR_11, //11   
      ENUM_HOUR_12, //12
      ENUM_HOUR_13, //13
      ENUM_HOUR_14, //14
      ENUM_HOUR_15, //15
      ENUM_HOUR_16, //16
      ENUM_HOUR_17, //17
      ENUM_HOUR_18, //18
      ENUM_HOUR_19, //19
      ENUM_HOUR_20, //20
      ENUM_HOUR_21, //21  
      ENUM_HOUR_22, //22
      ENUM_HOUR_23 //23    
};
//+----------------------------------------------+
//|  Объявление перечисления минут часов         |
//+----------------------------------------------+
enum MINUTS {
   ENUM_MINUT_0 = 0, //0
      ENUM_MINUT_1, //1
      ENUM_MINUT_2, //2
      ENUM_MINUT_3, //3
      ENUM_MINUT_4, //4
      ENUM_MINUT_5, //5
      ENUM_MINUT_6, //6
      ENUM_MINUT_7, //7
      ENUM_MINUT_8, //8
      ENUM_MINUT_9, //9
      ENUM_MINUT_10, //10
      ENUM_MINUT_11, //11   
      ENUM_MINUT_12, //12
      ENUM_MINUT_13, //13
      ENUM_MINUT_14, //14
      ENUM_MINUT_15, //15
      ENUM_MINUT_16, //16
      ENUM_MINUT_17, //17
      ENUM_MINUT_18, //18
      ENUM_MINUT_19, //19
      ENUM_MINUT_20, //20
      ENUM_MINUT_21, //21  
      ENUM_MINUT_22, //22
      ENUM_MINUT_23, //23
      ENUM_MINUT_24, //24
      ENUM_MINUT_25, //25
      ENUM_MINUT_26, //26
      ENUM_MINUT_27, //27
      ENUM_MINUT_28, //28
      ENUM_MINUT_29, //29
      ENUM_MINUT_30, //30
      ENUM_MINUT_31, //31  
      ENUM_MINUT_32, //32
      ENUM_MINUT_33, //33
      ENUM_MINUT_34, //34
      ENUM_MINUT_35, //35
      ENUM_MINUT_36, //36
      ENUM_MINUT_37, //37
      ENUM_MINUT_38, //38
      ENUM_MINUT_39, //39 
      ENUM_MINUT_40, //40
      ENUM_MINUT_41, //41  
      ENUM_MINUT_42, //42
      ENUM_MINUT_43, //43
      ENUM_MINUT_44, //44
      ENUM_MINUT_45, //45
      ENUM_MINUT_46, //46
      ENUM_MINUT_47, //47
      ENUM_MINUT_48, //48
      ENUM_MINUT_49, //49
      ENUM_MINUT_50, //50
      ENUM_MINUT_51, //51  
      ENUM_MINUT_52, //52
      ENUM_MINUT_53, //53
      ENUM_MINUT_54, //54
      ENUM_MINUT_55, //55
      ENUM_MINUT_56, //56
      ENUM_MINUT_57, //57
      ENUM_MINUT_58, //58
      ENUM_MINUT_59 //59             
};
//+----------------------------------------------+
//| Входные параметры индикатора                 |
//+----------------------------------------------+
input HOURS BarHours = ENUM_HOUR_8; //Время установки бара (Часы)
input MINUTS BarMinuts = ENUM_MINUT_0; //Время установки бара (Минуты)
//+----------------------------------------------+

//---- объявление динамических массивов, которые будут в  дальнейшем использованы в качестве индикаторных буферов
double ExtUpBuffer[], ExtDnBuffer[];
//---
int min_rates_total;
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
   //---- инициализация глобальных переменных 
   min_rates_total = 2;

   //---- превращение динамических массивов в индикаторные буферы
   SetIndexBuffer(0, ExtUpBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ExtDnBuffer, INDICATOR_DATA);
   //---- осуществление сдвига начала отсчёта отрисовки индикатора 1
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, min_rates_total);
   //---- установка значений индикатора, которые не будут видимы на графике
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   //---- запрет на отображение значений индикатора в левом верхнем углу окна индикатора
   PlotIndexSetInteger(0, PLOT_SHOW_DATA, false);
   //---- индексация элементов в буферах как в таймсериях   
   ArraySetAsSeries(ExtUpBuffer, true);
   ArraySetAsSeries(ExtDnBuffer, true);
   //---- Установка формата точности отображения индикатора
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   //---- имя для окон данных и лэйба для субъокон 
   string short_name = "Time_Bar_Custom(" + string(BarHours) + ":" + string(BarMinuts) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   //---- завершение инициализации
   return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//|  проверка бара на момент времени                                 |
//+------------------------------------------------------------------+   
bool CheckVLinePoint(datetime bartime1, datetime bartime0)
//+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+
{
   //----
   MqlDateTime tm0, tm1;
   TimeToStruct(bartime0, tm0);
   TimeToStruct(bartime1, tm1);
   //----
   if (tm0.hour == BarHours && tm0.min == BarMinuts) return (true);
   //----
   if (!BarMinuts) {
      if (tm0.day_of_year == tm1.day_of_year)
         if (tm1.hour < BarHours && tm0.hour > BarHours) return (true);
      if (tm0.day_of_year != tm1.day_of_year)
         if (tm0.hour >= BarHours) return (true);
   }
   //----
   if (BarMinuts) {
      if (tm0.hour == BarHours && tm1.min < BarMinuts && tm0.min >= BarMinuts) return (true);
      if (tm0.day_of_year == tm1.day_of_year && tm1.hour < BarHours && tm0.hour > BarHours) return (true);
      if (tm0.day_of_year != tm1.day_of_year)
         if (tm0.hour > BarHours) return (true);
   }
   //----
   return (false);
}
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   //---- проверка количества баров на достаточность для расчёта
   if (rates_total < min_rates_total) return (0);

   //---- объявления локальных переменных    
   int limit;

   //---- расчёт стартового номера limit для цикла пересчёта баров и стартовая инициализация переменных
   if (prev_calculated > rates_total || prev_calculated <= 0) // проверка на первый старт расчёта индикатора
   {
      limit = rates_total - min_rates_total; // стартовый номер для расчёта всех баров
   } else {
      limit = rates_total - prev_calculated; // стартовый номер для расчёта новых баров
   }

   //---- индексация элементов в массивах как в таймсериях  
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   //---- основной цикл расчёта индикатора
   for (int bar = limit; bar >= 0 && !IsStopped(); bar--) {
      ExtUpBuffer[bar] = EMPTY_VALUE;
      ExtDnBuffer[bar] = EMPTY_VALUE;
      if (CheckVLinePoint(time[bar + 1], time[bar])) {
         ExtUpBuffer[bar] = 10 * high[bar];
         ExtDnBuffer[bar] = NULL;
      }
   }
   //---           
   return (rates_total);
}
//+------------------------------------------------------------------+
