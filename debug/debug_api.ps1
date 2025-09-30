# 调试版本 - 检查HTTP头
$API_BASE_URL = "http://localhost:5000/v2"

Write-Host "=== 调试 Base API 检查 ===" -ForegroundColor Cyan

try {
    $baseResponse = Invoke-WebRequest -Uri "$API_BASE_URL/" -Method GET -UseBasicParsing
    Write-Host "状态码: $($baseResponse.StatusCode)" -ForegroundColor Yellow
    Write-Host "所有HTTP头:" -ForegroundColor Yellow
    $baseResponse.Headers.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
    }
    
    Write-Host "`n检查特定头:" -ForegroundColor Yellow
    $apiVersionHeader = $baseResponse.Headers['Docker-Distribution-Api-Version']
    Write-Host "API版本头 (直接访问): '$apiVersionHeader'" -ForegroundColor Gray
    Write-Host "API版本头 (类型): $($apiVersionHeader.GetType().Name)" -ForegroundColor Gray
    
    # 如果是数组，显示所有值
    if ($apiVersionHeader -is [array]) {
        Write-Host "API版本头 (数组长度): $($apiVersionHeader.Length)" -ForegroundColor Gray
        for ($i = 0; $i -lt $apiVersionHeader.Length; $i++) {
            Write-Host "  [$i]: '$($apiVersionHeader[$i])'" -ForegroundColor Gray
        }
    }
    
    # 测试比较
    Write-Host "`n比较结果:" -ForegroundColor Yellow
    Write-Host "apiVersionHeader -eq 'registry/2.0': $($apiVersionHeader -eq 'registry/2.0')" -ForegroundColor Gray
    Write-Host "apiVersionHeader.ToString() -eq 'registry/2.0': $($apiVersionHeader.ToString() -eq 'registry/2.0')" -ForegroundColor Gray
    
} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
}