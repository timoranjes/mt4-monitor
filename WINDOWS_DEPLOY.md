# MT4/5 Account Monitor - Windows VPS Deployment

## VPS Server Details
- **IP**: 216.66.53.132
- **Dashboard**: http://216.66.53.132:8000
- **Username**: timoranjes
- **Password**: 19931017lzc
- **OS**: Windows

---

## Step 1: Install Python on Windows

### Option A: Microsoft Store (Recommended)
1. Open Microsoft Store
2. Search "Python 3.11"
3. Click Install

### Option B: Python.org
1. Download from https://python.org/downloads
2. Run installer
3. **IMPORTANT**: Check "Add Python to PATH"
4. Click "Install Now"

### Verify Installation
```cmd
python --version
pip --version
```

---

## Step 2: Install Dependencies

Open **Command Prompt (CMD)** or **PowerShell** as Administrator:

```cmd
pip install fastapi uvicorn pyzmq websockets
```

If `pip` not found, try:
```cmd
python -m pip install fastapi uvicorn pyzmq websockets
```

---

## Step 3: Upload Files to VPS

### Method A: RDP + Copy Paste
1. RDP to your VPS: `216.66.53.132`
2. Create folder: `C:\mt4_monitor\`
3. Copy these files:
   - `server.py`
   - `static\manifest.json`
   - `static\sw.js`
   - `AccountMonitorEA.mq5`

### Method B: SCP (if you have OpenSSH)
```bash
scp server.py timoranjes@216.66.53.132:/c:/mt4_monitor/
scp -r static timoranjes@216.66.53.132:/c:/mt4_monitor/
```

---

## Step 4: Configure Windows Firewall

### Option A: GUI
1. Open "Windows Defender Firewall"
2. Click "Advanced Settings"
3. Click "Inbound Rules" → "New Rule"
4. Select "Port" → Next
5. Select "TCP", enter port: `5555` → Next
6. Select "Allow the connection" → Next
7. Check all profiles (Domain, Private, Public) → Next
8. Name: "MT4 Monitor ZeroMQ" → Finish

9. Repeat for port `8000`
   - Name: "MT4 Monitor Web"

### Option B: PowerShell (Admin)
```powershell
# Open port 5555 (ZeroMQ)
New-NetFirewallRule -DisplayName "MT4 Monitor ZeroMQ" -Direction Inbound -Protocol TCP -LocalPort 5555 -Action Allow

# Open port 8000 (Web Dashboard)
New-NetFirewallRule -DisplayName "MT4 Monitor Web" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

---

## Step 5: Start the Server

### Method A: Command Line (Quick Test)

Open CMD or PowerShell:
```cmd
cd C:\mt4_monitor
python server.py
```

You should see:
```
ZeroMQ server listening on port 5555...
Server started. Auth: enabled
Telegram notifications: enabled
```

Keep window open. To stop, press `Ctrl+C`.

---

### Method B: Run as Windows Service (Recommended for Production)

#### Install NSSM (Service Manager)
1. Download NSSM from https://nssm.cc/download
2. Extract `nssm.exe` to `C:\Windows\System32\`

#### Create Service
Open CMD **as Administrator**:

```cmd
nssm install MT4Monitor
```

In the GUI:
- **Path**: `C:\Users\timoranjes\AppData\Local\Programs\Python\Python311\python.exe`
  (Or wherever python.exe is installed)
- **Startup directory**: `C:\mt4_monitor`
- **Arguments**: `server.py`

Click "Install service"

#### Start Service
```cmd
nssm start MT4Monitor
```

#### Check Status
```cmd
nssm status MT4Monitor
```

#### View Logs
```cmd
nssm logs MT4Monitor
```

Or check: `C:\mt4_monitor\mt4_monitor.log`

---

### Method C: Task Scheduler (Alternative)

1. Open "Task Scheduler"
2. Create Basic Task
3. Name: "MT4 Monitor"
4. Trigger: "When the computer starts"
5. Action: "Start a program"
6. Program: `C:\Users\timoranjes\AppData\Local\Programs\Python\Python311\python.exe`
7. Arguments: `C:\mt4_monitor\server.py`
8. Check "Run with highest privileges"
9. Finish

---

## Step 6: Configure EA in MT4/5

### Install ZeroMQ Library (Windows)

1. Download ZMQ for MT5: https://www.mql5.com/en/code/43672
2. Extract files:
   - `ZmqSocket.mqh` → `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\Include\zmq\`

### Compile EA

1. Copy `AccountMonitorEA.mq5` to:
   `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\Experts\`

2. Open MetaEditor
3. Open `AccountMonitorEA.mq5`
4. Press F7 to compile

### EA Configuration

Attach to any chart and use these settings:

**For Live Account:**
```
Account Name: Live-ICMarkets-1
Account Type: LIVE
Is Cent Account: false
Enable FTMO 1-Step Rules: false
Enable PnL Tracking: true
Daily Loss Alert %: 5
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

**For FTMO 1-Step:**
```
Account Name: FTMO-50K-1
Account Type: PROP_FTMO
Is Cent Account: false
Enable FTMO 1-Step Rules: true
Max Daily Loss %: 3
Max Total Loss %: 10
Profit Target %: 10
Enable PnL Tracking: true
Daily Loss Alert %: 3
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

**For Cent Account:**
```
Account Name: Cent-Exness-1
Account Type: CENT
Is Cent Account: true
Enable FTMO 1-Step Rules: false
Enable PnL Tracking: true
Daily Loss Alert %: 5
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

---

## Step 7: Access Dashboard

1. Open browser: http://216.66.53.132:8000
2. Login:
   - Username: `timoranjes`
   - Password: `19931017lzc`
3. You should see your account data

---

## Step 8: Install as PWA on Mobile

1. Open http://216.66.53.132:8000 on phone
2. Chrome menu → "Add to Home Screen"
3. Works like a native app

---

## Troubleshooting

### "python" is not recognized
- Python not in PATH
- Solution: Reinstall Python and check "Add to PATH"

### Port 5555/8000 already in use
```cmd
# Check what's using the port
netstat -ano | findstr :5555
netstat -ano | findstr :8000

# Kill process (replace PID)
taskkill /PID [PID_NUMBER] /F
```

### EA Cannot Connect
1. Check Windows Firewall allows port 5555
2. Check server is running: `nssm status MT4Monitor`
3. Verify IP is correct: 216.66.53.132

### Dashboard Shows Disconnected
1. Check Windows Firewall allows port 8000
2. Try different browser
3. Check if server is running

---

## Quick Commands Reference

```cmd
# Start server manually
python C:\mt4_monitor\server.py

# Check if ports are listening
netstat -an | findstr "5555"
netstat -an | findstr "8000"

# Check firewall rules
netsh advfirewall firewall show rule name="MT4 Monitor"

# Service commands (if using NSSM)
nssm start MT4Monitor
nssm stop MT4Monitor
nssm restart MT4Monitor
nssm status MT4Monitor
```

---

## File Locations (Windows)

| File | Location |
|------|----------|
| Server | `C:\mt4_monitor\server.py` |
| Database | `C:\mt4_monitor\mt4_monitor.db` |
| Static files | `C:\mt4_monitor\static\` |
| EA (MT5) | `%AppData%\MetaQuotes\Terminal\*\MQL5\Experts\` |
| ZMQ Library | `%AppData%\MetaQuotes\Terminal\*\MQL5\Include\zmq\` |

---

Ready to deploy on Windows!
