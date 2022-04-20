//+------------------------------------------------------------------+
//|                                                      Binario.mq5 |
//|                             Copyright © 2008-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                    Based on the EA by don_forex. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Binario/"
#property version   "1.01"

#property description "Uses a band of two same period MAs - one over High prices, one over Low prices."
#property description "A breakout from within the bands triggers a trade."

input group "Main"
input int MA_Period = 144; // MA Period
input ENUM_MA_METHOD MA_Method = MODE_EMA; // MA Method
input int TakeProfit = 115;
input int PipDifference = 20; // PipDifference: distance from MA for breakout.
input group "Money management"
input double Lots = 0.1; // Lots: Fixed position size.
input double MaximumRisk = 2; // MaximumRisk: Position sizing increase coefficient. 0 - disable.
input group "Miscellaneous"
input int Slippage = 3;
input string OrderCommentary = "Binario";
input int Magic = 16384;

#include <Trade/Trade.mqh>

CTrade *Trade;

double Poin;

int MA_High_Handle, MA_Low_Handle;

void OnInit()
{
    // Checking for unconventional Point digits number.
    if (_Point == 0.00001) Poin = 0.0001; // 5 digits.
    else if (_Point == 0.001) Poin = 0.01; // 3 digits.
    else Poin = _Point; // Normal.
    
    MA_High_Handle = iMA(Symbol(), Period(), MA_Period, 0, MA_Method, PRICE_HIGH);
    MA_Low_Handle = iMA(Symbol(), Period(), MA_Period, 0, MA_Method, PRICE_LOW);
    
    Trade = new CTrade;
    Trade.SetDeviationInPoints(Slippage);
    Trade.SetExpertMagicNumber(Magic);
}

void OnDeinit(const int reason)
{
    delete Trade;
}

void OnTick()
{
    if (Bars(Symbol(), Period()) < 144)
    {
        Print("Fewer than 144 bars on the chart. Trading disabled.");
        return;
    }

    // Get the current MA over High prices value.
    double buf[];
    int copied;
    copied = CopyBuffer(MA_High_Handle, 0, 0, 1, buf);
    if (copied != 1)
    {
        Print("MA buffers aren't ready yet.");
        return;
    }
    double MA144H = buf[0];
    // Get the current MA over Low prices value.
    copied = CopyBuffer(MA_Low_Handle, 0, 0, 1, buf);
    if (copied != 1)
    {
        Print("MA buffers aren't ready yet.");
        return;
    }
    double MA144L = buf[0];
    
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double Spread = Ask - Bid;

    double BuyPrice       = NormalizeDouble(MA144H + Spread + PipDifference * Poin, _Digits);
    double BuyStopLoss    = NormalizeDouble(MA144L - Poin, _Digits);
    double BuyTakeProfit  = NormalizeDouble(MA144H + (PipDifference + TakeProfit) * Poin, _Digits);
    double SellPrice      = NormalizeDouble(MA144L - (PipDifference) * Poin, _Digits);
    double SellStopLoss   = NormalizeDouble(MA144H + Spread + Poin, _Digits);
    double SellTakeProfit = NormalizeDouble(MA144L - Spread - (PipDifference + TakeProfit) * Poin, _Digits);

    double Lot = Lots;
    if (MaximumRisk > 0) // Use increasing position size.
    {
        int LotStep_digits = CountDecimalPlaces(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
        Lot = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * MaximumRisk / 50000, LotStep_digits);
    }
    if (Lot < SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN)) Lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if (Lot > SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX)) Lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);

    bool need_long  = true;
    bool need_short = true;

    int ord_total = OrdersTotal();
    for (int cnt = 0; cnt < ord_total; cnt++)
    {
        ulong ticket = OrderGetTicket(cnt);
        if (ticket == 0)
        {
            Print("OrderGetTicket() failed. Error: ", GetLastError());
            continue;
        }
        if (!OrderSelect(ticket))
        {
            Print("OrderSelect() failed. Error: ", GetLastError());
            continue;
        }
        if ((OrderGetString(ORDER_SYMBOL) != Symbol()) || (OrderGetInteger(ORDER_MAGIC) != Magic)) continue;

        if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
        {
            need_long = false;
            if (OrderGetDouble(ORDER_SL) != BuyStopLoss)
            {
                Trade.OrderModify(ticket, BuyPrice, BuyStopLoss, BuyTakeProfit, ORDER_TIME_GTC, 0);
            }
        }
        if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
        {
            need_short = false;
            if (OrderGetDouble(ORDER_SL) != SellStopLoss)
            {
                Trade.OrderModify(ticket, SellPrice, SellStopLoss, SellTakeProfit, ORDER_TIME_GTC, 0);
            }
        }
    }
    
    int pos_total = PositionsTotal();
    for (int cnt = 0; cnt < pos_total; cnt++)
    {
        ulong ticket = PositionGetTicket(cnt);
        if (ticket == 0)
        {
            Print("PositionGetTicket() failed. Error: ", GetLastError());
            continue;
        }
        if (!PositionSelectByTicket(ticket))
        {
            Print("PositionSelectByTicket() failed. Error: ", GetLastError());
            continue;
        }
        if ((PositionGetString(POSITION_SYMBOL) != Symbol()) || (PositionGetInteger(POSITION_MAGIC) != Magic)) continue;
        
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            need_long = false;
            if (PositionGetDouble(POSITION_SL) < BuyStopLoss)
            {
                Trade.PositionModify(ticket, BuyStopLoss, BuyTakeProfit);
            }
            return;
        }
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            need_short = false;
            if (PositionGetDouble(POSITION_SL) > SellStopLoss)
            {
                Trade.PositionModify(ticket, SellStopLoss, SellTakeProfit);
            }
            return;
        }
    }

    if (AccountInfoDouble(ACCOUNT_MARGIN_FREE) < 1000 * Lot)
    {
        Print("No money. Free Margin = ", AccountInfoDouble(ACCOUNT_MARGIN_FREE));
        return;
    }

    if ((Bid < MA144H) && (Bid > MA144L)) // Inside the MA bands.
    {
        if (need_long)
        {
            Trade.OrderOpen(Symbol(), ORDER_TYPE_BUY_STOP, Lot, 0, BuyPrice, BuyStopLoss, BuyTakeProfit, ORDER_TIME_GTC, 0, OrderCommentary); 
        }
        if(need_short)
        {
            Trade.OrderOpen(Symbol(), ORDER_TYPE_SELL_STOP, Lot, 0, SellPrice, SellStopLoss, SellTakeProfit, ORDER_TIME_GTC, 0, OrderCommentary); 
        }
    }
}

//+------------------------------------------------------------------+
//| Counts decimal places.                                           |
//+------------------------------------------------------------------+
int CountDecimalPlaces(double number)
{
    // 100 as maximum length of number.
    for (int i = 0; i < 100; i++)
    {
        double pwr = MathPow(10, i);
        if (MathRound(number * pwr) / pwr == number) return i;
    }
    return -1;
}
//+------------------------------------------------------------------+