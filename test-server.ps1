# MT4 Monitor - Test Script
# Run this on VPS to test if server is working

Write-Host "=== Testing MT4 Monitor Server ===" -ForegroundColor Cyan

# Test 1: Health check
Write-Host "`n1. Testing Health Endpoint..." -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "   ✅ Health OK: $($r.Content)" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Health Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Test data endpoint
Write-Host "`n2. Testing Data Endpoint (POST)..." -ForegroundColor Yellow
$json = '{"account_name":"Test-Account","account_type":"LIVE","balance":10000,"equity":10500}'
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/api/data" -Method POST -Body $json -ContentType "application/json" -TimeoutSec 5 -UseBasicParsing
    Write-Host "   ✅ Data POST OK: $($r.Content)" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Data POST Failed: $($_.Exception.Message)" -ForegroundColor Red
    if($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test 3: Dashboard
Write-Host "`n3. Testing Dashboard..." -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000" -TimeoutSec 5 -UseBasicParsing
    if($r.StatusCode -eq 401) {
        Write-Host "   ✅ Dashboard OK (401 = needs login, which is expected)" -ForegroundColor Green
    } else {
        Write-Host "   ✅ Dashboard OK: $($r.StatusCode)" -ForegroundColor Green
    }
} catch {
    Write-Host "   ❌ Dashboard Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "If all tests show ✅, the server is working correctly!" -ForegroundColor Green
Write-Host "If you see ❌, restart the server: cd C:\mt4-monitor; python server.py" -ForegroundColor Yellow
