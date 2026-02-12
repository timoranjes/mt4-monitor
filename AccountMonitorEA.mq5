//+------------------------------------------------------------------+
//|                                              AccountMonitorEA.mq5|
//|                        MT4/5 Account Monitor with ZeroMQ           |
//|                        FTMO 1-Step + PnL Tracking Edition         |
//+------------------------------------------------------------------+
#property copyright "Clawd Trading Tools"
#property version   "2.10"
#property strict

#include <zmq/ZmqSocket.mqh>

//--- 输入参数
input group "=== 账户配置 ==="
input string   InpAccountName = "Account1";      // 账户名称
input ENUM_ACCOUNT_TYPE InpAccountType = ACCOUNT_LIVE; // 账户类型
input string   InpPropFirm = "";                  // Prop Firm名称 (FTMO/DARWINEX等)
input double   InpChallengeSize = 50000;          // 挑战规模 ($)
input bool     InpIsCentAccount = false;          // 是否为Cent账户

input group "=== FTMO 1-Step 规则 ==="
input bool     InpUseFTMO1StepRules = false;      // 启用FTMO 1-Step规则
input double   InpMaxDailyLossPct = 3;            // 最大日损 % (FTMO 1-Step = 3%)
input double   InpMaxTotalLossPct = 10;           // 最大总损 % (FTMO 1-Step = 10%)
input double   InpProfitTargetPct = 10;           // 利润目标 % (FTMO 1-Step = 10%)
input double   InpBestDayMaxPct = 50;             // Best Day 最大占比 % (FTMO = 50%)

input group "=== 盈亏预警 ==="
input bool     InpEnablePnLAlerts = true;         // 启用盈亏追踪
input double   InpDailyLossAlertPct = 5;          // 单日亏损预警 % (如: 5%)
input double   InpDailyProfitAlertPct = 0;        // 单日盈利预警 % (0=关闭)

input group "=== 服务器配置 ==="
input string   InpServerIP = "your-server-ip";    // 中央服务器IP
input int      InpServerPort = 5555;              // 服务器端口
input int      InpUpdateInterval = 5;             // 更新间隔(秒)

//--- 枚举
enum ENUM_ACCOUNT_TYPE
{
   ACCOUNT_LIVE,          // 实盘
   ACCOUNT_CENT,          // Cent账户
   ACCOUNT_PROP_FTMO,     // FTMO挑战
   ACCOUNT_PROP_DARWINEX, // Darwinex
   ACCOUNT_PROP_5ERS,     // 5ers
   ACCOUNT_DEMO           // 模拟
};

//--- 全局变量
Context g_context;
Socket  g_socket(g_context, ZMQ_REQ);
datetime g_lastUpdate = 0;

//--- 账户基础数据
datetime g_sessionStartTime = 0;
double   g_initialBalance = 0;
double   g_todayStartBalance = 0;
datetime g_lastDay = 0;

//--- FTMO 1-Step 追踪变量
double   g_highestBalance = 0;
double   g_yesterdayBalance = 0;

//--- 每日盈亏追踪
struct DayPnL
{
   datetime date;
   double   startBalance;
   double   endBalance;
   double   closedProfit;
   double   floatingProfit;
   double   totalPnL;
};
DayPnL   g_dailyPnLHistory[];        // 历史每日盈亏
double   g_bestDayPnL = 0;           // 最佳单日盈亏
double   g_worstDayPnL = 0;          // 最差单日盈亏
double   g_totalClosedProfit = 0;    // 总平仓盈亏

//--- 当前交易日统计
double   g_todayClosedProfit = 0;    // 今日已平仓盈亏
double   g_todayFloatingProfit = 0;  // 今日浮动盈亏
double   g_todayTotalPnL = 0;        // 今日总盈亏
int      g_tradingDaysCount = 0;     // 总交易天数

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 记录起始数据
   g_sessionStartTime = TimeCurrent();
   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_highestBalance = g_initialBalance;
   g_todayStartBalance = g_initialBalance;
   g_yesterdayBalance = g_initialBalance;
   g_lastDay = getDayStart(TimeCurrent());
   
   //--- 加载历史数据
   LoadHistory();
   
   //--- 计算今日已平仓盈亏
   CalculateTodayClosedProfit();
   
   //--- 连接ZeroMQ服务器
   string endpoint = StringFormat("tcp://%s:%d", InpServerIP, InpServerPort);
   if(!g_socket.connect(endpoint))
   {
      Print("Failed to connect to server: ", endpoint);
      return(INIT_FAILED);
   }
   
   Print("AccountMonitorEA v2.1 initialized for: ", InpAccountName);
   Print("Account Type: ", GetAccountTypeString(InpAccountType));
   Print("FTMO 1-Step Mode: ", InpUseFTMO1StepRules ? "ENABLED" : "DISABLED");
   Print("PnL Tracking: ", InpEnablePnLAlerts ? "ENABLED" : "DISABLED");
   Print("Initial Balance: $", g_initialBalance);
   Print("Trading Days: ", g_tradingDaysCount);
   Print("Connected to: ", endpoint);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- 保存今日数据
   SaveTodayPnL();
   SaveHistory();
   
   g_socket.disconnect(StringFormat("tcp://%s:%d", InpServerIP, InpServerPort));
   Print("AccountMonitorEA stopped for: ", InpAccountName);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 检查是否跨日
   CheckNewDay();
   
   //--- 按间隔发送数据
   if(TimeCurrent() - g_lastUpdate < InpUpdateInterval)
      return;
   
   g_lastUpdate = TimeCurrent();
   
   //--- 更新计算
   UpdateCalculations();
   
   //--- 检查预警
   if(InpEnablePnLAlerts)
      CheckPnLAlerts();
   
   SendAccountData();
}

//+------------------------------------------------------------------+
//| 检查新交易日                                                       |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   datetime currentDay = getDayStart(TimeCurrent());
   if(currentDay > g_lastDay)
   {
      //--- 保存昨日数据
      SaveTodayPnL();
      
      //--- 更新昨日余额
      g_yesterdayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_todayStartBalance = g_yesterdayBalance;
      g_lastDay = currentDay;
      
      //--- 重置今日统计
      g_todayClosedProfit = 0;
      g_todayFloatingProfit = 0;
      g_todayTotalPnL = 0;
      
      Print("New trading day started. Yesterday balance: $", g_yesterdayBalance);
   }
}

//+------------------------------------------------------------------+
//| 获取日期起始时间                                                   |
//+------------------------------------------------------------------+
datetime getDayStart(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| 保存今日盈亏数据                                                   |
//+------------------------------------------------------------------+
void SaveTodayPnL()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- 计算今日最终盈亏
   double closedPnL = CalculateTodayClosedProfit();
   double floatingPnL = currentEquity - currentBalance;
   double totalPnL = currentEquity - g_todayStartBalance;
   
   //--- 添加到历史
   int size = ArraySize(g_dailyPnLHistory);
   ArrayResize(g_dailyPnLHistory, size + 1);
   g_dailyPnLHistory[size].date = g_lastDay;
   g_dailyPnLHistory[size].startBalance = g_todayStartBalance;
   g_dailyPnLHistory[size].endBalance = currentBalance;
   g_dailyPnLHistory[size].closedProfit = closedPnL;
   g_dailyPnLHistory[size].floatingProfit = floatingPnL;
   g_dailyPnLHistory[size].totalPnL = totalPnL;
   
   //--- 更新最佳/最差记录
   if(totalPnL > g_bestDayPnL) g_bestDayPnL = totalPnL;
   if(totalPnL < g_worstDayPnL) g_worstDayPnL = totalPnL;
   
   //--- 更新总盈亏
   g_totalClosedProfit += closedPnL;
   
   Print("Day saved: PnL=$", totalPnL, " | Best: $", g_bestDayPnL, " | Worst: $", g_worstDayPnL);
}

//+------------------------------------------------------------------+
//| 更新计算                                                           |
//+------------------------------------------------------------------+
void UpdateCalculations()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- 更新最高余额
   if(currentBalance > g_highestBalance)
      g_highestBalance = currentBalance;
   
   //--- 计算今日盈亏
   g_todayClosedProfit = CalculateTodayClosedProfit();
   g_todayFloatingProfit = currentEquity - currentBalance;
   g_todayTotalPnL = currentEquity - g_todayStartBalance;
   
   //--- 更新交易天数
   g_tradingDaysCount = ArraySize(g_dailyPnLHistory);
}

//+------------------------------------------------------------------+
//| 计算今日已平仓盈亏                                                 |
//+------------------------------------------------------------------+
double CalculateTodayClosedProfit()
{
   datetime dayStart = getDayStart(TimeCurrent());
   double profit = 0;
   
   HistorySelect(dayStart, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
         }
      }
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| 检查盈亏预警                                                       |
//+------------------------------------------------------------------+
void CheckPnLAlerts()
{
   if(g_initialBalance <= 0) return;
   
   //--- 单日亏损预警
   if(InpDailyLossAlertPct > 0 && g_todayTotalPnL < 0)
   {
      double lossPct = MathAbs(g_todayTotalPnL) / g_initialBalance * 100;
      if(lossPct >= InpDailyLossAlertPct)
      {
         Print("⚠️ ALERT: Daily loss exceeded ", InpDailyLossAlertPct, "%! Current: ", lossPct, "%");
         // 这里可以添加发送通知的代码
      }
   }
   
   //--- 单日盈利预警 (可用于锁定利润提醒)
   if(InpDailyProfitAlertPct > 0 && g_todayTotalPnL > 0)
   {
      double profitPct = g_todayTotalPnL / g_initialBalance * 100;
      if(profitPct >= InpDailyProfitAlertPct)
      {
         Print("✅ ALERT: Daily profit reached ", InpDailyProfitAlertPct, "%! Current: ", profitPct, "%");
      }
   }
}

//+------------------------------------------------------------------+
//| 计算FTMO指标                                                       |
//+------------------------------------------------------------------+
struct FTMOMetrics
{
   double maxDailyLossLimit;
   double dailyLossRemaining;
   double maxTotalLossLimit;
   double totalLossRemaining;
   double profitTargetRemaining;
   double profitProgress;
   double bestDayRatio;
   double bestDayRemaining;
   bool   bestDayPassed;
};

FTMOMetrics CalculateFTMOMetrics()
{
   FTMOMetrics m;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   //--- 最大日损限额
   m.maxDailyLossLimit = g_yesterdayBalance - (InpMaxDailyLossPct / 100.0 * g_initialBalance);
   m.dailyLossRemaining = currentEquity - m.maxDailyLossLimit;
   
   //--- 最大总损限额
   m.maxTotalLossLimit = g_highestBalance - (InpMaxTotalLossPct / 100.0 * g_initialBalance);
   m.totalLossRemaining = currentEquity - m.maxTotalLossLimit;
   
   //--- 利润目标
   double targetAmount = InpProfitTargetPct / 100.0 * g_initialBalance;
   double currentProfit = currentEquity - g_initialBalance;
   m.profitTargetRemaining = targetAmount - currentProfit;
   m.profitProgress = (currentProfit / targetAmount) * 100;
   
   //--- Best Day 计算
   double potentialBestDay = MathMax(g_bestDayPnL, g_todayTotalPnL > 0 ? g_todayTotalPnL : 0);
   double totalProfit = g_totalClosedProfit + (g_todayTotalPnL > 0 ? g_todayTotalPnL : 0);
   
   if(totalProfit > 0)
      m.bestDayRatio = (potentialBestDay / totalProfit) * 100;
   else
      m.bestDayRatio = 0;
   
   if(m.bestDayRatio > InpBestDayMaxPct && potentialBestDay > 0)
   {
      m.bestDayRemaining = (2 * potentialBestDay) - totalProfit;
      m.bestDayPassed = false;
   }
   else
   {
      m.bestDayRemaining = 0;
      m.bestDayPassed = true;
   }
   
   return m;
}

//+------------------------------------------------------------------+
//| 计算盈亏统计                                                       |
//+------------------------------------------------------------------+
struct PnLStats
{
   double todayPnL;              // 今日盈亏
   double todayPnLPct;           // 今日盈亏%
   double weekPnL;               // 本周盈亏 (简化: 最近7天)
   double monthPnL;              // 本月盈亏 (简化: 最近30天)
   double totalPnL;              // 总盈亏 (从初始开始)
   double totalPnLPct;           // 总盈亏%
   double avgDailyPnL;           // 日均盈亏
   double winRate;               // 胜率 (简化)
   int    profitableDays;        // 盈利天数
   int    losingDays;            // 亏损天数
   double maxDrawdown;           // 最大回撤
   double maxDrawdownPct;        // 最大回撤%
   double sharpeRatio;           // 夏普比率 (简化)
};

PnLStats CalculatePnLStats()
{
   PnLStats s;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- 今日盈亏
   s.todayPnL = g_todayTotalPnL;
   s.todayPnLPct = (g_initialBalance > 0) ? (s.todayPnL / g_initialBalance * 100) : 0;
   
   //--- 总盈亏
   s.totalPnL = currentEquity - g_initialBalance;
   s.totalPnLPct = (g_initialBalance > 0) ? (s.totalPnL / g_initialBalance * 100) : 0;
   
   //--- 历史统计
   s.profitableDays = 0;
   s.losingDays = 0;
   double sumPnL = 0;
   double sumSquaredPnL = 0;
   
   datetime now = TimeCurrent();
   datetime weekAgo = now - 7 * 24 * 3600;
   datetime monthAgo = now - 30 * 24 * 3600;
   
   for(int i = 0; i < ArraySize(g_dailyPnLHistory); i++)
   {
      double dayPnL = g_dailyPnLHistory[i].totalPnL;
      sumPnL += dayPnL;
      sumSquaredPnL += dayPnL * dayPnL;
      
      if(dayPnL > 0) s.profitableDays++;
      else if(dayPnL < 0) s.losingDays++;
      
      // 本周盈亏
      if(g_dailyPnLHistory[i].date >= weekAgo)
         s.weekPnL += dayPnL;
      
      // 本月盈亏
      if(g_dailyPnLHistory[i].date >= monthAgo)
         s.monthPnL += dayPnL;
   }
   
   //--- 包含今日
   if(s.todayPnL > 0) s.profitableDays++;
   else if(s.todayPnL < 0) s.losingDays++;
   s.weekPnL += s.todayPnL;
   s.monthPnL += s.todayPnL;
   
   //--- 日均盈亏
   int totalDays = s.profitableDays + s.losingDays;
   s.avgDailyPnL = (totalDays > 0) ? (sumPnL / totalDays) : 0;
   
   //--- 胜率
   s.winRate = (totalDays > 0) ? ((double)s.profitableDays / totalDays * 100) : 0;
   
   //--- 最大回撤 (简化)
   s.maxDrawdown = MathAbs(g_worstDayPnL);
   s.maxDrawdownPct = (g_initialBalance > 0) ? (s.maxDrawdown / g_initialBalance * 100) : 0;
   
   //--- 简化夏普比率 (假设无风险利率为0)
   if(totalDays > 1)
   {
      double variance = (sumSquaredPnL / totalDays) - (s.avgDailyPnL * s.avgDailyPnL);
      double stdDev = MathSqrt(MathMax(0, variance));
      s.sharpeRatio = (stdDev > 0) ? (s.avgDailyPnL / stdDev * MathSqrt(252)) : 0; // 年化
   }
   else
   {
      s.sharpeRatio = 0;
   }
   
   return s;
}

//+------------------------------------------------------------------+
//| 发送账户数据到服务器                                               |
//+------------------------------------------------------------------+
void SendAccountData()
{
   //--- 获取账户信息
   long     login      = AccountInfoInteger(ACCOUNT_LOGIN);
   string   company    = AccountInfoString(ACCOUNT_COMPANY);
   string   server     = AccountInfoString(ACCOUNT_SERVER);
   string   currency   = AccountInfoString(ACCOUNT_CURRENCY);
   
   double   balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double   equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double   margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double   freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double   profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   double   marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   //--- Cent账户转换
   double multiplier = InpIsCentAccount ? 0.01 : 1.0;
   if(InpIsCentAccount)
   {
      balance    *= multiplier;
      equity     *= multiplier;
      margin     *= multiplier;
      freeMargin *= multiplier;
      profit     *= multiplier;
   }
   
   //--- 计算持仓统计
   int totalPositions = PositionsTotal();
   double openProfit = 0;
   double openVolume = 0;
   
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         openProfit += PositionGetDouble(POSITION_PROFIT);
         openVolume += PositionGetDouble(POSITION_VOLUME);
      }
   }
   
   if(InpIsCentAccount) openProfit *= multiplier;
   
   //--- FTMO 1-Step 计算
   FTMOMetrics ftmo;
   if(InpUseFTMO1StepRules)
      ftmo = CalculateFTMOMetrics();
   else
   {
      ZeroMemory(ftmo);
      ftmo.maxDailyLossLimit = g_initialBalance * (1 - InpMaxDailyLossPct / 100);
      ftmo.dailyLossRemaining = equity - ftmo.maxDailyLossLimit;
      ftmo.maxTotalLossLimit = g_initialBalance * (1 - InpMaxTotalLossPct / 100);
      ftmo.totalLossRemaining = equity - ftmo.maxTotalLossLimit;
      ftmo.profitTargetRemaining = (InpProfitTargetPct / 100 * g_initialBalance) - (equity - g_initialBalance);
      ftmo.profitProgress = ((equity - g_initialBalance) / (InpProfitTargetPct / 100 * g_initialBalance)) * 100;
      ftmo.bestDayPassed = true;
   }
   
   //--- 盈亏统计
   PnLStats pnl = CalculatePnLStats();
   
   //--- 构建JSON
   string json = StringFormat(
      "{" +
      "\"timestamp\":%s," +
      "\"account_name\":\"%s\"," +
      "\"account_type\":\"%s\"," +
      "\"prop_firm\":\"%s\"," +
      "\"login\":%I64d," +
      "\"company\":\"%s\"," +
      "\"server\":\"%s\"," +
      "\"currency\":\"%s\"," +
      "\"is_cent\":%s," +
      "\"is_ftmo_1step\":%s," +
      "\"balance\":%.2f," +
      "\"equity\":%.2f," +
      "\"margin\":%.2f," +
      "\"free_margin\":%.2f," +
      "\"profit\":%.2f," +
      "\"open_profit\":%.2f," +
      "\"margin_level\":%.2f," +
      "\"positions_count\":%d," +
      "\"open_volume\":%.2f," +
      "\"challenge_size\":%.2f," +
      "\"initial_balance\":%.2f," +
      "\"highest_balance\":%.2f," +
      "\"yesterday_balance\":%.2f," +
      "\"daily_loss_limit\":%.2f," +
      "\"daily_loss_remaining\":%.2f," +
      "\"total_loss_limit\":%.2f," +
      "\"total_loss_remaining\":%.2f," +
      "\"profit_target_remaining\":%.2f," +
      "\"profit_progress_pct\":%.2f," +
      "\"best_day_profit\":%.2f," +
      "\"best_day_ratio\":%.2f," +
      "\"best_day_remaining\":%.2f," +
      "\"best_day_passed\":%s," +
      "\"max_daily_loss_pct\":%.2f," +
      "\"max_total_loss_pct\":%.2f," +
      "\"profit_target_pct\":%.2f," +
      // PnL 数据
      "\"today_pnl\":%.2f," +
      "\"today_pnl_pct\":%.2f," +
      "\"week_pnl\":%.2f," +
      "\"month_pnl\":%.2f," +
      "\"total_pnl\":%.2f," +
      "\"total_pnl_pct\":%.2f," +
      "\"avg_daily_pnl\":%.2f," +
      "\"win_rate\":%.2f," +
      "\"profitable_days\":%d," +
      "\"losing_days\":%d," +
      "\"max_drawdown\":%.2f," +
      "\"max_drawdown_pct\":%.2f," +
      "\"sharpe_ratio\":%.2f," +
      "\"trading_days\":%d," +
      "\"daily_loss_alert_pct\":%.2f," +
      "\"daily_profit_alert_pct\":%.2f" +
      "}",
      IntegerToString((long)TimeCurrent()),
      InpAccountName,
      GetAccountTypeString(InpAccountType),
      InpPropFirm,
      login,
      company,
      server,
      currency,
      InpIsCentAccount ? "true" : "false",
      InpUseFTMO1StepRules ? "true" : "false",
      balance,
      equity,
      margin,
      freeMargin,
      profit,
      openProfit,
      marginLevel,
      totalPositions,
      openVolume,
      InpChallengeSize,
      g_initialBalance * multiplier,
      g_highestBalance * multiplier,
      g_yesterdayBalance * multiplier,
      ftmo.maxDailyLossLimit * multiplier,
      ftmo.dailyLossRemaining * multiplier,
      ftmo.maxTotalLossLimit * multiplier,
      ftmo.totalLossRemaining * multiplier,
      ftmo.profitTargetRemaining * multiplier,
      ftmo.profitProgress,
      g_bestDayPnL * multiplier,
      ftmo.bestDayRatio,
      ftmo.bestDayRemaining * multiplier,
      ftmo.bestDayPassed ? "true" : "false",
      InpMaxDailyLossPct,
      InpMaxTotalLossPct,
      InpProfitTargetPct,
      // PnL
      pnl.todayPnL * multiplier,
      pnl.todayPnLPct,
      pnl.weekPnL * multiplier,
      pnl.monthPnL * multiplier,
      pnl.totalPnL * multiplier,
      pnl.totalPnLPct,
      pnl.avgDailyPnL * multiplier,
      pnl.winRate,
      pnl.profitableDays,
      pnl.losingDays,
      pnl.maxDrawdown * multiplier,
      pnl.maxDrawdownPct,
      pnl.sharpeRatio,
      pnl.profitableDays + pnl.losingDays,
      InpDailyLossAlertPct,
      InpDailyProfitAlertPct
   );
   
   //--- 发送数据
   ZmqMsg request(json);
   if(!g_socket.send(request))
   {
      Print("Failed to send data");
      return;
   }
   
   //--- 接收确认
   ZmqMsg reply;
   if(g_socket.recv(reply, 1000))
   {
      string response = reply.getData();
      if(response != "OK")
         Print("Server response: ", response);
   }
}

//+------------------------------------------------------------------+
//| 加载历史数据                                                       |
//+------------------------------------------------------------------+
void LoadHistory()
{
   string filename = InpAccountName + "_history.csv";
   int handle = FileOpen(filename, FILE_READ|FILE_SHARE_READ|FILE_CSV|FILE_COMMON, ',');
   
   if(handle != INVALID_HANDLE)
   {
      // 读取表头
      FileReadString(handle); // header
      
      while(!FileIsEnding(handle))
      {
         string dateStr = FileReadString(handle);
         if(StringLen(dateStr) < 8) continue;
         
         datetime date = StringToTime(dateStr);
         double startBal = StringToDouble(FileReadString(handle));
         double endBal = StringToDouble(FileReadString(handle));
         double closed = StringToDouble(FileReadString(handle));
         double floating = StringToDouble(FileReadString(handle));
         double total = StringToDouble(FileReadString(handle));
         
         if(date > 0)
         {
            int size = ArraySize(g_dailyPnLHistory);
            ArrayResize(g_dailyPnLHistory, size + 1);
            g_dailyPnLHistory[size].date = date;
            g_dailyPnLHistory[size].startBalance = startBal;
            g_dailyPnLHistory[size].endBalance = endBal;
            g_dailyPnLHistory[size].closedProfit = closed;
            g_dailyPnLHistory[size].floatingProfit = floating;
            g_dailyPnLHistory[size].totalPnL = total;
            
            // 更新统计
            if(total > g_bestDayPnL) g_bestDayPnL = total;
            if(total < g_worstDayPnL) g_worstDayPnL = total;
            g_totalClosedProfit += closed;
         }
      }
      FileClose(handle);
      Print("Loaded ", ArraySize(g_dailyPnLHistory), " days of history");
   }
}

//+------------------------------------------------------------------+
//| 保存历史数据                                                       |
//+------------------------------------------------------------------+
void SaveHistory()
{
   string filename = InpAccountName + "_history.csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, "Date", "StartBalance", "EndBalance", "ClosedProfit", "FloatingProfit", "TotalPnL");
      
      for(int i = 0; i < ArraySize(g_dailyPnLHistory); i++)
      {
         FileWrite(handle, 
            TimeToString(g_dailyPnLHistory[i].date, TIME_DATE),
            DoubleToString(g_dailyPnLHistory[i].startBalance, 2),
            DoubleToString(g_dailyPnLHistory[i].endBalance, 2),
            DoubleToString(g_dailyPnLHistory[i].closedProfit, 2),
            DoubleToString(g_dailyPnLHistory[i].floatingProfit, 2),
            DoubleToString(g_dailyPnLHistory[i].totalPnL, 2));
      }
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| 获取账户类型字符串                                                 |
//+------------------------------------------------------------------+
string GetAccountTypeString(ENUM_ACCOUNT_TYPE type)
{
   switch(type)
   {
      case ACCOUNT_LIVE:          return "LIVE";
      case ACCOUNT_CENT:          return "CENT";
      case ACCOUNT_PROP_FTMO:     return "PROP_FTMO";
      case ACCOUNT_PROP_DARWINEX: return "PROP_DARWINEX";
      case ACCOUNT_PROP_5ERS:     return "PROP_5ERS";
      case ACCOUNT_DEMO:          return "DEMO";
      default:                    return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
