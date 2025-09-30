# --------------------------------------------------------------------------------
# 文件: test_basic.ps1
# 描述: Docker Registry 基础功能快速测试脚本
# --------------------------------------------------------------------------------

$REGISTRY_HOST = "localhost:5000"
$API_BASE_URL = "http://$REGISTRY_HOST/v2"

Write-Host "=== Docker Registry 基础功能测试 ===" -ForegroundColor Cyan

# 1. 测试基础 API
Write-Host "`n1. 测试基础 API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$API_BASE_URL/" -Method GET -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ 基础 API 正常" -ForegroundColor Green
    } else {
        Write-Host "❌ 基础 API 异常" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Registry 未运行，请先启动应用程序" -ForegroundColor Red
    Write-Host "运行: mvn spring-boot:run" -ForegroundColor Yellow
    exit 1
}

# 2. 测试开始上传
Write-Host "`n2. 测试开始上传..." -ForegroundColor Yellow
try {
    $uploadResponse = Invoke-WebRequest -Uri "$API_BASE_URL/test-repo/blobs/uploads/" -Method POST -UseBasicParsing
    if ($uploadResponse.StatusCode -eq 202) {
        Write-Host "✅ 开始上传成功" -ForegroundColor Green
        $uploadUrl = $uploadResponse.Headers['Location']
        Write-Host "上传 URL: $uploadUrl" -ForegroundColor Gray
    } else {
        Write-Host "❌ 开始上传失败" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ 开始上传异常: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 3. 测试上传数据
Write-Host "`n3. 测试上传数据..." -ForegroundColor Yellow
try {
    $testData = [System.Text.Encoding]::UTF8.GetBytes("Hello World!")
    $patchResponse = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $testData -ContentType "application/octet-stream" -UseBasicParsing
    if ($patchResponse.StatusCode -eq 202) {
        Write-Host "✅ 上传数据成功" -ForegroundColor Green
    } else {
        Write-Host "❌ 上传数据失败" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ 上传数据异常: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. 测试完成上传
Write-Host "`n4. 测试完成上传..." -ForegroundColor Yellow
try {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($testData)
    $digest = "sha256:" + [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
    
    $commitUrl = "$uploadUrl" + "?digest=$digest"
    $commitResponse = Invoke-WebRequest -Uri $commitUrl -Method PUT -UseBasicParsing
    if ($commitResponse.StatusCode -eq 201) {
        Write-Host "✅ 完成上传成功" -ForegroundColor Green
        Write-Host "Blob digest: $digest" -ForegroundColor Gray
    } else {
        Write-Host "❌ 完成上传失败" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ 完成上传异常: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 5. 测试获取 Blob
Write-Host "`n5. 测试获取 Blob..." -ForegroundColor Yellow
try {
    $blobUrl = "$API_BASE_URL/test-repo/blobs/$digest"
    $getBlobResponse = Invoke-WebRequest -Uri $blobUrl -Method GET -UseBasicParsing
    if ($getBlobResponse.StatusCode -eq 200) {
        $downloadedData = [System.Text.Encoding]::UTF8.GetString($getBlobResponse.Content)
        if ($downloadedData -eq "Hello World!") {
            Write-Host "✅ 获取 Blob 成功" -ForegroundColor Green
        } else {
            Write-Host "❌ Blob 数据不匹配" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "❌ 获取 Blob 失败" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ 获取 Blob 异常: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n🎉 所有基础测试通过！Docker Registry 运行正常！" -ForegroundColor Green