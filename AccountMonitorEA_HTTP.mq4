//+------------------------------------------------------------------+
//|                                       AccountMonitorEA_HTTP.mq4  |
//|              MT4 Account Monitor via HTTP (No ZMQ Required)        |
//+------------------------------------------------------------------+
#property copyright "Clawd Trading Tools"
#property version   "3.00"
#property strict

//--- WinInet DLL imports (MT4 compatible)
#import "wininet.dll"
   int InternetOpenA(string agent, int accessType, string proxy, string proxyBypass, int flags);
   int InternetConnectA(int handle, string server, int port, string user, string pass, int service, int flags, int context);
   int HttpOpenRequestA(int handle, string verb, string object, string version, string referrer, int acceptTypes, int flags, int context);
   int HttpSendRequestA(int handle, string headers, int headersLen, string optional, int optionalLen);
   int InternetReadFile(int handle, string buffer, int size, int& read);
   int InternetCloseHandle(int handle);
   int InternetQueryDataAvailable(int handle, int& available, int flags, int context);
#import

//--- Input Parameters
extern string   InpAccountName = "Account1";
extern int      InpAccountType = 0;  // 0=LIVE, 1=CENT, 2=PROP_FTMO, 3=PROP_DARWINEX, 4=PROP_5ERS, 5=DEMO
extern string   InpPropFirm = "";
extern double   InpChallengeSize = 50000;
extern bool     InpIsCentAccount = false;

extern bool     InpEnablePnLAlerts = true;
extern double   InpDailyLossAlertPct = 5;

extern string   InpServerURL = "http://127.0.0.1:8000/api/data";
extern int      InpUpdateInterval = 5;  // seconds

//--- Global Variables
datetime g_lastSend = 0;
double   g_initialBalance = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
   g_initialBalance = AccountBalance();
   
   Print("AccountMonitor HTTP v3.0 (MT4) initialized");
   Print("Account: ", InpAccountName);
   Print("Type: ", GetAccountTypeString(InpAccountType));
   
   // Send initial data
   SendAccountData();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
   Print("AccountMonitor stopped for: ", InpAccountName);
   return(0);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
int start()
{
   if(TimeCurrent() - g_lastSend < InpUpdateInterval)
      return(0);
   
   g_lastSend = TimeCurrent();
   SendAccountData();
   
   return(0);
}

//+------------------------------------------------------------------+
//| Send account data via HTTP POST                                  |
//+------------------------------------------------------------------+
void SendAccountData()
{
   // Gather data
   int      login      = AccountNumber();
   string   company    = AccountCompany();
   string   server     = AccountServer();
   string   currency   = AccountCurrency();
   
   double   balance    = AccountBalance();
   double   equity     = AccountEquity();
   double   margin     = AccountMargin();
   double   freeMargin = AccountFreeMargin();
   double   profit     = AccountProfit();
   double   marginLevel= 0;
   
   if(margin > 0)
      marginLevel = (equity / margin) * 100;
   
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
   
   // Orders count
   int totalOrders = OrdersTotal();
   double openProfit = 0;
   
   for(int i = 0; i < totalOrders; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         double orderProfit = OrderProfit() + OrderSwap() + OrderCommission();
         openProfit += orderProfit;
      }
   }
   
   if(InpIsCentAccount) openProfit *= multiplier;
   
   // Calculate PnL
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
      "\"balance\":" + DoubleToStr(balance, 2) + "," +
      "\"equity\":" + DoubleToStr(equity, 2) + "," +
      "\"margin\":" + DoubleToStr(margin, 2) + "," +
      "\"free_margin\":" + DoubleToStr(freeMargin, 2) + "," +
      "\"profit\":" + DoubleToStr(profit, 2) + "," +
      "\"open_profit\":" + DoubleToStr(openProfit, 2) + "," +
      "\"margin_level\":" + DoubleToStr(marginLevel, 2) + "," +
      "\"positions_count\":" + IntegerToString(totalOrders) + "," +
      "\"challenge_size\":" + DoubleToStr(InpChallengeSize, 2) + "," +
      "\"initial_balance\":" + DoubleToStr(g_initialBalance * multiplier, 2) + "," +
      "\"today_pnl\":" + DoubleToStr(profit, 2) + "," +
      "\"today_pnl_pct\":" + DoubleToStr(profit / (g_initialBalance > 0 ? g_initialBalance : 1) * 100, 2) + "," +
      "\"total_pnl\":" + DoubleToStr(totalPnL, 2) + "," +
      "\"total_pnl_pct\":" + DoubleToStr(totalPnLPct, 2) + "," +
      "\"daily_loss_alert_pct\":" + DoubleToStr(InpDailyLossAlertPct, 2) +
   "}";
   
   // Send HTTP POST
   string response = HttpPost(InpServerURL, json);
   
   if(StringLen(response) > 0)
      Print("Data sent: ", InpAccountName, " Equity: $", equity);
   else
      Print("Failed to send data for: ", InpAccountName);
}

//+------------------------------------------------------------------+
//| HTTP POST request using WinInet                                  |
//+------------------------------------------------------------------+
string HttpPost(string url, string data)
{
   string response = "";
   
   // Parse URL
   string server = "";
   string path = "/";
   int port = 80;
   bool isHttps = false;
   
   if(StringFind(url, "https://") == 0)
   {
      isHttps = true;
      port = 443;
      url = StringSubstr(url, 8);
   }
   else if(StringFind(url, "http://") == 0)
   {
      url = StringSubstr(url, 7);
   }
   
   int slashPos = StringFind(url, "/");
   if(slashPos > 0)
   {
      server = StringSubstr(url, 0, slashPos);
      path = StringSubstr(url, slashPos);
   }
   else
   {
      server = url;
   }
   
   // Check for port in server
   int colonPos = StringFind(server, ":");
   if(colonPos > 0)
   {
      port = (int)StringToInteger(StringSubstr(server, colonPos + 1));
      server = StringSubstr(server, 0, colonPos);
   }
   
   // Create Internet session
   int hInternet = InternetOpenA("MT4Monitor/3.0", 1, "", "", 0);
   if(hInternet == 0)
   {
      Print("InternetOpen failed");
      return response;
   }
   
   // Connect to server
   int hConnect = InternetConnectA(hInternet, server, port, "", "", 3, 0, 0);
   if(hConnect == 0)
   {
      Print("InternetConnect failed");
      InternetCloseHandle(hInternet);
      return response;
   }
   
   // Create request
   int hRequest = HttpOpenRequestA(hConnect, "POST", path, "", "", 0, isHttps ? 0x00800000 : 0, 0);
   if(hRequest == 0)
   {
      Print("HttpOpenRequest failed");
      InternetCloseHandle(hConnect);
      InternetCloseHandle(hInternet);
      return response;
   }
   
   // Headers
   string headers = "Content-Type: application/json\r\n";
   int result = HttpSendRequestA(hRequest, headers, StringLen(headers), data, StringLen(data));
   
   if(result == 0)
   {
      Print("HttpSendRequest failed");
      InternetCloseHandle(hRequest);
      InternetCloseHandle(hConnect);
      InternetCloseHandle(hInternet);
      return response;
   }
   
   // Read response
   int available = 0;
   while(InternetQueryDataAvailable(hRequest, available, 0, 0) && available > 0)
   {
      string buffer;
      int read = 0;
      if(InternetReadFile(hRequest, buffer, available, read))
      {
         response = response + StringSubstr(buffer, 0, read);
      }
   }
   
   // Cleanup
   InternetCloseHandle(hRequest);
   InternetCloseHandle(hConnect);
   InternetCloseHandle(hInternet);
   
   return response;
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
