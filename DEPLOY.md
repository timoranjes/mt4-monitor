# MT4/5 Account Monitor - Deployment Guide

## 🚀 VPS Deployment Steps

### 1. Upload Files to VPS

```bash
# On your VPS, create directory
mkdir -p ~/mt4_monitor/static
cd ~/mt4_monitor

# Upload these files:
# - server.py
# - AccountMonitorEA.mq5
# - static/manifest.json
# - static/sw.js
```

### 2. Install Dependencies

```bash
# Install Python dependencies
pip install fastapi uvicorn pyzmq websockets

# Or if using Python 3.11+
pip3 install fastapi uvicorn pyzmq websockets
```

### 3. Set Environment Variables

```bash
# Edit ~/.bashrc or create a startup script
export MT4_ADMIN_USER="your_username"
export MT4_ADMIN_PASS="your_secure_password"
export MT4_ENABLE_AUTH="true"
export MT4_TELEGRAM_ENABLED="true"
export MT4_TELEGRAM_CHAT_ID="6692882496"
```

Then reload:
```bash
source ~/.bashrc
```

### 4. Open Firewall Ports

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 5555/tcp  # ZeroMQ from MT4/5 EA
sudo ufw allow 8000/tcp  # Web dashboard
sudo ufw reload

# Or iptables
sudo iptables -A INPUT -p tcp --dport 5555 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8000 -j ACCEPT
```

### 5. Create Systemd Service

Create file `/etc/systemd/system/mt4-monitor.service`:

```ini
[Unit]
Description=MT4/5 Account Monitor
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/mt4_monitor
Environment="MT4_ADMIN_USER=admin"
Environment="MT4_ADMIN_PASS=your_password"
Environment="MT4_ENABLE_AUTH=true"
Environment="MT4_TELEGRAM_ENABLED=true"
Environment="MT4_TELEGRAM_CHAT_ID=6692882496"
ExecStart=/usr/bin/python3 /home/ubuntu/mt4_monitor/server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mt4-monitor
sudo systemctl start mt4-monitor
sudo systemctl status mt4-monitor
```

### 6. View Logs

```bash
sudo journalctl -u mt4-monitor -f
```

---

## 📱 Access Dashboard

After deployment, access at:
```
http://your-vps-ip:8000
```

Login with the credentials you set in environment variables.

### Install as PWA on Mobile
1. Open the URL in Chrome/Safari
2. Tap "Add to Home Screen"
3. The app will work like a native app

---

## 🔧 Single Account Test

### Step 1: Configure EA
In MT4/5, attach EA to chart with these settings:

```
=== Account Config ===
Account Name: Test-Account-1
Account Type: LIVE (or your type)
Is Cent Account: false

=== FTMO 1-Step Rules ===
Enable FTMO 1-Step Rules: false (for regular accounts)

=== PnL Alerts ===
Enable PnL Tracking: true
Daily Loss Alert %: 5
Daily Profit Alert %: 0

=== Server Config ===
Server IP: YOUR_VPS_IP
Server Port: 5555
Update Interval: 5
```

### Step 2: Verify Connection
Check server logs - you should see:
```
ZeroMQ server listening on port 5555...
```

And when EA connects:
```
Notification sent: Test-Account-1 - type
```

### Step 3: Check Dashboard
Open `http://your-vps-ip:8000` and login. You should see your account data.

---

## 🔔 Telegram Notifications

Notifications are sent automatically when:
- Daily loss limit exceeded
- Total loss limit exceeded  
- PnL alert threshold reached
- Profit target achieved

Each alert is sent **only once** until condition resets.

Example notification:
```
🚨 MT4 Monitor Alert

Account: FTMO-50K-1
Type: Daily Loss Limit
Level: DANGER

Daily loss limit exceeded! Remaining: $-234.50

2026-02-12 14:30:25
```

---

## 🔒 Security

### Change Default Password
Edit the systemd service file or set environment variables:
```bash
export MT4_ADMIN_USER="your_custom_username"
export MT4_ADMIN_PASS="your_strong_password_123!"
```

Then restart:
```bash
sudo systemctl restart mt4-monitor
```

### Disable Auth (Not Recommended)
```bash
export MT4_ENABLE_AUTH="false"
```

---

## 🐛 Troubleshooting

### EA Cannot Connect
```bash
# Check if port 5555 is listening
sudo netstat -tlnp | grep 5555

# Check firewall
sudo ufw status
```

### Dashboard Not Loading
```bash
# Check if port 8000 is listening
sudo netstat -tlnp | grep 8000

# Check service status
sudo systemctl status mt4-monitor

# View logs
sudo journalctl -u mt4-monitor -n 50
```

### Notifications Not Sending
- Check `MT4_TELEGRAM_ENABLED=true`
- Verify `MT4_TELEGRAM_CHAT_ID` is correct
- Check server logs for errors

---

## 📝 File Structure

```
~/mt4_monitor/
├── server.py              # Main server
├── static/
│   ├── manifest.json      # PWA manifest
│   └── sw.js             # Service worker
├── mt4_monitor.db        # SQLite database (auto-created)
└── README.md             # This file
```

---

## 🔄 Updating

To update the server:
```bash
sudo systemctl stop mt4-monitor
# Upload new server.py
sudo systemctl start mt4-monitor
```

---

## 💡 Production Tips

1. **Use a reverse proxy** (nginx) for SSL/HTTPS
2. **Change default ports** if needed (edit server.py)
3. **Regular backups** of `mt4_monitor.db`
4. **Monitor disk space** - logs and history grow over time

Need help with any step?
