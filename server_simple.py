from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, status, Request
from fastapi.responses import HTMLResponse, JSONResponse
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

# Fix for Windows Python 3.12 + zmq compatibility
import sys
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

#--- 配置 ---
ADMIN_USERNAME = os.getenv("MT4_ADMIN_USER", "timoranjes")
ADMIN_PASSWORD = os.getenv("MT4_ADMIN_PASS", "19931017lzc")
ENABLE_AUTH = os.getenv("MT4_ENABLE_AUTH", "true").lower() == "true"
TELEGRAM_ENABLED = os.getenv("MT4_TELEGRAM_ENABLED", "true").lower() == "true"
TELEGRAM_CHAT_ID = os.getenv("MT4_TELEGRAM_CHAT_ID", "6692882496")

security = HTTPBasic()

def verify_credentials(credentials):
    if not ENABLE_AUTH:
        return True
    is_correct_username = secrets.compare_digest(credentials.username, ADMIN_USERNAME)
    is_correct_password = secrets.compare_digest(credentials.password, ADMIN_PASSWORD)
    if not (is_correct_username and is_correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return True

#--- 数据模型 ---
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

#--- 全局状态 ---
accounts: Dict[str, AccountData] = {}
active_connections: List[WebSocket] = []
data_lock = asyncio.Lock()
notification_queue: asyncio.Queue = asyncio.Queue()

#--- 数据库初始化 ---
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
    conn.commit()
    conn.close()

#--- 通知处理器 ---
async def notification_worker():
    while True:
        try:
            alert = await notification_queue.get()
            await asyncio.sleep(0)
            notification_queue.task_done()
        except Exception as e:
            print(f"Notification error: {e}")
            await asyncio.sleep(5)

def queue_notification(account: AccountData, alert_type: str, message: str, level: str = "info"):
    if account.alert_sent:
        return
    account.alert_sent = True

def calculate_risk_status(account: AccountData) -> AccountData:
    if account.today_pnl_pct <= -account.daily_loss_alert_pct:
        account.pnl_alert_triggered = True
    return account

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

#--- 处理HTTP数据 ---
async def process_account_data(data: dict):
    async with data_lock:
        account_name = data.get('account_name', 'Unknown')
        
        account = AccountData(
            timestamp=data.get('timestamp', int(datetime.now().timestamp())),
            account_name=account_name,
            account_type=data.get('account_type', 'LIVE'),
            prop_firm=data.get('prop_firm', ''),
            login=data.get('login', 0),
            company=data.get('company', ''),
            server=data.get('server', ''),
            currency=data.get('currency', 'USD'),
            is_cent=data.get('is_cent', False),
            is_ftmo_1step=data.get('is_ftmo_1step', False),
            balance=data.get('balance', 0),
            equity=data.get('equity', 0),
            margin=data.get('margin', 0),
            free_margin=data.get('free_margin', 0),
            profit=data.get('profit', 0),
            open_profit=data.get('open_profit', 0),
            margin_level=data.get('margin_level', 0),
            positions_count=data.get('positions_count', 0),
            open_volume=data.get('open_volume', 0),
            challenge_size=data.get('challenge_size', 0),
            initial_balance=data.get('initial_balance', data.get('balance', 0)),
            highest_balance=data.get('highest_balance', data.get('balance', 0)),
            yesterday_balance=data.get('yesterday_balance', data.get('balance', 0)),
            daily_loss_limit=data.get('daily_loss_limit', 0),
            daily_loss_remaining=data.get('daily_loss_remaining', 0),
            total_loss_limit=data.get('total_loss_limit', 0),
            total_loss_remaining=data.get('total_loss_remaining', 0),
            profit_target_remaining=data.get('profit_target_remaining', 0),
            profit_progress_pct=data.get('profit_progress_pct', 0),
            best_day_profit=data.get('best_day_profit', 0),
            best_day_ratio=data.get('best_day_ratio', 0),
            best_day_remaining=data.get('best_day_remaining', 0),
            best_day_passed=data.get('best_day_passed', False),
            max_daily_loss_pct=data.get('max_daily_loss_pct', 5),
            max_total_loss_pct=data.get('max_total_loss_pct', 10),
            profit_target_pct=data.get('profit_target_pct', 10),
            today_pnl=data.get('today_pnl', 0),
            today_pnl_pct=data.get('today_pnl_pct', 0),
            week_pnl=data.get('week_pnl', 0),
            month_pnl=data.get('month_pnl', 0),
            total_pnl=data.get('total_pnl', 0),
            total_pnl_pct=data.get('total_pnl_pct', 0),
            avg_daily_pnl=data.get('avg_daily_pnl', 0),
            win_rate=data.get('win_rate', 0),
            profitable_days=data.get('profitable_days', 0),
            losing_days=data.get('losing_days', 0),
            max_drawdown=data.get('max_drawdown', 0),
            max_drawdown_pct=data.get('max_drawdown_pct', 0),
            sharpe_ratio=data.get('sharpe_ratio', 0),
            trading_days=data.get('trading_days', 0),
            daily_loss_alert_pct=data.get('daily_loss_alert_pct', 5),
            daily_profit_alert_pct=data.get('daily_profit_alert_pct', 0),
            last_seen=datetime.now(),
            status="online"
        )
        
        account = calculate_risk_status(account)
        accounts[account_name] = account
        save_to_history(account)

#--- HTML Dashboard ---
DASHBOARD_HTML = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>MT4/5 Monitor</title>
    <style>
        body { font-family: Arial; background: #0a0e14; color: #fff; padding: 20px; }
        .card { background: #111820; padding: 15px; border-radius: 10px; margin: 10px 0; }
        .value { font-family: monospace; }
        .positive { color: #10b981; } .negative { color: #ef4444; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #333; }
    </style>
</head>
<body>
    <h1>📊 MT4/5 Monitor</h1>
    <div id="summary"></div>
    <div id="accounts"></div>
    <script>
        const ws = new WebSocket("ws://" + location.host + "/ws");
        ws.onmessage = (e) => {
            const msg = JSON.parse(e.data);
            const acc = msg.data;
            let html = '<table><tr><th>Account</th><th>Equity</th><th>Today PnL</th></tr>';
            for (const name in acc) {
                const a = acc[name];
                const cls = a.today_pnl >= 0 ? 'positive' : 'negative';
                html += `<tr><td>${name}</td><td>$${a.equity?.toFixed(2)}</td><td class="${cls}">$${a.today_pnl?.toFixed(2)}</td></tr>`;
            }
            html += '</table>';
            document.getElementById('accounts').innerHTML = html;
        };
    </script>
</body>
</html>'''

#--- FastAPI 应用 ---
app = FastAPI(title="MT4/5 Monitor")

@app.on_event("startup")
async def startup():
    init_database()
    print(f"Server started at http://127.0.0.1:8000")
    print(f"Auth: {ENABLE_AUTH}")

# Public endpoint for EA data
@app.post("/api/data")
async def receive_data(request: Request):
    """Receive data from EA - NO AUTH REQUIRED"""
    try:
        body = await request.body()
        body_str = body.decode().strip()
        # Remove any trailing null bytes or extra data
        body_str = body_str.split('\x00')[0].strip()
        print(f"Received: {body_str[:100]}")
        data = json.loads(body_str)
        await process_account_data(data)
        await broadcast_update()
        print(f"Saved: {data.get('account_name')}, accounts: {len(accounts)}")
        return {"status": "ok"}
    except Exception as e:
        print(f"Error: {e}, body: {body.decode()[:200]}")
        return {"status": "ok"}  # Still return OK so EA doesn't retry

# Health check - public
@app.get("/health")
async def health():
    return {"status": "ok", "accounts": len(accounts)}

# Dashboard - requires auth
@app.get("/")
async def dashboard(request: Request):
    if ENABLE_AUTH:
        auth = request.headers.get("Authorization")
        if not auth or not auth.startswith("Basic "):
            return HTMLResponse(content="<h1>401 - Login Required</h1>", status_code=401)
    return HTMLResponse(content=DASHBOARD_HTML)

# WebSocket
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    try:
        async with data_lock:
            data = {name: acc.to_dict() for name, acc in accounts.items()}
        await websocket.send_text(json.dumps({"type": "init", "data": data}))
        while True:
            await websocket.receive_text()
    except:
        if websocket in active_connections:
            active_connections.remove(websocket)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
