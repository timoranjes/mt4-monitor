# MT4 Monitor - Network Diagnostic Script
# Run this on your VPS to find the correct network configuration

Write-Host "=== Network Configuration ===" -ForegroundColor Cyan

# Get all IP addresses
Write-Host "`nAll IP Addresses:" -ForegroundColor Yellow
Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.IPAddress -notlike "127.*" } | Format-Table InterfaceAlias, IPAddress, PrefixLength

# Get external IP
Write-Host "`nExternal IP (what the internet sees):" -ForegroundColor Yellow
try {
    $externalIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
    Write-Host $externalIP -ForegroundColor Green
} catch {
    Write-Host "Could not determine external IP" -ForegroundColor Red
}

# Check routing
Write-Host "`nDefault Gateway:" -ForegroundColor Yellow
Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Format-Table NextHop, InterfaceAlias

# Test which IP the server should bind to
Write-Host "`n=== Testing Server Binding ===" -ForegroundColor Cyan

$ips = Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.IPAddress -notlike "127.*" } | Select-Object -ExpandProperty IPAddress

foreach ($ip in $ips) {
    Write-Host "Testing $ip..." -NoNewline
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($ip), 18000)
        $listener.Start()
        $listener.Stop()
        Write-Host " OK (Can bind)" -ForegroundColor Green
    } catch {
        Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

# Check if port 8000 is actually reachable from outside
Write-Host "`n=== Port 8000 Reachability ===" -ForegroundColor Cyan
Write-Host "Checking if port 8000 is accessible..." -ForegroundColor Yellow

# Check Windows Firewall status
Write-Host "`nWindows Firewall Status:" -ForegroundColor Yellow
Get-NetFirewallProfile | Format-Table Name, Enabled

# Show current firewall rules for 8000
Write-Host "`nFirewall Rules for Port 8000:" -ForegroundColor Yellow
Get-NetFirewallRule | Where-Object { 
    ($_ | Get-NetFirewallPortFilter).LocalPort -eq 8000 
} | Format-Table DisplayName, Enabled, Action, Direction

Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan
Write-Host "If you see FAILED above for all IPs, the issue is Windows networking." -ForegroundColor Yellow
Write-Host "If Windows Firewall shows Enabled, try temporarily disabling it:" -ForegroundColor Yellow
Write-Host "  Set-NetFirewallProfile -All -Enabled False  # (Remember to re-enable!)" -ForegroundColor White
Write-Host "`nFor IC Markets VPS, also check if there's a VPS control panel firewall." -ForegroundColor Yellow
