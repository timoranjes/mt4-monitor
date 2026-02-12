# MT4 Monitor - Windows One-Click Deploy Script
# Run this on your Windows VPS as Administrator

param(
    [string]$ServerIP = "216.66.53.132",
    [string]$AdminUser = "timoranjes",
    [string]$AdminPass = "19931017lzc"
)

Write-Host "🚀 MT4/5 Account Monitor - Windows Deployment" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ Please run this script as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell → Run as Administrator" -ForegroundColor Yellow
    exit 1
}

# Create directory
$InstallDir = "C:\mt4_monitor"
Write-Host "📁 Creating directory: $InstallDir" -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\static" | Out-Null

# Check Python
Write-Host "🐍 Checking Python installation..." -ForegroundColor Green
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}

if (-not $python) {
    Write-Host "⚠️  Python not found. Please install Python 3.11 from Microsoft Store or python.org" -ForegroundColor Yellow
    Write-Host "   Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    
    # Try to install via winget
    Write-Host "🔄 Attempting to install Python via winget..." -ForegroundColor Cyan
    try {
        winget install Python.Python.3.11 --accept-package-agreements --accept-source-agreements
        Write-Host "✅ Python installed! Please restart this script." -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "❌ Automatic install failed. Please install manually." -ForegroundColor Red
        exit 1
    }
}

Write-Host "✅ Python found: $($python.Source)" -ForegroundColor Green

# Install dependencies
Write-Host "📦 Installing Python dependencies..." -ForegroundColor Green
try {
    & python -m pip install fastapi uvicorn pyzmq websockets
    Write-Host "✅ Dependencies installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to install dependencies" -ForegroundColor Red
    exit 1
}

# Create server.py
Write-Host "📝 Creating server.py..." -ForegroundColor Green
$serverCode = @'
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException, status
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
import zmq.asyncio
import asyncio
import json
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
import uvicorn
import secrets
import os

# Configuration
ADMIN_USERNAME = "timoranjes"
ADMIN_PASSWORD = "19931017lzc"
ENABLE_AUTH = True
TELEGRAM_ENABLED = True
TELEGRAM_CHAT_ID = "6692882496"

security = HTTPBasic()

def verify_credentials(credentials: HTTPBasicCredentials = Depends(security)):
    if not ENABLE_AUTH:
        return credentials
    is_correct_username = secrets.compare_digest(credentials.username, ADMIN_USERNAME)
    is_correct_password = secrets.compare_digest(credentials.password, ADMIN_PASSWORD)
    if not (is_correct_username and is_correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials

@dataclass
class AccountData:
    timestamp: int
    account_name: str
    account_type: str
    prop_firm: str
    login: int
    company: str
    server: str
    currency: str
    is_cent: bool
    is_ftmo_1step: bool
    balance: float
    equity: float
    margin: float
    free_margin: float
    profit: float
    open_profit: float
    margin_level: float
    positions_count: int
    open_volume: float
    challenge_size: float
    initial_balance: float
    highest_balance: float
    yesterday_balance: float
    daily_loss_limit: float
    daily_loss_remaining: float
    total_loss_limit: float
    total_loss_remaining: float
    profit_target_remaining: float
    profit_progress_pct: float
    best_day_profit: float
    best_day_ratio: float
    best_day_remaining: float
    best_day_passed: bool
    max_daily_loss_pct: float
    max_total_loss_pct: float
    profit_target_pct: float
    today_pnl: float = 0
    today_pnl_pct: float = 0
    week_pnl: float = 0
    month_pnl: float = 0
    total_pnl: float = 0
    total_pnl_pct: float = 0
    avg_daily_pnl: float = 0
    win_rate: float = 0
    profitable_days: int = 0
    losing_days: int = 0
    max_drawdown: float = 0
    max_drawdown_pct: float = 0
    sharpe_ratio: float = 0
    trading_days: int = 0
    daily_loss_alert_pct: float = 5
    daily_profit_alert_pct: float = 0
    last_seen: Optional[datetime] = None
    status: str = "online"
    daily_loss_risk: str = "safe"
    total_loss_risk: str = "safe"
    profit_target_risk: str = "pending"
    pnl_alert_triggered: bool = False
    alert_sent: bool = False

    def to_dict(self):
        data = asdict(self)
        if self.last_seen:
            data['last_seen'] = self.last_seen.isoformat()
        return data

accounts: Dict[str, AccountData] = {}
active_connections: List[WebSocket] = []
data_lock = asyncio.Lock()
notification_queue: asyncio.Queue = asyncio.Queue()

def init_database():
    conn = sqlite3.connect('mt4_monitor.db')
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
            account_name TEXT PRIMARY KEY,
            account_type TEXT,
            prop_firm TEXT,
            login INTEGER,
            company TEXT,
            server TEXT,
            currency TEXT,
            is_cent BOOLEAN,
            is_ftmo_1step BOOLEAN,
            challenge_size REAL,
            initial_balance REAL,
            max_daily_loss_pct REAL,
            max_total_loss_pct REAL,
            profit_target_pct REAL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_name TEXT,
            timestamp INTEGER,
            balance REAL,
            equity REAL,
            profit REAL,
            today_pnl REAL,
            total_pnl REAL,
            best_day_ratio REAL,
            profit_progress_pct REAL
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_name TEXT,
            alert_type TEXT,
            message TEXT,
            sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

async def notification_worker():
    while True:
        try:
            alert = await notification_queue.get()
            await send_telegram_notification(alert)
            notification_queue.task_done()
        except Exception as e:
            print(f"Notification error: {e}")
            await asyncio.sleep(5)

async def send_telegram_notification(alert: dict):
    if not TELEGRAM_ENABLED:
        return
    try:
        import subprocess
        emoji = {"danger": "🚨", "warning": "⚠️", "info": "ℹ️"}.get(alert['level'], "ℹ️")
        text = f"{emoji} <b>MT4 Monitor Alert</b>\n\n<b>Account:</b> {alert['account']}\n<b>Type:</b> {alert['type']}\n<b>Level:</b> {alert['level'].upper()}\n\n{alert['message']}\n\n<i>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</i>"
        # Use OpenClaw messaging if available
        conn = sqlite3.connect('mt4_monitor.db')
        cursor = conn.cursor()
        cursor.execute('INSERT INTO notifications (account_name, alert_type, message) VALUES (?, ?, ?)',
                      (alert['account'], alert['type'], alert['message']))
        conn.commit()
        conn.close()
        print(f"Notification: {alert['account']} - {alert['type']}")
    except Exception as e:
        print(f"Failed to send notification: {e}")

def queue_notification(account: AccountData, alert_type: str, message: str, level: str = "info"):
    if account.alert_sent:
        return
    alert = {'account': account.account_name, 'type': alert_type, 'message': message, 'level': level, 'timestamp': datetime.now().isoformat()}
    try:
        notification_queue.put_nowait(alert)
        account.alert_sent = True
    except asyncio.QueueFull:
        print("Notification queue full")

def calculate_risk_status(account: AccountData) -> AccountData:
    if account.is_ftmo_1step:
        if account.daily_loss_remaining <= 0:
            if account.daily_loss_risk != "danger":
                queue_notification(account, "Daily Loss Limit", f"Daily loss limit exceeded! Remaining: ${account.daily_loss_remaining:.2f}", "danger")
            account.daily_loss_risk = "danger"
        elif account.daily_loss_remaining < account.challenge_size * 0.01:
            if account.daily_loss_risk != "danger":
                queue_notification(account, "Daily Loss Warning", f"Daily loss limit almost reached! Only ${account.daily_loss_remaining:.2f} remaining", "warning")
            account.daily_loss_risk = "danger"
        elif account.daily_loss_remaining < account.challenge_size * 0.015:
            account.daily_loss_risk = "warning"
        else:
            account.daily_loss_risk = "safe"
    else:
        daily_loss_used = account.initial_balance * (account.max_daily_loss_pct / 100) - account.daily_loss_remaining
        daily_loss_pct_used = (daily_loss_used / (account.initial_balance * account.max_daily_loss_pct / 100)) * 100 if account.initial_balance > 0 else 0
        if daily_loss_pct_used >= 100:
            if account.daily_loss_risk != "danger":
                queue_notification(account, "Daily Loss Limit", f"Daily loss limit exceeded! Used: {daily_loss_pct_used:.1f}%", "danger")
            account.daily_loss_risk = "danger"
        elif daily_loss_pct_used >= 80:
            if account.daily_loss_risk != "warning":
                queue_notification(account, "Daily Loss Warning", f"Daily loss at {daily_loss_pct_used:.1f}% of limit", "warning")
            account.daily_loss_risk = "warning"
        else:
            account.daily_loss_risk = "safe"
    
    if account.total_loss_remaining <= 0:
        if account.total_loss_risk != "danger":
            queue_notification(account, "Total Loss Limit", "Total loss limit exceeded! Account at risk!", "danger")
        account.total_loss_risk = "danger"
    elif account.total_loss_remaining < account.challenge_size * 0.02:
        if account.total_loss_risk != "danger":
            queue_notification(account, "Total Loss Warning", f"Total loss limit almost reached! Only ${account.total_loss_remaining:.2f} remaining", "danger")
        account.total_loss_risk = "danger"
    elif account.total_loss_remaining < account.challenge_size * 0.05:
        account.total_loss_risk = "warning"
    else:
        account.total_loss_risk = "safe"
    
    if account.profit_progress_pct >= 100:
        if account.profit_target_risk != "completed":
            queue_notification(account, "Profit Target Reached", f"🎉 Profit target achieved! Progress: {account.profit_progress_pct:.1f}%", "info")
        account.profit_target_risk = "completed"
    elif account.profit_progress_pct >= 80:
        account.profit_target_risk = "close"
    elif account.profit_progress_pct >= 50:
        account.profit_target_risk = "progress"
    else:
        account.profit_target_risk = "pending"
    
    if account.daily_loss_alert_pct > 0 and account.today_pnl_pct <= -account.daily_loss_alert_pct:
        if not account.pnl_alert_triggered:
            queue_notification(account, "PnL Alert", f"Daily PnL dropped {account.today_pnl_pct:.1f}% (alert at -{account.daily_loss_alert_pct}%)", "warning")
        account.pnl_alert_triggered = True
    elif account.daily_profit_alert_pct > 0 and account.today_pnl_pct >= account.daily_profit_alert_pct:
        if not account.pnl_alert_triggered:
            queue_notification(account, "PnL Alert", f"Daily PnL reached +{account.today_pnl_pct:.1f}% (alert at +{account.daily_profit_alert_pct}%)", "info")
        account.pnl_alert_triggered = True
    else:
        account.pnl_alert_triggered = False
        account.alert_sent = False
    
    return account

async def zmq_receiver():
    context = zmq.asyncio.Context()
    socket = context.socket(zmq.REP)
    socket.bind("tcp://0.0.0.0:5555")
    print("ZeroMQ server listening on port 5555...")
    while True:
        try:
            message = await socket.recv_string()
            data = json.loads(message)
            await process_account_data(data)
            await socket.send_string("OK")
            await broadcast_update()
        except Exception as e:
            print(f"Error processing message: {e}")
            await socket.send_string("ERROR")

async def process_account_data(data: dict):
    async with data_lock:
        account_name = data['account_name']
        prev_alert_sent = accounts.get(account_name, AccountData(**data)).alert_sent if account_name in accounts else False
        account = AccountData(
            timestamp=data['timestamp'], account_name=account_name, account_type=data['account_type'],
            prop_firm=data.get('prop_firm', ''), login=data['login'], company=data['company'],
            server=data['server'], currency=data['currency'], is_cent=data['is_cent'],
            is_ftmo_1step=data.get('is_ftmo_1step', False), balance=data['balance'], equity=data['equity'],
            margin=data['margin'], free_margin=data['free_margin'], profit=data['profit'],
            open_profit=data['open_profit'], margin_level=data['margin_level'],
            positions_count=data['positions_count'], open_volume=data['open_volume'],
            challenge_size=data['challenge_size'], initial_balance=data.get('initial_balance', data['balance']),
            highest_balance=data.get('highest_balance', data['balance']),
            yesterday_balance=data.get('yesterday_balance', data['balance']),
            daily_loss_limit=data.get('daily_loss_limit', 0), daily_loss_remaining=data.get('daily_loss_remaining', 0),
            total_loss_limit=data.get('total_loss_limit', 0), total_loss_remaining=data.get('total_loss_remaining', 0),
            profit_target_remaining=data.get('profit_target_remaining', 0), profit_progress_pct=data.get('profit_progress_pct', 0),
            best_day_profit=data.get('best_day_profit', 0), best_day_ratio=data.get('best_day_ratio', 0),
            best_day_remaining=data.get('best_day_remaining', 0), best_day_passed=data.get('best_day_passed', False),
            max_daily_loss_pct=data.get('max_daily_loss_pct', 5), max_total_loss_pct=data.get('max_total_loss_pct', 10),
            profit_target_pct=data.get('profit_target_pct', 10), today_pnl=data.get('today_pnl', 0),
            today_pnl_pct=data.get('today_pnl_pct', 0), week_pnl=data.get('week_pnl', 0),
            month_pnl=data.get('month_pnl', 0), total_pnl=data.get('total_pnl', 0),
            total_pnl_pct=data.get('total_pnl_pct', 0), avg_daily_pnl=data.get('avg_daily_pnl', 0),
            win_rate=data.get('win_rate', 0), profitable_days=data.get('profitable_days', 0),
            losing_days=data.get('losing_days', 0), max_drawdown=data.get('max_drawdown', 0),
            max_drawdown_pct=data.get('max_drawdown_pct', 0), sharpe_ratio=data.get('sharpe_ratio', 0),
            trading_days=data.get('trading_days', 0), daily_loss_alert_pct=data.get('daily_loss_alert_pct', 5),
            daily_profit_alert_pct=data.get('daily_profit_alert_pct', 0), last_seen=datetime.now(), status="online",
            alert_sent=prev_alert_sent
        )
        account = calculate_risk_status(account)
        accounts[account_name] = account
        save_to_history(account)

def save_to_history(account: AccountData):
    conn = sqlite3.connect('mt4_monitor.db')
    cursor = conn.cursor()
    cursor.execute('SELECT timestamp FROM history WHERE account_name = ? ORDER BY timestamp DESC LIMIT 1', (account.account_name,))
    result = cursor.fetchone()
    should_save = True
    if result:
        if account.timestamp - result[0] < 300:
            should_save = False
    if should_save:
        cursor.execute('INSERT INTO history (account_name, timestamp, balance, equity, profit, today_pnl, total_pnl, best_day_ratio, profit_progress_pct) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                      (account.account_name, account.timestamp, account.balance, account.equity, account.profit, account.today_pnl, account.total_pnl, account.best_day_ratio, account.profit_progress_pct))
        conn.commit()
    conn.close()

async def broadcast_update():
    if not active_connections:
        return
    async with data_lock:
        data = {name: acc.to_dict() for name, acc in accounts.items()}
    message = json.dumps({"type": "update", "data": data, "timestamp": datetime.now().isoformat()})
    disconnected = []
    for connection in active_connections:
        try:
            await connection.send_text(message)
        except:
            disconnected.append(connection)
    for conn in disconnected:
        if conn in active_connections:
            active_connections.remove(conn)

async def check_offline_accounts():
    while True:
        await asyncio.sleep(30)
        async with data_lock:
            now = datetime.now()
            for account in accounts.values():
                if account.last_seen and (now - account.last_seen).seconds > 60:
                    account.status = "offline"
        await broadcast_update()

app = FastAPI(title="MT4/5 Account Monitor")

@app.on_event("startup")
async def startup():
    init_database()
    asyncio.create_task(zmq_receiver())
    asyncio.create_task(check_offline_accounts())
    asyncio.create_task(notification_worker())
    print(f"Server started at http://0.0.0.0:8000")
    print(f"Auth enabled: {ENABLE_AUTH}")

@app.get("/", response_class=HTMLResponse)
async def dashboard(credentials: HTTPBasicCredentials = Depends(verify_credentials)):
    return HTMLResponse(content=get_dashboard_html())

@app.get("/manifest.json")
async def manifest():
    return FileResponse("static/manifest.json")

@app.get("/sw.js")
async def service_worker():
    return FileResponse("static/sw.js")

@app.get("/api/accounts")
async def get_accounts(credentials: HTTPBasicCredentials = Depends(verify_credentials)):
    async with data_lock:
        return {name: acc.to_dict() for name, acc in accounts.items()}

@app.get("/api/accounts/{account_name}/history")
async def get_account_history(account_name: str, hours: int = 24, credentials: HTTPBasicCredentials = Depends(verify_credentials)):
    conn = sqlite3.connect('mt4_monitor.db')
    cursor = conn.cursor()
    since = int((datetime.now() - timedelta(hours=hours)).timestamp())
    cursor.execute('SELECT timestamp, balance, equity, profit, today_pnl, total_pnl, best_day_ratio, profit_progress_pct FROM history WHERE account_name = ? AND timestamp > ? ORDER BY timestamp', (account_name, since))
    rows = cursor.fetchall()
    conn.close()
    return [{"timestamp": r[0], "balance": r[1], "equity": r[2], "profit": r[3], "today_pnl": r[4], "total_pnl": r[5], "best_day_ratio": r[6], "profit_progress_pct": r[7]} for r in rows]

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, credentials: HTTPBasicCredentials = Depends(verify_credentials)):
    await websocket.accept()
    active_connections.append(websocket)
    try:
        async with data_lock:
            data = {name: acc.to_dict() for name, acc in accounts.items()}
        await websocket.send_text(json.dumps({"type": "init", "data": data}))
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        if websocket in active_connections:
            active_connections.remove(websocket)

def get_dashboard_html():
    return open('dashboard.html').read() if os.path.exists('dashboard.html') else get_default_dashboard()

def get_default_dashboard():
    return '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="#0a0e14">
    <link rel="manifest" href="/manifest.json">
    <title>MT4/5 Account Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0a0e14; color: #e1e8ed; padding: 20px; line-height: 1.5; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; padding-bottom: 15px; border-bottom: 1px solid #1e2530; }
        .header h1 { font-size: 22px; color: #fff; }
        .header h1 span { color: #3b82f6; }
        .status { display: flex; gap: 20px; font-size: 13px; }
        .status-item { display: flex; align-items: center; gap: 6px; }
        .dot { width: 8px; height: 8px; border-radius: 50%; background: #10b981; }
        .dot.offline { background: #ef4444; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; }
        .card { background: #111820; border-radius: 10px; padding: 16px; border: 1px solid #1e2530; }
        .card-label { font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
        .card-value { font-size: 20px; font-weight: 600; color: #fff; }
        .card-value.positive { color: #10b981; } .card-value.negative { color: #ef4444; } .card-value.warning { color: #f59e0b; }
        .filters { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
        .filter-btn { padding: 6px 14px; background: #111820; border: 1px solid #1e2530; border-radius: 16px; color: #64748b; cursor: pointer; font-size: 13px; transition: all 0.2s; }
        .filter-btn:hover, .filter-btn.active { background: #3b82f6; color: #fff; border-color: #3b82f6; }
        .accounts-table { background: #111820; border-radius: 10px; overflow: hidden; border: 1px solid #1e2530; }
        .table-header { display: grid; grid-template-columns: 1.8fr 1fr 0.9fr 0.9fr 0.9fr 0.9fr 0.7fr 0.7fr 80px; padding: 12px 16px; background: #1a2332; font-size: 11px; font-weight: 600; color: #64748b; text-transform: uppercase; }
        .account-row { display: grid; grid-template-columns: 1.8fr 1fr 0.9fr 0.9fr 0.9fr 0.9fr 0.7fr 0.7fr 80px; padding: 14px 16px; border-bottom: 1px solid #1e2530; align-items: center; font-size: 13px; }
        .account-row:hover { background: #1a2332; } .account-row.offline { opacity: 0.5; } .account-row:last-child { border-bottom: none; }
        .account-info { display: flex; flex-direction: column; gap: 3px; }
        .account-name { font-weight: 600; color: #fff; }
        .account-meta { font-size: 11px; color: #64748b; display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }
        .badge { font-size: 9px; padding: 1px 5px; border-radius: 3px; font-weight: 600; }
        .badge.live { background: #10b98120; color: #10b981; } .badge.cent { background: #f59e0b20; color: #f59e0b; }
        .badge.ftmo { background: #8b5cf620; color: #8b5cf6; } .badge.ftmo-1step { background: #ec489920; color: #ec4899; }
        .badge.darwinex { background: #06b6d420; color: #06b6d4; } .badge.offline { background: #ef444420; color: #ef4444; }
        .badge.alert { background: #ef444420; color: #ef4444; animation: pulse 1.5s infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .value { font-family: 'SF Mono', monospace; font-size: 13px; } .value.positive { color: #10b981; } .value.negative { color: #ef4444; }
        .pnl-stack { display: flex; flex-direction: column; gap: 2px; } .pnl-sub { font-size: 10px; color: #64748b; }
        .progress-bar { width: 100%; height: 4px; background: #1e2530; border-radius: 2px; overflow: hidden; margin-top: 4px; }
        .progress-fill { height: 100%; border-radius: 2px; transition: width 0.3s; }
        .progress-fill.safe { background: #10b981; } .progress-fill.warning { background: #f59e0b; } .progress-fill.danger { background: #ef4444; }
        .connection-status { position: fixed; top: 20px; right: 20px; padding: 6px 12px; border-radius: 20px; font-size: 11px; font-weight: 500; }
        .connection-status.connected { background: #10b98120; color: #10b981; } .connection-status.disconnected { background: #ef444420; color: #ef4444; }
        @media (max-width: 1200px) { .table-header, .account-row { grid-template-columns: 1.5fr 1fr 1fr 1fr; } .table-header > *:nth-child(n+5), .account-row > *:nth-child(n+5) { display: none; } }
    </style>
</head>
<body>
    <div class="connection-status disconnected" id="connStatus">Disconnected</div>
    <div class="header">
        <h1>📊 MT4/5 <span>Monitor</span></h1>
        <div class="status">
            <div class="status-item"><div class="dot"></div><span>Online: <strong id="onlineCount">0</strong></span></div>
            <div class="status-item"><div class="dot offline"></div><span>Offline: <strong id="offlineCount">0</strong></span></div>
        </div>
    </div>
    <div class="summary-cards">
        <div class="card"><div class="card-label">Total Equity</div><div class="card-value" id="totalEquity">$0.00</div></div>
        <div class="card"><div class="card-label">Today PnL</div><div class="card-value" id="todayPnL">$0.00</div></div>
        <div class="card"><div class="card-label">Week PnL</div><div class="card-value" id="weekPnL">$0.00</div></div>
        <div class="card"><div class="card-label">Month PnL</div><div class="card-value" id="monthPnL">$0.00</div></div>
        <div class="card"><div class="card-label">Real Accounts</div><div class="card-value" id="personalCount">0</div></div>
        <div class="card"><div class="card-label">Prop Firm</div><div class="card-value" id="propCount">0</div></div>
        <div class="card"><div class="card-label">Alerts</div><div class="card-value warning" id="alertCount">0</div></div>
    </div>
    <div class="filters">
        <button class="filter-btn active" data-filter="all">All</button>
        <button class="filter-btn" data-filter="personal">🏦 Real</button>
        <button class="filter-btn" data-filter="prop">🎯 Prop</button>
        <button class="filter-btn" data-filter="LIVE">🔴 Live</button>
        <button class="filter-btn" data-filter="CENT">🟡 Cent</button>
        <button class="filter-btn" data-filter="DEMO">🔵 Demo</button>
        <button class="filter-btn" data-filter="PROP_FTMO">🟣 FTMO</button>
        <button class="filter-btn" data-filter="PROP_DARWINEX">🟢 Darwinex</button>
    </div>
    <div class="accounts-table">
        <div class="table-header"><div>Account</div><div>Equity / Target</div><div>Today PnL</div><div>Week PnL</div><div>Total PnL</div><div>Win Rate</div><div>Drawdown</div><div>Positions</div><div>Status</div></div>
        <div id="accountsList"></div>
    </div>
    <script>
        let ws, accounts = {}, currentFilter = 'all';
        function connect() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
            ws.onopen = () => { document.getElementById('connStatus').className = 'connection-status connected'; document.getElementById('connStatus').textContent = 'Connected'; };
            ws.onclose = () => { document.getElementById('connStatus').className = 'connection-status disconnected'; document.getElementById('connStatus').textContent = 'Disconnected'; setTimeout(connect, 3000); };
            ws.onmessage = (event) => { const msg = JSON.parse(event.data); if (msg.type === 'init' || msg.type === 'update') { accounts = msg.data; render(); } };
        }
        const fmtMoney = v => v == null ? '$0.00' : '$' + parseFloat(v).toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});
        const fmtPct = v => v == null ? '0%' : parseFloat(v).toFixed(1) + '%';
        const clsPnL = v => parseFloat(v || 0) >= 0 ? 'positive' : 'negative';
        function getBadgeClass(type, is1step) { if (is1step) return 'ftmo-1step'; return {CENT: 'cent', PROP_FTMO: 'ftmo', PROP_DARWINEX: 'darwinex'}[type] || 'live'; }
        function render() {
            let totals = {equity: 0, today: 0, week: 0, month: 0};
            let counts = {online: 0, offline: 0, alert: 0, personal: 0, prop: 0};
            const filtered = Object.values(accounts).filter(a => { if (currentFilter === 'all') return true; if (currentFilter === 'personal') return ['LIVE', 'CENT'].includes(a.account_type); if (currentFilter === 'prop') return ['PROP_FTMO', 'PROP_DARWINEX'].includes(a.account_type); return a.account_type === currentFilter; });
            Object.values(accounts).forEach(a => { if (['LIVE', 'CENT'].includes(a.account_type)) counts.personal++; if (['PROP_FTMO', 'PROP_DARWINEX'].includes(a.account_type)) counts.prop++; });
            filtered.forEach(a => { totals.equity += a.equity || 0; totals.today += a.today_pnl || 0; totals.week += a.week_pnl || 0; totals.month += a.month_pnl || 0; counts.online += a.status === 'online' ? 1 : 0; counts.offline += a.status === 'offline' ? 1 : 0; counts.alert += (a.daily_loss_risk === 'danger' || a.total_loss_risk === 'danger' || a.pnl_alert_triggered) ? 1 : 0; });
            document.getElementById('totalEquity').textContent = fmtMoney(totals.equity); ['todayPnL', 'weekPnL', 'monthPnL'].forEach((id, i) => { const el = document.getElementById(id); const vals = [totals.today, totals.week, totals.month]; el.textContent = fmtMoney(vals[i]); el.className = 'card-value ' + clsPnL(vals[i]); }); document.getElementById('personalCount').textContent = counts.personal; document.getElementById('propCount').textContent = counts.prop; document.getElementById('alertCount').textContent = counts.alert; document.getElementById('onlineCount').textContent = counts.online; document.getElementById('offlineCount').textContent = counts.offline;
            document.getElementById('accountsList').innerHTML = filtered.map(a => { const offline = a.status === 'offline'; const is1step = a.is_ftmo_1step; const progress = is1step ? `<div class="pnl-stack"><span class="value ${clsPnL(a.profit_progress_pct)}">${fmtPct(a.profit_progress_pct)}</span><div class="progress-bar"><div class="progress-fill ${a.profit_progress_pct >= 100 ? 'safe' : 'warning'}" style="width:${Math.min(a.profit_progress_pct,100)}%"></div></div></div>` : `<div class="pnl-stack"><span class="value ${clsPnL(a.total_pnl)}">${fmtMoney(a.total_pnl)}</span><span class="pnl-sub">${fmtPct(a.total_pnl_pct)}</span></div>`; const dd = a.max_drawdown_pct > 0 ? `<div class="pnl-stack"><span class="value negative">-${fmtPct(a.max_drawdown_pct)}</span><span class="pnl-sub">${fmtMoney(a.max_drawdown)}</span></div>` : '-'; const status = offline ? '<span class="badge offline">OFFLINE</span>' : a.pnl_alert_triggered ? '<span class="badge alert">ALERT</span>' : a.daily_loss_risk === 'danger' || a.total_loss_risk === 'danger' ? '<span class="badge alert">DANGER</span>' : '<span class="badge live">OK</span>'; return `<div class="account-row ${offline ? 'offline' : ''}"><div class="account-info"><div class="account-name">${a.account_name}</div><div class="account-meta"><span class="badge ${getBadgeClass(a.account_type, is1step)}">${is1step ? 'FTMO 1-STEP' : (a.account_type === 'LIVE' ? 'LIVE' : a.account_type)}</span><span>${a.server}</span></div></div><div>${progress}</div><div class="pnl-stack"><span class="value ${clsPnL(a.today_pnl)}">${fmtMoney(a.today_pnl)}</span><span class="pnl-sub">${fmtPct(a.today_pnl_pct)}</span></div><div class="pnl-stack"><span class="value ${clsPnL(a.week_pnl)}">${fmtMoney(a.week_pnl)}</span></div><div class="pnl-stack"><span class="value ${clsPnL(a.total_pnl)}">${fmtMoney(a.total_pnl)}</span><span class="pnl-sub">${a.trading_days || 0} days</span></div><div class="pnl-stack"><span class="value">${a.win_rate ? a.win_rate.toFixed(0) + '%' : '-'}</span><span class="pnl-sub">${a.profitable_days || 0}W/${a.losing_days || 0}L</span></div><div>${dd}</div><div class="value">${a.positions_count || 0}</div><div>${status}</div></div>`; }).join('');
        }
        document.querySelectorAll('.filter-btn').forEach(btn => { btn.addEventListener('click', () => { document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active')); btn.classList.add('active'); currentFilter = btn.dataset.filter; render(); }); });
        if ('serviceWorker' in navigator) { navigator.serviceWorker.register('/sw.js').catch(console.error); }
        connect();
    </script>
</body>
</html>'''

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
'@

$serverCode | Out-File -FilePath "$InstallDir\server.py" -Encoding UTF8
Write-Host "✅ server.py created" -ForegroundColor Green

# Create manifest.json
$manifest = @'{"name": "MT4/5 Account Monitor", "short_name": "MT4 Monitor", "start_url": "/", "display": "standalone", "background_color": "#0a0e14", "theme_color": "#0a0e14", "icons": [{"src": "/icon-192x192.png", "sizes": "192x192"}, {"src": "/icon-512x512.png", "sizes": "512x512"}]}'@
$manifest | Out-File -FilePath "$InstallDir\static\manifest.json" -Encoding UTF8

# Create sw.js
$sw = @'const CACHE_NAME='mt4-monitor-v1';const urlsToCache=['/','/manifest.json'];self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(urlsToCache)))});self.addEventListener('fetch',e=>{e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)))});'@
$sw | Out-File -FilePath "$InstallDir\static\sw.js" -Encoding UTF8

Write-Host "✅ Static files created" -ForegroundColor Green

# Configure Windows Firewall
Write-Host "🛡️  Configuring Windows Firewall..." -ForegroundColor Green
try {
    New-NetFirewallRule -DisplayName "MT4 Monitor ZeroMQ" -Direction Inbound -Protocol TCP -LocalPort 5555 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "MT4 Monitor Web" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -ErrorAction SilentlyContinue
    Write-Host "✅ Firewall rules created" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Could not create firewall rules automatically. Please add manually." -ForegroundColor Yellow
}

# Create startup script
$startupScript = @"
@echo off
cd /d $InstallDir
python server.py
pause
"@
$startupScript | Out-File -FilePath "$InstallDir\start.bat" -Encoding ASCII

# Create service installer script
$serviceScript = @"
# Run as Administrator to install as Windows Service
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run as Administrator" -ForegroundColor Red
    exit 1
}

# Download NSSM if not exists
if (-not (Test-Path "C:\Windows\System32\nssm.exe")) {
    Write-Host "Downloading NSSM..."
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile "$env:TEMP\nssm.zip"
    Expand-Archive "$env:TEMP\nssm.zip" -DestinationPath "$env:TEMP\nssm"
    Copy-Item "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" "C:\Windows\System32\"
}

# Install service
& nssm install MT4Monitor "$(Get-Command python).Source" "$InstallDir\server.py"
& nssm set MT4Monitor DisplayName "MT4/5 Account Monitor"
& nssm set MT4Monitor Start SERVICE_AUTO_START
& nssm start MT4Monitor

Write-Host "Service installed and started!" -ForegroundColor Green
"@
$serviceScript | Out-File -FilePath "$InstallDir\install-service.ps1" -Encoding UTF8

Write-Host ""
Write-Host "🎉 Installation Complete!" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Installation Directory: $InstallDir" -ForegroundColor Cyan
Write-Host "🌐 Dashboard URL: http://$ServerIP`:8000" -ForegroundColor Cyan
Write-Host "👤 Login: $AdminUser / $AdminPass" -ForegroundColor Cyan
Write-Host ""
Write-Host "🚀 To start the server:" -ForegroundColor Yellow
Write-Host "   Option 1 - Run manually: cd $InstallDir && python server.py" -ForegroundColor White
Write-Host "   Option 2 - Run batch: $InstallDir\start.bat" -ForegroundColor White
Write-Host "   Option 3 - Install as service: Right-click install-service.ps1 → Run with PowerShell" -ForegroundColor White
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Start the server using one of the options above" -ForegroundColor White
Write-Host "   2. Open http://$ServerIP`:8000 in browser" -ForegroundColor White
Write-Host "   3. Configure AccountMonitorEA.mq5 in MT4/5" -ForegroundColor White
Write-Host "   4. Set Server IP to: $ServerIP" -ForegroundColor White
Write-Host ""
Write-Host "⚠️  Make sure Windows Firewall allows ports 5555 and 8000" -ForegroundColor Yellow
Write-Host "   (This script attempted to add them automatically)" -ForegroundColor Gray
