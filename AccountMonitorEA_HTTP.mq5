//+------------------------------------------------------------------+
//|                                       AccountMonitorEA_HTTP.mq5  |
//|              MT5 Account Monitor via HTTP (No ZMQ Required)        |
//+------------------------------------------------------------------+
#property copyright "Clawd Trading Tools"
#property version   "3.00"
#property strict

//--- Input Parameters
input group "=== Account Config ==="
input string   InpAccountName = "Account1";
input int      InpAccountType = 0;  // 0=LIVE, 1=CENT, 2=PROP_FTMO, 3=PROP_DARWINEX, 4=PROP_5ERS, 5=DEMO
input string   InpPropFirm = "";
input double   InpChallengeSize = 50000;
input bool     InpIsCentAccount = false;

input group "=== PnL Alerts ==="
input bool     InpEnablePnLAlerts = true;
input double   InpDailyLossAlertPct = 5;

input group "=== Server Config ==="
input string   InpServerURL = "http://127.0.0.1:8000/api/data";
input int      InpUpdateInterval = 5;

//--- Global Variables
datetime g_lastSend = 0;
double   g_initialBalance = 0;
int      g_timeout = 5000;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("AccountMonitor HTTP v3.0 initialized");
   Print("Account: ", InpAccountName);
   Print("Type: ", GetAccountTypeString(InpAccountType));
   Print("Server: ", InpServerURL);
   
   SendAccountData();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("AccountMonitor stopped for: ", InpAccountName);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() - g_lastSend < InpUpdateInterval)
      return;
   
   g_lastSend = TimeCurrent();
   SendAccountData();
}

//+------------------------------------------------------------------+
//| Send account data via HTTP POST                                  |
//+------------------------------------------------------------------+
void SendAccountData()
{
   // Gather data
   long     login      = AccountInfoInteger(ACCOUNT_LOGIN);
   string   company    = AccountInfoString(ACCOUNT_COMPANY);
   string   server     = AccountInfoString(ACCOUNT_SERVER);
   string   currency   = AccountInfoString(ACCOUNT_CURRENCY);
   
   double   balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double   equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double   margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double   freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double   profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   double   marginLevel= AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   // Cent conversion
   double multiplier = InpIsCentAccount ? 0.01 : 1.0;
   if(InpIsCentAccount)
   {
      balance    *= multiplier;
      equity     *= multiplier;
      margin     *= multiplier;
      freeMargin *= multiplier;
      profit     *= multiplier;
   }
   
   int totalPositions = PositionsTotal();
   double openProfit = 0;
   
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
         openProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   if(InpIsCentAccount) openProfit *= multiplier;
   
   double totalPnL = equity - g_initialBalance;
   double totalPnLPct = g_initialBalance > 0 ? (totalPnL / g_initialBalance * 100) : 0;
   
   // Build JSON
   string json = "{" +
      "\"account_name\":\"" + InpAccountName + "\"," +
      "\"account_type\":\"" + GetAccountTypeString(InpAccountType) + "\"," +
      "\"prop_firm\":\"" + InpPropFirm + "\"," +
      "\"login\":" + IntegerToString(login) + "," +
      "\"company\":\"" + company + "\"," +
      "\"server\":\"" + server + "\"," +
      "\"currency\":\"" + currency + "\"," +
      "\"is_cent\":" + (InpIsCentAccount ? "true" : "false") + "," +
      "\"is_ftmo_1step\":false," +
      "\"balance\":" + DoubleToString(balance, 2) + "," +
      "\"equity\":" + DoubleToString(equity, 2) + "," +
      "\"margin\":" + DoubleToString(margin, 2) + "," +
      "\"free_margin\":" + DoubleToString(freeMargin, 2) + "," +
      "\"profit\":" + DoubleToString(profit, 2) + "," +
      "\"open_profit\":" + DoubleToString(openProfit, 2) + "," +
      "\"margin_level\":" + DoubleToString(marginLevel, 2) + "," +
      "\"positions_count\":" + IntegerToString(totalPositions) + "," +
      "\"challenge_size\":" + DoubleToString(InpChallengeSize, 2) + "," +
      "\"initial_balance\":" + DoubleToString(g_initialBalance * multiplier, 2) + "," +
      "\"today_pnl\":" + DoubleToString(profit, 2) + "," +
      "\"today_pnl_pct\":" + DoubleToString(profit / (g_initialBalance > 0 ? g_initialBalance : 1) * 100, 2) + "," +
      "\"total_pnl\":" + DoubleToString(totalPnL, 2) + "," +
      "\"total_pnl_pct\":" + DoubleToString(totalPnLPct, 2) + "," +
      "\"daily_loss_alert_pct\":" + DoubleToString(InpDailyLossAlertPct, 2) +
   "}";
   
   // Prepare data for WebRequest - use correct 7-parameter version
   char data[], result[];
   StringToCharArray(json, data);
   
   string headers = "Content-Type: application/json\r\n";
   string result_headers;
   
   // WebRequest: method, url, headers, timeout, data, result, result_headers
   int res = WebRequest("POST", InpServerURL, headers, g_timeout, data, result, result_headers);
   
   if(res == 200)
   {
      Print("Data sent: ", InpAccountName, " Equity: $", equity);
   }
   else
   {
      Print("Failed to send data. Error: ", res);
      if(res == -1)
         Print("Error: ", GetLastError(), " - Check Tools->Options->EA Trading allow WebRequest for ", InpServerURL);
   }
}

//+------------------------------------------------------------------+
//| Get account type string                                          |
//+------------------------------------------------------------------+
string GetAccountTypeString(int type)
{
   switch(type)
   {
      case 0:  return "LIVE";
      case 1:  return "CENT";
      case 2:  return "PROP_FTMO";
      case 3:  return "PROP_DARWINEX";
      case 4:  return "PROP_5ERS";
      case 5:  return "DEMO";
      default: return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
