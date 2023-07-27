//Let's define a WAVE structure
/*
struct WAVE{
    int direction;  
    int left_index;
    int middle_index; //direction==1, this index is a peak; direction==-1 is a bottom
    int right_index;        
    double left_price;
    double middle_price;
    double right_price;  
}
*/
#property copyright "Copyright 2000-2023, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 1
//--- plot ZigZag
#property indicator_label1 "ZigZag"
#property indicator_type1 DRAW_SECTION
#property indicator_color1 clrRed
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1
//--- input parameters
input int InpDepth = 12;    // Find wave window length
input int InpDeviation = 5; // min wave high
input int InpBackstep = 3;  // min half-wave length
//--- indicator buffers
double ZigZagBuffer[];  // main buffer
double HighMapBuffer[]; // ZigZag high candidate (peaks)
double LowMapBuffer[];  // ZigZag low candidate (bottoms)

int ExtRecalc = 3; // number of last wave key points for recalculation

enum EnSearchMode
{
    Extremum = 0, // searching for the first extremum
    Peak = 1,     // searching for the next ZigZag peak
    Bottom = -1   // searching for the next ZigZag bottom
};
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
{
    //--- indicator buffers mapping
    SetIndexBuffer(0, ZigZagBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, HighMapBuffer, INDICATOR_CALCULATIONS);
    SetIndexBuffer(2, LowMapBuffer, INDICATOR_CALCULATIONS);
    //--- set short name and digits
    string short_name = StringFormat("ZigZag(%d,%d,%d)", InpDepth, InpDeviation, InpBackstep);
    IndicatorSetString(INDICATOR_SHORTNAME, short_name);
    PlotIndexSetString(0, PLOT_LABEL, short_name);
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
    //--- set an empty value
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
}
//+------------------------------------------------------------------+
//| ZigZag calculation                                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (rates_total < 100)
        return (0);
    //---
    int i = 0;
    int start = 0, extreme_counter = 0, extreme_search = Extremum;
    int shift = 0, back = 0, last_high_pos = 0, last_low_pos = 0;
    double val = 0, res = 0;
    double curlow = 0, curhigh = 0, last_high = 0, last_low = 0;
    //--- initializing
    if (prev_calculated == 0)
    {
        ArrayInitialize(ZigZagBuffer, 0.0);
        ArrayInitialize(HighMapBuffer, 0.0);
        ArrayInitialize(LowMapBuffer, 0.0);
        start = InpDepth;
    }

    //--- ZigZag was already calculated before
    if (prev_calculated > 0)
    {
        i = rates_total - 1;
        //--- searching for the third extremum from the last uncompleted bar
        while (extreme_counter < ExtRecalc && i > rates_total - 100)
        {
            res = ZigZagBuffer[i];
            if (res != 0.0)
                extreme_counter++;
            i--;
        }
        i++;
        start = i;

        //--- what type of exremum we search for
        if (LowMapBuffer[i] != 0.0)
        {
            curlow = LowMapBuffer[i];
            extreme_search = Peak;
        }
        else
        {
            curhigh = HighMapBuffer[i];
            extreme_search = Bottom;
        }
        //--- clear indicator values
        for (i = start + 1; i < rates_total && !IsStopped(); i++)
        {
            ZigZagBuffer[i] = 0.0;
            LowMapBuffer[i] = 0.0;
            HighMapBuffer[i] = 0.0;
        }
    }

    //--- searching for high and low extremes
    for (shift = start; shift < rates_total && !IsStopped(); shift++)
    {
        //--- find bottom candidate wave
        val = low[Lowest(low, InpDepth, shift)];  //find lowest from shift-InpDepth to shift.
        if (val == last_low) //if the last loop and the current loop find the same value, it means we find only one wave, just jump to find peak.
            val = 0.0;
        else  //below code is ensure that a bottom must meet one of the two addition conditions: 
        {     //1. bottom depth larger than InpDeviation * _Point  2. bottom have length more than InpBackstep
            last_low = val;
            if ((low[shift] - val) > InpDeviation * _Point) //the wave meet condition 1, just jump to find peak
                val = 0.0;
            else //condition 1 isn't meet
            {
                for (back = 1; back <= InpBackstep; back++)// ensure condition 2 is meet, otherwise the point will be cleaned
                {
                    res = LowMapBuffer[shift - back];
                    if ((res != 0) && (res > val))
                        LowMapBuffer[shift - back] = 0.0;
                }
            }
        }
        if (low[shift] == val) //if current shift is the lowest, record it. I think it is not a good way of the implementation.
            LowMapBuffer[shift] = val; //It makes things more complicated. It records the point before we can see the wave is formed.
        else                           //and if the point meet the wave-condition later, it will be reserved, else cleared.
            LowMapBuffer[shift] = 0.0;

        //--- find peak candidate wave
        val = high[Highest(high, InpDepth, shift)];
        if (val == last_high)
            val = 0.0;
        else
        {
            last_high = val;
            if ((val - high[shift]) > InpDeviation * _Point)
                val = 0.0;
            else
            {
                for (back = 1; back <= InpBackstep; back++)
                {
                    res = HighMapBuffer[shift - back];
                    if ((res != 0) && (res < val))
                        HighMapBuffer[shift - back] = 0.0;
                }
            }
        }
        if (high[shift] == val)
            HighMapBuffer[shift] = val;
        else
            HighMapBuffer[shift] = 0.0;
    }
    //now we get the LowMapBuffer which only store the bottom meet conditions: 
    //{[(wave depth deeper than InpDeviation * _Point) || (wave half-length more than InpBackstep)] && (the wave is finded by a InpDepth window)} || (It is the only wave of the window)
    //The above condition show that if in the window we find more than one wave, it will fall into a complicated logic to filter waves.
    //The same as HighMapBuffer
    //in the above code, the latest WAVE is cleared and we must re-find it from the two candidate arrays, in fact the left point of the lates wave is not cleared, but will also re-find.
    //And the extreme_search will indicates what direction the to-find wave is.
    //It is clear that what will we do is to re-peak the best left point, middle point and right point.    
    //--- set last values
    if (extreme_search == 0) // undefined values
    {
        last_low = 0.0;
        last_high = 0.0;
    }
    else
    {
        last_low = curlow;
        last_high = curhigh;
    }

    //--- final selection of extreme points for ZigZag
    for (shift = start; shift < rates_total && !IsStopped(); shift++)
    {
        res = 0.0;
        switch (extreme_search)
        {
        case Extremum:
            if (last_low == 0.0 && last_high == 0.0)
            {
                if (HighMapBuffer[shift] != 0)
                {
                    last_high = high[shift];
                    last_high_pos = shift;
                    extreme_search = Bottom;
                    ZigZagBuffer[shift] = last_high;
                    res = 1;
                }
                if (LowMapBuffer[shift] != 0.0)
                {
                    last_low = low[shift];
                    last_low_pos = shift;
                    extreme_search = Peak;
                    ZigZagBuffer[shift] = last_low;
                    res = 1;
                }
            }
            break;
        case Peak:
            if (LowMapBuffer[shift] != 0.0 && LowMapBuffer[shift] < last_low && HighMapBuffer[shift] == 0.0)
            {
                ZigZagBuffer[last_low_pos] = 0.0;
                last_low_pos = shift;
                last_low = LowMapBuffer[shift];
                ZigZagBuffer[shift] = last_low;
                res = 1;
            }
            if (HighMapBuffer[shift] != 0.0 && LowMapBuffer[shift] == 0.0)
            {
                last_high = HighMapBuffer[shift];
                last_high_pos = shift;
                ZigZagBuffer[shift] = last_high;
                extreme_search = Bottom;
                res = 1;
            }
            break;
        case Bottom:
            if (HighMapBuffer[shift] != 0.0 && HighMapBuffer[shift] > last_high && LowMapBuffer[shift] == 0.0)
            {
                ZigZagBuffer[last_high_pos] = 0.0;
                last_high_pos = shift;
                last_high = HighMapBuffer[shift];
                ZigZagBuffer[shift] = last_high;
            }
            if (LowMapBuffer[shift] != 0.0 && HighMapBuffer[shift] == 0.0)
            {
                last_low = LowMapBuffer[shift];
                last_low_pos = shift;
                ZigZagBuffer[shift] = last_low;
                extreme_search = Peak;
            }
            break;
        default:
            return (rates_total);
        }
    }

    //--- return value of prev_calculated for next call
    return (rates_total);
}
//+------------------------------------------------------------------+
//|  Search for the index of the highest bar                         |
//+------------------------------------------------------------------+
int Highest(const double &array[], const int depth, const int start)
{
    if (start < 0)
        return (0);

    double max = array[start];
    int index = start;
    //--- start searching
    for (int i = start - 1; i > start - depth && i >= 0; i--)
    {
        if (array[i] > max)
        {
            index = i;
            max = array[i];
        }
    }
    //--- return index of the highest bar
    return (index);
}
//+------------------------------------------------------------------+
//|  Search for the index of the lowest bar                          |
//+------------------------------------------------------------------+
int Lowest(const double &array[], const int depth, const int start)
{
    if (start < 0)
        return (0);

    double min = array[start];
    int index = start;
    //--- start searching
    for (int i = start - 1; i > start - depth && i >= 0; i--)
    {
        if (array[i] < min)
        {
            index = i;
            min = array[i];
        }
    }
    //--- return index of the lowest bar
    return (index);
}
//+------------------------------------------------------------------+