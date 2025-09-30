# 调试Manifest操作
$API_BASE_URL = "http://localhost:5000/v2"
$REPO_NAME = "debug-test"

Write-Host "=== 调试 Manifest 操作 ===" -ForegroundColor Cyan

# 先创建一个blob用于测试
Write-Host "`n1. 创建测试Blob..." -ForegroundColor Yellow
try {
    # 开始上传
    $uploadResponse = Invoke-WebRequest -Uri "$API_BASE_URL/$REPO_NAME/blobs/uploads/" -Method POST -UseBasicParsing
    $uploadUrl = $uploadResponse.Headers['Location']
    
    # 上传数据
    $testData = [System.Text.Encoding]::UTF8.GetBytes("Hello Manifest Test!")
    $patchResponse = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $testData -ContentType "application/octet-stream" -UseBasicParsing
    
    # 计算digest并完成上传
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($testData)
    $digest = "sha256:" + [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
    $commitUrl = "$uploadUrl" + "?digest=$digest"
    $commitResponse = Invoke-WebRequest -Uri $commitUrl -Method PUT -UseBasicParsing
    
    Write-Host "✅ Blob创建成功: $digest" -ForegroundColor Green
} catch {
    Write-Host "❌ Blob创建失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 创建测试manifest
Write-Host "`n2. 创建测试Manifest..." -ForegroundColor Yellow
$manifestJson = @{
    schemaVersion = 2
    mediaType = "application/vnd.docker.distribution.manifest.v2+json"
    config = @{
        mediaType = "application/vnd.docker.container.image.v1+json"
        size = $testData.Length
        digest = $digest
    }
    layers = @(
        @{
            mediaType = "application/vnd.docker.image.rootfs.diff.tar.gzip"
            size = $testData.Length
            digest = $digest
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host "Manifest JSON:" -ForegroundColor Gray
Write-Host $manifestJson -ForegroundColor DarkGray

# 上传manifest
Write-Host "`n3. 上传Manifest..." -ForegroundColor Yellow
try {
    $manifestUrl = "$API_BASE_URL/$REPO_NAME/manifests/latest"
    $putResponse = Invoke-WebRequest -Uri $manifestUrl -Method PUT -Body $manifestJson -ContentType "application/vnd.docker.distribution.manifest.v2+json" -UseBasicParsing
    Write-Host "✅ Manifest上传成功" -ForegroundColor Green
    Write-Host "状态码: $($putResponse.StatusCode)" -ForegroundColor Gray
    Write-Host "Location: $($putResponse.Headers['Location'])" -ForegroundColor Gray
    Write-Host "Digest: $($putResponse.Headers['Docker-Content-Digest'])" -ForegroundColor Gray
} catch {
    Write-Host "❌ Manifest上传失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}

# 获取manifest
Write-Host "`n4. 获取Manifest..." -ForegroundColor Yellow
try {
    $getResponse = Invoke-WebRequest -Uri $manifestUrl -Method GET -UseBasicParsing
    Write-Host "✅ Manifest获取成功" -ForegroundColor Green
    Write-Host "状态码: $($getResponse.StatusCode)" -ForegroundColor Gray
    Write-Host "Content-Type: $($getResponse.Headers['Content-Type'])" -ForegroundColor Gray
    Write-Host "Content-Length: $($getResponse.Headers['Content-Length'])" -ForegroundColor Gray
    Write-Host "Docker-Content-Digest: $($getResponse.Headers['Docker-Content-Digest'])" -ForegroundColor Gray
    
    Write-Host "`n获取的内容:" -ForegroundColor Gray
    Write-Host $getResponse.Content -ForegroundColor DarkGray
    
    # 解析并验证内容
    Write-Host "`n5. 验证Manifest内容..." -ForegroundColor Yellow
    try {
        $retrievedManifest = $getResponse.Content | ConvertFrom-Json
        Write-Host "schemaVersion: $($retrievedManifest.schemaVersion)" -ForegroundColor Gray
        Write-Host "mediaType: '$($retrievedManifest.mediaType)'" -ForegroundColor Gray
        Write-Host "config.digest: $($retrievedManifest.config.digest)" -ForegroundColor Gray
        Write-Host "layers.count: $($retrievedManifest.layers.Count)" -ForegroundColor Gray
        
        # 验证条件
        $schemaOk = $retrievedManifest.schemaVersion -eq 2
        $mediaTypeOk = $retrievedManifest.mediaType -eq "application/vnd.docker.distribution.manifest.v2+json"
        
        Write-Host "`n验证结果:" -ForegroundColor Yellow
        Write-Host "schemaVersion == 2: $schemaOk" -ForegroundColor Gray
        Write-Host "mediaType == 'application/vnd.docker.distribution.manifest.v2+json': $mediaTypeOk" -ForegroundColor Gray
        Write-Host "总体验证: $($schemaOk -and $mediaTypeOk)" -ForegroundColor Gray
        
        if ($schemaOk -and $mediaTypeOk) {
            Write-Host "✅ Manifest验证成功" -ForegroundColor Green
        } else {
            Write-Host "❌ Manifest验证失败" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "❌ JSON解析失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.Exception.ToString()
    }
    
} catch {
    Write-Host "❌ Manifest获取失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
}