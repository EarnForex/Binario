//+------------------------------------------------------------------+
//|                                                      Binario.mq4 |
//|                             Copyright © 2008-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                    Based on the EA by don_forex. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Binario/"
#property version   "1.01"
#property strict

#property description "Uses a band of two same period MAs - one over High prices, one over Low prices."
#property description "A breakout from within the bands triggers a trade."

input group "Main"
input int MA_Period = 144; // MA Period
input ENUM_MA_METHOD MA_Method = MODE_EMA; // MA Method
input int TakeProfit = 100;
input int PipDifference = 25; // PipDifference: distance from MA for breakout.
input group "Money management"
input double Lots = 0.1; // Lots: Fixed position size.
input double MaximumRisk = 2; // MaximumRisk: Position sizing increase coefficient. 0 - disable.
input group "Miscellaneous"
input int Slippage = 3;
input string OrderCommentary = "Binario";
input int Magic = 16384;

double Poin;

void OnInit()
{
    // Checking for unconvetional Point digits number.
    if (Point == 0.00001) Poin = 0.0001; // 5 digits.
    else if (Point == 0.001) Poin = 0.01; // 3 digits.
    else Poin = Point; // Normal.
}

void OnTick()
{
    if (Bars(Symbol(), Period()) < 144)
    {
        Print("Fewer than 144 bars on the chart. Trading disabled.");
        return;
    }

    double MA144H = MathRound(iMA(NULL, 0, 144, 0, MODE_EMA, PRICE_HIGH, 0) / Poin) * Poin;
    double MA144L = MathRound(iMA(NULL, 0, 144, 0, MODE_EMA, PRICE_LOW, 0) / Poin) * Poin;

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

    int total = OrdersTotal();
    for (int cnt = 0; cnt < total; cnt++)
    {
        if (!OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES))
        {
            Print("OrderSelect() failed. Error: ", GetLastError());
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if (OrderType() == OP_BUYSTOP)
        {
            need_long = false;
            if (OrderStopLoss() != BuyStopLoss)
            {
                if (!OrderModify(OrderTicket(), BuyPrice, BuyStopLoss, BuyTakeProfit, 0))
                {
                    Print("OrderModify() failed. Error: ", GetLastError());
                }
            }
        }
        else if (OrderType() == OP_SELLSTOP)
        {
            need_short = false;
            if (OrderStopLoss() != SellStopLoss)
            {
                if (!OrderModify(OrderTicket(), SellPrice, SellStopLoss, SellTakeProfit, 0))
                {
                    Print("OrderModify() failed. Error: ", GetLastError());
                }
            }
        }
        else if (OrderType() == OP_BUY)
        {
            need_long = false;
            if (OrderStopLoss() < BuyStopLoss)
            {
                if (!OrderModify(OrderTicket(), OrderOpenPrice(), BuyStopLoss, BuyTakeProfit, 0))
                {
                    Print("OrderModify() failed. Error: ", GetLastError());
                }
            }
        }
        else if (OrderType() == OP_SELL)
        {
            need_short = false;
            if (OrderStopLoss() > SellStopLoss)
            {
                if (!OrderModify(OrderTicket(), OrderOpenPrice(), SellStopLoss, SellTakeProfit, 0))
                {
                    Print("OrderModify() failed. Error: ", GetLastError());
                }
            }
        }
    }

    if (AccountFreeMargin() < (1000 * Lot))
    {
        Print("No money. Free margin = ", AccountFreeMargin());
        return;
    }

    if ((Bid < MA144H) && (Bid > MA144L)) // Inside the MA bands.
    {
        if (need_long)
        {
            for (int i = 0; i < 10; i++) // 10 attempts.
            {
                int ticket = OrderSend(Symbol(), OP_BUYSTOP, Lot, BuyPrice, Slippage, BuyStopLoss, BuyTakeProfit, OrderCommentary, Magic, 0, clrGreen);
                if (ticket == -1)
                {
                    Print("OrderSend() failed. Error: ", GetLastError());
                }
                else break;
            }
        }
        else if (need_short)
        {
            for (int i = 0; i < 10; i++) // 10 attempts.
            {
                int ticket = OrderSend(Symbol(), OP_SELLSTOP, Lot, SellPrice, Slippage, SellStopLoss, SellTakeProfit, OrderCommentary, Magic, 0, clrRed);
                if (ticket == -1)
                {
                    Print("OrderSend() failed. Error: ", GetLastError());
                }
                else break;
            }
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