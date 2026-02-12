# MT4 Monitor - Troubleshooting Guide

## 问题：服务器运行但无法访问

### 检查 1：确认端口监听

在 VPS 的 PowerShell (管理员) 中运行：

```powershell
# 检查端口 8000 是否在监听
netstat -an | findstr "8000"

# 应该显示类似：
# TCP    0.0.0.0:8000    0.0.0.0:0    LISTENING
```

如果没有显示，说明服务器绑定有问题。

---

### 检查 2：Windows 防火墙

```powershell
# 查看现有防火墙规则
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*MT4*" }

# 如果没有显示，手动添加：
New-NetFirewallRule -DisplayName "MT4 Monitor Web" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
New-NetFirewallRule -DisplayName "MT4 Monitor ZeroMQ" -Direction Inbound -Protocol TCP -LocalPort 5555 -Action Allow

# 验证规则已添加
netsh advfirewall firewall show rule name="MT4 Monitor Web"
```

---

### 检查 3：测试本地访问

在 VPS 上打开浏览器，访问：
```
http://localhost:8000
```

如果能打开，说明服务器正常，是防火墙/网络问题。
如果不能打开，说明服务器本身有问题。

---

### 检查 4：检查安全组/云防火墙

如果你的 VPS 是云服务器（AWS/Azure/阿里云等），还需要检查：

1. **安全组规则** - 放行 TCP 8000 端口
2. **网络 ACL** - 允许入站 8000

例如 AWS EC2：
- 进入 EC2 控制台
- 选择实例 → 安全组
- 入站规则 → 添加规则
- 类型: 自定义 TCP, 端口: 8000, 来源: 0.0.0.0/0

---

### 检查 5：修改服务器绑定

如果上述都正常，可能是绑定问题。修改 server.py：

找到这行：
```python
uvicorn.run(app, host="0.0.0.0", port=8000)
```

改为你的实际 IP：
```python
uvicorn.run(app, host="216.66.53.132", port=8000)
```

然后重启服务器。

---

## 快速修复脚本

在 VPS PowerShell (管理员) 中运行：

```powershell
# 1. 停止现有服务器 (Ctrl+C 或关闭窗口)

# 2. 检查并添加防火墙规则
$rule1 = Get-NetFirewallRule -DisplayName "MT4 Monitor Web" -ErrorAction SilentlyContinue
if (-not $rule1) {
    Write-Host "Adding firewall rule for port 8000..."
    New-NetFirewallRule -DisplayName "MT4 Monitor Web" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
}

$rule2 = Get-NetFirewallRule -DisplayName "MT4 Monitor ZeroMQ" -ErrorAction SilentlyContinue
if (-not $rule2) {
    Write-Host "Adding firewall rule for port 5555..."
    New-NetFirewallRule -DisplayName "MT4 Monitor ZeroMQ" -Direction Inbound -Protocol TCP -LocalPort 5555 -Action Allow
}

# 3. 检查端口监听
Write-Host "`nChecking if port 8000 is listening..."
$listener = netstat -an | findstr "8000"
if ($listener) {
    Write-Host "✅ Port 8000 is listening:" -ForegroundColor Green
    Write-Host $listener
} else {
    Write-Host "❌ Port 8000 is NOT listening" -ForegroundColor Red
}

# 4. 测试本地连接
Write-Host "`nTesting local connection..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8000" -TimeoutSec 5 -UseBasicParsing
    Write-Host "✅ Local connection successful! Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ Local connection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nFirewall rules configured. Try accessing http://216.66.53.132:8000 from your browser now." -ForegroundColor Cyan
```

---

## 最简测试版本

如果还是不行，尝试这个最小版本：

**创建文件 `C:\test_server.py`：**

```python
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
async def root():
    return "<h1>Server is working!</h1>"

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

**运行：**
```powershell
cd C:\
pip install fastapi uvicorn
python test_server.py
```

**测试：**
```powershell
# 在 VPS 上
Invoke-WebRequest http://localhost:8000

# 在外部浏览器
http://216.66.53.132:8000
```

如果测试服务器能工作，说明问题在主 server.py。如果测试服务器也不行，说明是防火墙/网络问题。

---

## 常见问题

### Q: 服务器运行但端口没监听？
A: 可能是 uvicorn 绑定问题。尝试修改 server.py 最后一行：
```python
# 从
uvicorn.run(app, host="0.0.0.0", port=8000)
# 改为
uvicorn.run(app, host="127.0.0.1", port=8000)
```

### Q: 本地能访问，外部不能？
A: 100% 是防火墙问题。检查：
1. Windows Defender Firewall
2. 云服务商安全组
3. 路由器/网络防火墙

### Q: 如何确认是防火墙问题？
A: 临时关闭防火墙测试（仅用于诊断，测试完记得开启）：
```powershell
# 临时关闭（测试完立即开启！）
netsh advfirewall set allprofiles state off

# 测试访问...

# 重新开启
netsh advfirewall set allprofiles state on
```

---

## 需要帮助？

运行上面的 "快速修复脚本"，把输出发给我，我帮你分析！
