# 调试存储文件系统
$API_BASE_URL = "http://localhost:5000/v2"
$REPO_NAME = "debug-test"

Write-Host "=== 调试存储文件系统 ===" -ForegroundColor Cyan

# 1. 先检查存储根目录
$storageRoot = "$env:USERPROFILE\.docker-registry"
Write-Host "`n1. 检查存储根目录: $storageRoot" -ForegroundColor Yellow

if (Test-Path $storageRoot) {
    Write-Host "✅ 存储根目录存在" -ForegroundColor Green
    Get-ChildItem $storageRoot -Recurse | ForEach-Object { 
        $relativePath = $_.FullName.Replace($storageRoot, "")
        Write-Host "  $relativePath" -ForegroundColor Gray
    }
} else {
    Write-Host "❌ 存储根目录不存在" -ForegroundColor Red
}

# 2. 创建测试Blob
Write-Host "`n2. 创建测试Blob..." -ForegroundColor Yellow
try {
    $uploadResponse = Invoke-WebRequest -Uri "$API_BASE_URL/$REPO_NAME/blobs/uploads/" -Method POST -UseBasicParsing
    $uploadUrl = $uploadResponse.Headers['Location']
    
    $testData = [System.Text.Encoding]::UTF8.GetBytes("Test Data for Manifest")
    $patchResponse = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $testData -ContentType "application/octet-stream" -UseBasicParsing
    
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

# 3. 检查Blob存储
Write-Host "`n3. 检查Blob存储..." -ForegroundColor Yellow
$blobPath = "$storageRoot\v2\blobs\sha256\" + $digest.Substring(7, 2) + "\" + $digest.Substring(7) + "\data"
Write-Host "预期Blob路径: $blobPath" -ForegroundColor Gray
if (Test-Path $blobPath) {
    Write-Host "✅ Blob文件存在" -ForegroundColor Green
    $blobContent = Get-Content $blobPath -Raw
    Write-Host "Blob内容: '$blobContent'" -ForegroundColor Gray
} else {
    Write-Host "❌ Blob文件不存在" -ForegroundColor Red
}

# 4. 创建Manifest
Write-Host "`n4. 创建并上传Manifest..." -ForegroundColor Yellow
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

Write-Host "要上传的Manifest:" -ForegroundColor Gray
Write-Host $manifestJson -ForegroundColor DarkGray

try {
    $manifestUrl = "$API_BASE_URL/$REPO_NAME/manifests/test-tag"
    $putResponse = Invoke-WebRequest -Uri $manifestUrl -Method PUT -Body $manifestJson -ContentType "application/vnd.docker.distribution.manifest.v2+json" -UseBasicParsing
    
    Write-Host "✅ Manifest上传成功" -ForegroundColor Green
    Write-Host "返回的Digest: $($putResponse.Headers['Docker-Content-Digest'])" -ForegroundColor Gray
    $manifestDigest = $putResponse.Headers['Docker-Content-Digest']
    
} catch {
    Write-Host "❌ Manifest上传失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}

# 5. 检查Manifest存储
Write-Host "`n5. 检查Manifest存储..." -ForegroundColor Yellow

# 检查manifest blob
if ($manifestDigest) {
    $manifestBlobPath = "$storageRoot\v2\blobs\sha256\" + $manifestDigest.Substring(7, 2) + "\" + $manifestDigest.Substring(7) + "\data"
    Write-Host "预期Manifest Blob路径: $manifestBlobPath" -ForegroundColor Gray
    if (Test-Path $manifestBlobPath) {
        Write-Host "✅ Manifest Blob文件存在" -ForegroundColor Green
        $manifestBlobContent = Get-Content $manifestBlobPath -Raw
        Write-Host "Manifest Blob内容:" -ForegroundColor Gray
        Write-Host $manifestBlobContent -ForegroundColor DarkGray
    } else {
        Write-Host "❌ Manifest Blob文件不存在" -ForegroundColor Red
    }
}

# 检查tag link
$linkPath = "$storageRoot\v2\repositories\$REPO_NAME\_manifests\tags\test-tag\current\link"
Write-Host "预期Tag Link路径: $linkPath" -ForegroundColor Gray
if (Test-Path $linkPath) {
    Write-Host "✅ Tag Link文件存在" -ForegroundColor Green
    $linkContent = Get-Content $linkPath -Raw
    Write-Host "Link内容: '$linkContent'" -ForegroundColor Gray
} else {
    Write-Host "❌ Tag Link文件不存在" -ForegroundColor Red
}

# 6. 尝试获取Manifest
Write-Host "`n6. 尝试获取Manifest..." -ForegroundColor Yellow
try {
    $getResponse = Invoke-WebRequest -Uri $manifestUrl -Method GET -UseBasicParsing
    Write-Host "✅ Manifest获取成功" -ForegroundColor Green
    Write-Host "状态码: $($getResponse.StatusCode)" -ForegroundColor Gray
    Write-Host "Content-Type: $($getResponse.Headers['Content-Type'])" -ForegroundColor Gray
    Write-Host "Content-Length: $($getResponse.Headers['Content-Length'])" -ForegroundColor Gray
    Write-Host "获取的内容长度: $($getResponse.Content.Length)" -ForegroundColor Gray
    Write-Host "获取的原始内容:" -ForegroundColor Gray
    Write-Host $getResponse.Content -ForegroundColor DarkGray
    
    if ($getResponse.Content) {
        try {
            $parsed = $getResponse.Content | ConvertFrom-Json
            Write-Host "JSON解析成功:" -ForegroundColor Green
            Write-Host "  schemaVersion: $($parsed.schemaVersion)" -ForegroundColor Gray
            Write-Host "  mediaType: '$($parsed.mediaType)'" -ForegroundColor Gray
        } catch {
            Write-Host "JSON解析失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ 获取的内容为空" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Manifest获取失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
}