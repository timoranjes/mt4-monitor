# MT4/5 Account Monitor - EA Configuration Guide

## Server Details
- **Tunnel URL**: https://intersection-sierra-newbie-shortcuts.trycloudflare.com (临时，重启会变)
- **Local**: http://127.0.0.1:8000
- **Login**: timoranjes / 19931017lzc

---

## Account Type Reference

| Account Type | Badge | Category |
|--------------|-------|----------|
| LIVE | 🔴 LIVE | Real Accounts |
| CENT | 🟡 CENT | Real Accounts |
| DEMO | 🔵 DEMO | Demo |
| PROP_FTMO | 🟣 FTMO | 🎯 Prop Firm |
| PROP_DARWINEX | 🟢 DARWINEX | 🎯 Prop Firm |
| PROP_5ERS | 🔵 5ERS | 🎯 Prop Firm |

---

## EA Configuration by Account Type

### 1. Live Account (实盘账户)
```ini
Account Name: Live-ICMarkets-1
Account Type: LIVE
Is Cent Account: false

Enable FTMO 1-Step Rules: false

Enable PnL Tracking: true
Daily Loss Alert %: 5
Daily Profit Alert %: 0

Server IP: 127.0.0.1
Server Port: 5555
Update Interval: 5
```

---

### 2. Cent Account
```ini
Account Name: Cent-Exness-1
Account Type: CENT
Is Cent Account: true              ← IMPORTANT

Enable FTMO 1-Step Rules: false

Enable PnL Tracking: true
Daily Loss Alert %: 5

Server IP: 127.0.0.1
Server Port: 5555
Update Interval: 5
```

---

### 3. FTMO 1-Step Challenge
```ini
Account Name: FTMO-50K-1
Account Type: PROP_FTMO
Prop Firm: FTMO
Is Cent Account: false

Enable FTMO 1-Step Rules: true    ← IMPORTANT
Max Daily Loss %: 3               ← FTMO 1-Step rule
Max Total Loss %: 10              ← FTMO 1-Step rule
Profit Target %: 10               ← FTMO 1-Step rule
Best Day Max %: 50                ← FTMO 1-Step rule

Enable PnL Tracking: true
Daily Loss Alert %: 3              ← Match FTMO rule

Server IP: 127.0.0.1
Server Port: 5555
Update Interval: 5
```

**FTMO 1-Step Rules:**
- Daily Loss: 3% (floating, based on yesterday's balance)
- Total Loss: 10% (floating, based on highest balance)
- Profit Target: 10%
- Best Day: ≤50% of total profit
- No time limit

---

### 4. Darwinex Zero
```ini
Account Name: Darwinex-Zero-1
Account Type: PROP_DARWINEX
Prop Firm: DARWINEX
Is Cent Account: false

Enable FTMO 1-Step Rules: false

Enable PnL Tracking: true
Daily Loss Alert %: 5

Server IP: 127.0.0.1
Server Port: 5555
Update Interval: 5
```

---

### 5. 5ers High Stakes (2-Step)
```ini
Account Name: 5ers-HighStakes-50K
Account Type: PROP_5ERS
Prop Firm: 5ERS
Is Cent Account: false

Enable FTMO 1-Step Rules: false    ← 5ers has different rules

Enable PnL Tracking: true
Daily Loss Alert %: 5              ← 5ers max daily loss

Server IP: 127.0.0.1
Server Port: 5555
Update Interval: 5
```

**5ers High Stakes 2-Step Rules:**
| Phase | Profit Target | Max Daily Loss | Max Total Loss | Time Limit |
|-------|--------------|----------------|----------------|------------|
| Step 1 | 8% | 5% | 10% | Unlimited |
| Step 2 | 5% | 5% | 10% | Unlimited |

- Leverage: Up to 1:100
- Profit split: Scales up to 100%
- No minimum trading days

---

## Dashboard Filters

| Filter | Shows |
|--------|-------|
| **All** | All accounts |
| **🏦 Real Accounts** | LIVE + CENT |
| **🎯 Prop Firm** | FTMO + DARWINEX + 5ERS |
| **🔴 Live** | Only LIVE accounts |
| **🟡 Cent** | Only CENT accounts |
| **🔵 Demo** | Only DEMO accounts |

---

## Naming Convention Suggestion

For 11 accounts across your VPSs:

| # | Account Name | Type | Prop Firm | VPS |
|---|-------------|------|-----------|-----|
| 1 | Live-ICMarkets-1 | LIVE | - | VPS 1 |
| 2 | Live-ICMarkets-2 | LIVE | - | VPS 2 |
| 3 | Cent-Exness-1 | CENT | - | VPS 1 |
| 4 | Cent-Exness-2 | CENT | - | VPS 2 |
| 5 | FTMO-50K-1 | PROP_FTMO | FTMO | VPS 1 |
| 6 | FTMO-50K-2 | PROP_FTMO | FTMO | VPS 2 |
| 7 | FTMO-100K-1 | PROP_FTMO | FTMO | VPS 3 |
| 8 | Darwinex-Zero-1 | PROP_DARWINEX | DARWINEX | VPS 1 |
| 9 | Darwinex-Zero-2 | PROP_DARWINEX | DARWINEX | VPS 2 |
| 10 | 5ers-HighStakes-50K | PROP_5ERS | 5ERS | VPS 1 |
| 11 | 5ers-HighStakes-100K | PROP_5ERS | 5ERS | VPS 2 |

---

## Update Server

After code changes:
```powershell
cd C:\mt4-monitor
git pull origin main
# Restart server
```

---

## Troubleshooting

### Cannot connect to server
1. Check server is running: `http://127.0.0.1:8000`
2. Check Cloudflare Tunnel is running
3. Check Windows Firewall allows port 5555

### EA cannot connect
1. Verify Server IP is `127.0.0.1` (for localhost)
2. Check port 5555 is open in Windows Firewall
3. Check MT5 Experts tab for errors

### Dashboard shows Disconnected
1. Check WebSocket connection
2. Refresh page
3. Check browser console for errors

---

## Quick Commands

```powershell
# Start server
python server.py

# Start Cloudflare Tunnel (in another window)
.\cloudflared.exe tunnel --url http://localhost:8000

# Check firewall
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*MT4*" }

# Test local connection
Invoke-WebRequest http://localhost:8000
```

---

## References

- **FTMO Rules**: https://ftmo.com/en/trading-objectives/
- **5ers Rules**: https://the5ers.com/high-stakes/
- **Darwinex**: https://www.darwinex.com/
