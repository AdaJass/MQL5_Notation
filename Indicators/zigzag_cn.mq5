
/*让我们首先定义一个波， 这里其实是传统的一个正/余弦 周期的一个 半周期，或者说半波。 
就是传统意义上的半波我们定义为一个波
struct WAVE{
    int direction;
    int left_index;
    int middle_index; //中间点index 如果 direction==1，是波峰， direction==-1 是波谷
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
input int InpDepth = 12;    // 寻波窗口长度
input int InpDeviation = 5; // 波高最小值
input int InpBackstep = 3;  // 最小半波长
//--- indicator buffers
double ZigZagBuffer[];  // 指标数组
double HighMapBuffer[]; // 保存满足寻波条件的高点的数组
double LowMapBuffer[];  // 保存满足寻波条件的低点的数组

int ExtRecalc = 3; // 重新计算的波节点数

enum EnSearchMode  //类似于波方向的一个标记
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
        //--- 至少重新计算100个柱子 或 至少ExtRecalc个波节点
        while (extreme_counter < ExtRecalc && i > rates_total - 100)
        {
            res = ZigZagBuffer[i];
            if (res != 0.0)
                extreme_counter++;
            i--;
        }
        i++;
        start = i;

        //---如果当前波节点是个低点，那么接下来将寻找Peak=>高点
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
        //--- 清除从第ExtRecalc个节点开始往后的信息
        for (i = start + 1; i < rates_total && !IsStopped(); i++)
        {
            ZigZagBuffer[i] = 0.0;
            LowMapBuffer[i] = 0.0;
            HighMapBuffer[i] = 0.0;
        }
    }

    //--- 找符合条件的波，保存在两个候选数组里。
    for (shift = start; shift < rates_total && !IsStopped(); shift++)
    {
        //--- 找下降波
        val = low[Lowest(low, InpDepth, shift)];  //按窗口大小找最低点.
        if (val == last_low) //上次和这次都找到一样的地点，直接跳到找上升波
            val = 0.0;
        else  //下面的代码保证波谷满足两个条件之一： 
        {     //1. 波谷深度大于 InpDeviation * _Point  2. 半波长大于 InpBackstep
            last_low = val;
            if ((low[shift] - val) > InpDeviation * _Point) //波深满足条件，直接跳过找下降波部分
                val = 0.0;
            else //波深不满足条件
            {
                for (back = 1; back <= InpBackstep; back++)//该循环判断波长是否满足条件，如果波长不满足，意味着两个条件都不满足，那么这不是合格的候选者
                {
                    res = LowMapBuffer[shift - back];
                    if ((res != 0) && (res > val))
                        LowMapBuffer[shift - back] = 0.0;
                }
            }
        }
        if (low[shift] == val) //当前shift如果是最低点，那么记录。 这里这样实现其实不太好，这里记录的时候还没看到波的形成。
            LowMapBuffer[shift] = val; //相当于这里提前记录，然后后继看如果这里的记录满足寻波条件，那么保留，如果不满足再清除。其实很简单的事，被搞复杂了
        else
            LowMapBuffer[shift] = 0.0;
        //--- 找上升波
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
    //现在LowMapBuffer保存了满足寻波条件的所有低点，寻波条件是：
    //{[(波深大于 InpDeviation * _Point) || (半波长大于 InpBackstep)] && (该下降波是由InpDepth的寻波窗口找出来的)} || 窗口范围内只有一个波
    //概括点说就是，如果窗口内只找到一个波，那直接跳过，只有找到多于一个波时，才进行进一步波筛选步骤。
    //HighMapBuffer 逻辑类似    
    //在上面的代码中，把最近的一个波的节点信息清除了，其实只清除最后两个节点信息，但是新波的左节点也是要重新确定的。
    //并且 extreme_search 已经保存了接下来我们要找的是上升波还是下降波
    //所有很明显，接下来我们要从候选节点数组中找到最合适的这3个节点    
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