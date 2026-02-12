//+------------------------------------------------------------------+
//|                                       AccountMonitorEA_HTTP.mq5  |
//|              MT5 Account Monitor via HTTP (No ZMQ Required)        |
//+------------------------------------------------------------------+
#property copyright "Clawd Trading Tools"
#property version   "3.00"
#property strict

//--- WinHTTP DLL imports
#import "winhttp.dll"
   int WinHttpOpen(string userAgent, int accessType, string proxyName, string proxyBypass, int flags);
   int WinHttpConnect(int sessionHandle, string serverName, int serverPort, int reserved);
   int WinHttpOpenRequest(int connectHandle, string verb, string objectName, string version, string referrer, int reserved, int flags);
   bool WinHttpSendRequest(int requestHandle, string headers, int headersLength, string optional, int optionalLength, int totalLength, int context);
   bool WinHttpReceiveResponse(int requestHandle, int reserved);
   bool WinHttpQueryDataAvailable(int requestHandle, int& size);
   bool WinHttpReadData(int requestHandle, string buffer, int bufferLength, int& downloaded);
   bool WinHttpCloseHandle(int handle);
#import

//--- Input Parameters
input group "=== Account Config ==="
input string   InpAccountName = "Account1";
input ENUM_ACCOUNT_TYPE InpAccountType = ACCOUNT_LIVE;
input string   InpPropFirm = "";
input double   InpChallengeSize = 50000;
input bool     InpIsCentAccount = false;

input group "=== PnL Alerts ==="
input bool     InpEnablePnLAlerts = true;
input double   InpDailyLossAlertPct = 5;

input group "=== Server Config ==="
input string   InpServerURL = "http://127.0.0.1:8000/api/data";  // HTTP endpoint
input int      InpUpdateInterval = 5;  // seconds

//--- Enums
enum ENUM_ACCOUNT_TYPE
{
   ACCOUNT_LIVE = 0,
   ACCOUNT_CENT = 1,
   ACCOUNT_PROP_FTMO = 2,
   ACCOUNT_PROP_DARWINEX = 3,
   ACCOUNT_PROP_5ERS = 4,
   ACCOUNT_DEMO = 5
};

//--- Global Variables
datetime g_lastSend = 0;
double   g_initialBalance = 0;

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
   
   // Send HTTP POST
   string response = HttpPost(InpServerURL, json);
   
   if(StringLen(response) > 0)
      Print("Data sent: ", InpAccountName, " Equity: $", equity);
   else
      Print("Failed to send data for: ", InpAccountName);
}

//+------------------------------------------------------------------+
//| HTTP POST request using WinHTTP                                  |
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
   
   // Create WinHTTP session
   int hSession = WinHttpOpen("MT5Monitor/3.0", 1, "", "", 0);
   if(hSession == 0)
   {
      Print("WinHttpOpen failed");
      return response;
   }
   
   // Connect to server
   int hConnect = WinHttpConnect(hSession, server, port, 0);
   if(hConnect == 0)
   {
      Print("WinHttpConnect failed");
      WinHttpCloseHandle(hSession);
      return response;
   }
   
   // Create request
   int hRequest = WinHttpOpenRequest(hConnect, "POST", path, "", "", 0, isHttps ? 0x00800000 : 0);
   if(hRequest == 0)
   {
      Print("WinHttpOpenRequest failed");
      WinHttpCloseHandle(hConnect);
      WinHttpCloseHandle(hSession);
      return response;
   }
   
   // Headers
   string headers = "Content-Type: application/json\r\n";
   int dataLen = StringLen(data);
   
   // Send request
   bool result = WinHttpSendRequest(hRequest, headers, StringLen(headers), data, dataLen, dataLen, 0);
   if(!result)
   {
      Print("WinHttpSendRequest failed");
      WinHttpCloseHandle(hRequest);
      WinHttpCloseHandle(hConnect);
      WinHttpCloseHandle(hSession);
      return response;
   }
   
   // Receive response
   result = WinHttpReceiveResponse(hRequest, 0);
   if(!result)
   {
      Print("WinHttpReceiveResponse failed");
      WinHttpCloseHandle(hRequest);
      WinHttpCloseHandle(hConnect);
      WinHttpCloseHandle(hSession);
      return response;
   }
   
   // Read response
   int size = 0;
   while(WinHttpQueryDataAvailable(hRequest, size) && size > 0)
   {
      string buffer;
      int downloaded = 0;
      if(WinHttpReadData(hRequest, buffer, size, downloaded))
      {
         response = response + StringSubstr(buffer, 0, downloaded);
      }
   }
   
   // Cleanup
   WinHttpCloseHandle(hRequest);
   WinHttpCloseHandle(hConnect);
   WinHttpCloseHandle(hSession);
   
   return response;
}

//+------------------------------------------------------------------+
//| Get account type string                                          |
//+------------------------------------------------------------------+
string GetAccountTypeString(ENUM_ACCOUNT_TYPE type)
{
   switch(type)
   {
      case ACCOUNT_LIVE:      return "LIVE";
      case ACCOUNT_CENT:      return "CENT";
      case ACCOUNT_PROP_FTMO: return "PROP_FTMO";
      case ACCOUNT_PROP_DARWINEX: return "PROP_DARWINEX";
      case ACCOUNT_PROP_5ERS: return "PROP_5ERS";
      case ACCOUNT_DEMO:      return "DEMO";
      default:                return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
