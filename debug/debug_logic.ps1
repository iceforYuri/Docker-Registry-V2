# 调试 PowerShell -and 操作符
$API_BASE_URL = "http://localhost:5000/v2"

Write-Host "=== 调试 PowerShell 逻辑 ===" -ForegroundColor Cyan

try {
    $baseResponse = Invoke-WebRequest -Uri "$API_BASE_URL/" -Method GET -UseBasicParsing
    $apiVersionHeader = $baseResponse.Headers['Docker-Distribution-Api-Version']
    
    Write-Host "原始值:" -ForegroundColor Yellow
    Write-Host "  StatusCode: $($baseResponse.StatusCode) (Type: $($baseResponse.StatusCode.GetType().Name))" -ForegroundColor Gray
    Write-Host "  ApiVersion: '$apiVersionHeader' (Type: $($apiVersionHeader.GetType().Name))" -ForegroundColor Gray
    
    Write-Host "`n单独比较:" -ForegroundColor Yellow
    $statusCheck = $baseResponse.StatusCode -eq 200
    $versionCheck = $apiVersionHeader -eq 'registry/2.0'
    Write-Host "  StatusCode -eq 200: $statusCheck (Type: $($statusCheck.GetType().Name))" -ForegroundColor Gray
    Write-Host "  ApiVersion -eq 'registry/2.0': $versionCheck (Type: $($versionCheck.GetType().Name))" -ForegroundColor Gray
    
    Write-Host "`n组合检查:" -ForegroundColor Yellow
    $combinedCheck = $statusCheck -and $versionCheck
    Write-Host "  combinedCheck: $combinedCheck (Type: $($combinedCheck.GetType().Name))" -ForegroundColor Gray
    
    Write-Host "`n直接组合:" -ForegroundColor Yellow
    $directCheck = ($baseResponse.StatusCode -eq 200) -and ($apiVersionHeader -eq 'registry/2.0')
    Write-Host "  directCheck: $directCheck (Type: $($directCheck.GetType().Name))" -ForegroundColor Gray
    
    Write-Host "`n测试if语句:" -ForegroundColor Yellow
    if ($baseResponse.StatusCode -eq 200 -and $apiVersionHeader -eq 'registry/2.0') {
        Write-Host "  ✅ if语句成功" -ForegroundColor Green
    } else {
        Write-Host "  ❌ if语句失败" -ForegroundColor Red
    }
    
    Write-Host "`n测试改进的if语句:" -ForegroundColor Yellow
    if (($baseResponse.StatusCode -eq 200) -and ($apiVersionHeader -eq 'registry/2.0')) {
        Write-Host "  ✅ 改进的if语句成功" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 改进的if语句失败" -ForegroundColor Red
    }
    
} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
}