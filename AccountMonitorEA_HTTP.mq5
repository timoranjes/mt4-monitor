//+------------------------------------------------------------------+
//|                                       AccountMonitorEA_HTTP.mq5  |
//|              MT5 Account Monitor via HTTP (No ZMQ Required)        |
//|              Uses built-in WebRequest function                     |
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
   
   Print("AccountMonitor HTTP v3.0 (MT5) initialized");
   Print("Account: ", InpAccountName);
   Print("Type: ", GetAccountTypeString(InpAccountType));
   Print("Server: ", InpServerURL);
   
   // Send initial data
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
   
   // Positions count
   int totalPositions = PositionsTotal();
   double openProfit = 0;
   
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
         openProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   if(InpIsCentAccount) openProfit *= multiplier;
   
   // Calculate PnL
   double totalPnL = equity - g_initialBalance;
   
   // Build JSON
   string json = BuildJSON(
      InpAccountName,
      GetAccountTypeString(InpAccountType),
      InpPropFirm,
      login,
      company,
      server,
      currency,
      InpIsCentAccount,
      balance,
      equity,
      margin,
      freeMargin,
      profit,
      openProfit,
      marginLevel,
      totalPositions,
      InpChallengeSize,
      g_initialBalance * multiplier,
      profit,
      totalPnL,
      InpDailyLossAlertPct
   );
   
   // Prepare data for WebRequest
   char data[], result[];
   StringToCharArray(json, data);
   int dataSize = ArraySize(data);
   
   string headers;
   
   // Send HTTP POST - use 6 parameter version
   int res = WebRequest("POST", InpServerURL, g_timeout, data, result, headers);
   
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
//| Build JSON string                                                |
//+------------------------------------------------------------------+
string BuildJSON(
   string account_name,
   string account_type,
   string prop_firm,
   long login,
   string company,
   string server,
   string currency,
   bool is_cent,
   double balance,
   double equity,
   double margin,
   double free_margin,
   double profit,
   double open_profit,
   double margin_level,
   int positions_count,
   double challenge_size,
   double initial_balance,
   double today_pnl,
   double total_pnl,
   double daily_loss_alert_pct
)
{
   string json = "{" +
      "\"account_name\":\"" + account_name + "\"," +
      "\"account_type\":\"" + account_type + "\"," +
      "\"prop_firm\":\"" + prop_firm + "\"," +
      "\"login\":" + IntegerToString(login) + "," +
      "\"company\":\"" + company + "\"," +
      "\"server\":\"" + server + "\"," +
      "\"currency\":\"" + currency + "\"," +
      "\"is_cent\":" + (is_cent ? "true" : "false") + "," +
      "\"is_ftmo_1step\":false," +
      "\"balance\":" + DoubleToString(balance, 2) + "," +
      "\"equity\":" + DoubleToString(equity, 2) + "," +
      "\"margin\":" + DoubleToString(margin, 2) + "," +
      "\"free_margin\":" + DoubleToString(free_margin, 2) + "," +
      "\"profit\":" + DoubleToString(profit, 2) + "," +
      "\"open_profit\":" + DoubleToString(open_profit, 2) + "," +
      "\"margin_level\":" + DoubleToString(margin_level, 2) + "," +
      "\"positions_count\":" + IntegerToString(positions_count) + "," +
      "\"challenge_size\":" + DoubleToString(challenge_size, 2) + "," +
      "\"initial_balance\":" + DoubleToString(initial_balance, 2) + "," +
      "\"today_pnl\":" + DoubleToString(today_pnl, 2) + "," +
      "\"today_pnl_pct\":" + DoubleToString(today_pnl / (initial_balance > 0 ? initial_balance : 1) * 100, 2) + "," +
      "\"total_pnl\":" + DoubleToString(total_pnl, 2) + "," +
      "\"total_pnl_pct\":" + DoubleToString(total_pnl / (initial_balance > 0 ? initial_balance : 1) * 100, 2) + "," +
      "\"daily_loss_alert_pct\":" + DoubleToString(daily_loss_alert_pct, 2) +
   "}";
   
   return json;
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
