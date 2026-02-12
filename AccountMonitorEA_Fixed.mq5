//+------------------------------------------------------------------+
//|                                       AccountMonitorEA_HTTP.mq5  |
//|              MT5 Account Monitor - JSON Fix Version                |
//+------------------------------------------------------------------+
#property copyright "Clawd Trading Tools"
#property version   "3.01"
#property strict

input group "=== Account Config ==="
input string   InpAccountName = "Account1";
input int      InpAccountType = 0;
input string   InpPropFirm = "";
input double   InpChallengeSize = 50000;
input bool     InpIsCentAccount = false;

input group "=== Server Config ==="
input string   InpServerURL = "http://127.0.0.1:8000/api/data";
input int      InpUpdateInterval = 5;

datetime g_lastSend = 0;
double   g_initialBalance = 0;

int OnInit()
{
   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("AccountMonitor HTTP v3.01 started");
   SendAccountData();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { }

void OnTick()
{
   if(TimeCurrent() - g_lastSend < InpUpdateInterval) return;
   g_lastSend = TimeCurrent();
   SendAccountData();
}

void SendAccountData()
{
   // Get account info
   long   login    = AccountInfoInteger(ACCOUNT_LOGIN);
   string company  = AccountInfoString(ACCOUNT_COMPANY);
   string server   = AccountInfoString(ACCOUNT_SERVER);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit   = AccountInfoDouble(ACCOUNT_PROFIT);
   
   // Build simple JSON manually - NO special characters
   string json = "{";
   json += "\"account_name\":\"" + StringReplace(InpAccountName, "\"", "'") + "\",";
   json += "\"account_type\":\"" + GetType(InpAccountType) + "\",";
   json += "\"login\":" + IntegerToString(login) + ",";
   json += "\"company\":\"" + StringReplace(company, "\"", "'") + "\",";
   json += "\"server\":\"" + StringReplace(server, "\"", "'") + "\",";
   json += "\"currency\":\"" + currency + "\",";
   json += "\"balance\":" + DoubleToString(balance, 2) + ",";
   json += "\"equity\":" + DoubleToString(equity, 2) + ",";
   json += "\"profit\":" + DoubleToString(profit, 2);
   json += "}";
   
   // Send
   char data[], result[];
   StringToCharArray(json, data);
   string headers;
   int res = WebRequest("POST", InpServerURL, headers, 5000, data, result, headers);
   
   if(res == 200)
      Print("Sent: ", InpAccountName, " $", equity);
   else
      Print("Failed: ", res, " Error: ", GetLastError());
}

string GetType(int t)
{
   if(t==0) return "LIVE";
   if(t==1) return "CENT";
   if(t==2) return "PROP_FTMO";
   if(t==3) return "PROP_DARWINEX";
   if(t==4) return "PROP_5ERS";
   return "DEMO";
}

string StringReplace(string str, string from, string to)
{
   string result = str;
   int pos = StringFind(result, from);
   while(pos != -1)
   {
      result = StringSubstr(result, 0, pos) + to + StringSubstr(result, pos + StringLen(from));
      pos = StringFind(result, from, pos + StringLen(to));
   }
   return result;
}
