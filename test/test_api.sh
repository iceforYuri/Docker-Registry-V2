# 创建 PowerShell 测试脚本
# filepath: test_api.ps1

$BASE_URL = "http://localhost:5000"
$REPO_NAME = "test/sample"

Write-Host "=== Docker Registry API 测试 ===" -ForegroundColor Green

# 1. 测试 API 版本检查
Write-Host "1. 测试 API 版本检查..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/" -Method GET
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Headers: $($response.Headers | Out-String)"
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 2. 测试开始分片上传
Write-Host "2. 测试开始分片上传..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/blobs/uploads/" -Method POST
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Headers: $($response.Headers | Out-String)"
    
    # 提取 Upload UUID
    $uploadUuid = $response.Headers['Docker-Upload-UUID'][0]
    Write-Host "Upload UUID: $uploadUuid" -ForegroundColor Cyan
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 3. 创建测试数据
Write-Host "3. 创建测试数据..." -ForegroundColor Yellow
$testData = "Hello Docker Registry!"
$tempFile = "$env:TEMP\test_blob.data"
[System.IO.File]::WriteAllText($tempFile, $testData, [System.Text.Encoding]::UTF8)

# 计算 SHA256
$hash = Get-FileHash -Path $tempFile -Algorithm SHA256
$testDigest = "sha256:" + $hash.Hash.ToLower()
Write-Host "Test data: $testData" -ForegroundColor Cyan
Write-Host "Expected digest: $testDigest" -ForegroundColor Cyan
Write-Host ""

# 4. 测试上传分片（如果有 UUID）
if ($uploadUuid) {
    Write-Host "4. 测试上传分片..." -ForegroundColor Yellow
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
        $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/blobs/uploads/$uploadUuid" -Method PATCH -Body $fileBytes -ContentType "application/octet-stream"
        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""

    # 5. 测试完成上传
    Write-Host "5. 测试完成上传..." -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/blobs/uploads/${uploadUuid}?digest=$testDigest" -Method PUT
        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# 6. 测试检查 Blob 存在性
Write-Host "6. 测试检查 Blob 存在性..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/blobs/$testDigest" -Method HEAD
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 7. 测试下载 Blob
Write-Host "7. 测试下载 Blob..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/blobs/$testDigest" -Method GET
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content: $($response.Content)" -ForegroundColor Cyan
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 8. 测试上传 Manifest
Write-Host "8. 测试上传 Manifest..." -ForegroundColor Yellow
$manifest = @{
    schemaVersion = 2
    mediaType = "application/vnd.docker.distribution.manifest.v2+json"
    config = @{
        mediaType = "application/vnd.docker.container.image.v1+json"
        size = $testData.Length
        digest = $testDigest
    }
    layers = @(
        @{
            mediaType = "application/vnd.docker.image.rootfs.diff.tar.gzip"
            size = $testData.Length
            digest = $testDigest
        }
    )
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/manifests/latest" -Method PUT -Body $manifest -ContentType "application/vnd.docker.distribution.manifest.v2+json"
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 9. 测试获取 Manifest
Write-Host "9. 测试获取 Manifest..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/v2/$REPO_NAME/manifests/latest" -Method GET
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content: $($response.Content)" -ForegroundColor Cyan
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 清理临时文件
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

Write-Host "=== 测试完成 ===" -ForegroundColor Green
Read-Host "按 Enter 键退出"