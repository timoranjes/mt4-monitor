# MT4/5 Account Monitor - EA Configuration

## VPS Server Details
- **IP**: 216.66.53.132
- **Dashboard**: http://216.66.53.132:8000
- **Username**: timoranjes
- **Password**: 19931017lzc

---

## EA Configuration Template

### For Live Account (实盘账户)
```
=== Account Configuration ===
Account Name: Live-ICMarkets-1
Account Type: LIVE
Prop Firm: (empty)
Challenge Size: 0
Is Cent Account: false

=== FTMO 1-Step Rules ===
Enable FTMO 1-Step Rules: false
Max Daily Loss %: 5
Max Total Loss %: 10
Profit Target %: 10
Best Day Max %: 50

=== PnL Alerts ===
Enable PnL Tracking: true
Daily Loss Alert %: 5
Daily Profit Alert %: 0

=== Server Configuration ===
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

### For Cent Account
```
=== Account Configuration ===
Account Name: Cent-Exness-1
Account Type: CENT
Prop Firm: (empty)
Challenge Size: 0
Is Cent Account: true              ← IMPORTANT

=== FTMO 1-Step Rules ===
Enable FTMO 1-Step Rules: false

=== PnL Alerts ===
Enable PnL Tracking: true
Daily Loss Alert %: 5
Daily Profit Alert %: 0

=== Server Configuration ===
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

### For FTMO 1-Step Account
```
=== Account Configuration ===
Account Name: FTMO-50K-1
Account Type: PROP_FTMO
Prop Firm: FTMO
Challenge Size: 50000
Is Cent Account: false

=== FTMO 1-Step Rules ===
Enable FTMO 1-Step Rules: true    ← IMPORTANT
Max Daily Loss %: 3
Max Total Loss %: 10
Profit Target %: 10
Best Day Max %: 50

=== PnL Alerts ===
Enable PnL Tracking: true
Daily Loss Alert %: 3              ← Match FTMO rule
Daily Profit Alert %: 0

=== Server Configuration ===
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

### For Darwinex Account
```
=== Account Configuration ===
Account Name: Darwinex-Zero-1
Account Type: PROP_DARWINEX
Prop Firm: DARWINEX
Challenge Size: 0
Is Cent Account: false

=== FTMO 1-Step Rules ===
Enable FTMO 1-Step Rules: false

=== PnL Alerts ===
Enable PnL Tracking: true
Daily Loss Alert %: 5
Daily Profit Alert %: 0

=== Server Configuration ===
Server IP: 216.66.53.132
Server Port: 5555
Update Interval: 5
```

---

## Quick Start - Test with 1 Account

### Step 1: Upload to VPS
```bash
# SSH to your VPS
ssh timoranjes@216.66.53.132

# Create directory
mkdir -p ~/mt4_monitor/static
cd ~/mt4_monitor

# Upload files (from your local machine)
scp server.py timoranjes@216.66.53.132:~/mt4_monitor/
scp -r static timoranjes@216.66.53.132:~/mt4_monitor/
```

### Step 2: Install & Start
```bash
# On VPS
sudo apt update
sudo apt install python3-pip -y
pip3 install fastapi uvicorn pyzmq websockets

# Start server
python3 ~/mt4_monitor/server.py
```

### Step 3: Open Firewall
```bash
sudo ufw allow 5555/tcp
sudo ufw allow 8000/tcp
```

### Step 4: Configure EA in MT4/5
1. Open MT4/5
2. Copy `AccountMonitorEA.mq5` to `MQL5/Experts/`
3. Compile (F7)
4. Attach to any chart
5. Use config above with your account details

### Step 5: Verify
1. Open http://216.66.53.132:8000
2. Login: timoranjes / 19931017lzc
3. You should see your account data

---

## Systemd Service (Auto-start)

Create `/etc/systemd/system/mt4-monitor.service`:

```ini
[Unit]
Description=MT4/5 Account Monitor
After=network.target

[Service]
Type=simple
User=timoranjes
WorkingDirectory=/home/timoranjes/mt4_monitor
ExecStart=/usr/bin/python3 /home/timoranjes/mt4_monitor/server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mt4-monitor
sudo systemctl start mt4-monitor
sudo systemctl status mt4-monitor
```

---

## All 11 Accounts Naming Suggestion

| # | Account Name | Type | VPS |
|---|-------------|------|-----|
| 1 | Live-ICMarkets-1 | LIVE | VPS 1 |
| 2 | Live-ICMarkets-2 | LIVE | VPS 2 |
| 3 | Cent-Exness-1 | CENT | VPS 1 |
| 4 | Cent-Exness-2 | CENT | VPS 2 |
| 5 | FTMO-50K-1 | PROP_FTMO | VPS 1 |
| 6 | FTMO-50K-2 | PROP_FTMO | VPS 2 |
| 7 | FTMO-100K-1 | PROP_FTMO | VPS 3 |
| 8 | FTMO-100K-2 | PROP_FTMO | VPS 3 |
| 9 | Darwinex-Zero-1 | PROP_DARWINEX | VPS 1 |
| 10 | Darwinex-Zero-2 | PROP_DARWINEX | VPS 2 |
| 11 | Demo-Test-1 | DEMO | Any |

---

## Troubleshooting

### EA Shows "Failed to connect"
- Check firewall: `sudo ufw status`
- Verify server running: `sudo netstat -tlnp | grep 5555`
- Check IP is correct: 216.66.53.132

### Dashboard Shows "Disconnected"
- WebSocket blocked? Try different browser
- Check port 8000: `sudo netstat -tlnp | grep 8000`

### No Data Showing
- Check EA is attached to chart (green smiley)
- Check Experts tab for errors
- Verify account name is unique per account

---

Ready to deploy!
