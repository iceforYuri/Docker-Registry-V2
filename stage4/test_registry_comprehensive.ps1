# --------------------------------------------------------------------------------
# 文件: test_registry_comprehensive.ps1
# 描述: Docker Registry V2 核心 API 端到端和独立接口测试脚本 (Spring Boot版本)
# --------------------------------------------------------------------------------

# --- 配置变量 ---
$REGISTRY_HOST = "localhost:5000"
$REPO_NAME = "my-comprehensive-test"
$BASE_IMAGE = "alpine"
$IMAGE_TAG_LATEST = "$REGISTRY_HOST/$REPO_NAME`:latest"
$API_BASE_URL = "http://$REGISTRY_HOST/v2"

# --- 辅助函数 ---
function Assert-Success {
    param([string]$TestName)
    # 对于HTTP API测试，我们不依赖 $LASTEXITCODE
    # 该变量用于外部程序的退出代码，这里只是显示成功消息
    Write-Host "--- ✅ TEST PASSED: $TestName ---" -ForegroundColor Green
}

function Clean-Environment {
    Write-Host "--- 🧹 清理环境... ---" -ForegroundColor Yellow
    docker rmi -f $IMAGE_TAG_LATEST 2>$null
    docker rmi -f $BASE_IMAGE 2>$null
    $storagePath = "$env:USERPROFILE\.docker-registry\v2"
    if (Test-Path $storagePath) { Remove-Item -Recurse -Force $storagePath }
    Write-Host "--- 清理完成。---`n" -ForegroundColor Yellow
}

function Test-RegistryRunning {
    Write-Host "--- 检查 Registry 是否运行... ---" -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$API_BASE_URL/" -Method GET -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            Write-Host "--- ✅ Registry 正在运行 ---" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "--- ❌ Registry 未运行，请先启动 Spring Boot 应用程序 ---" -ForegroundColor Red
        Write-Host "运行命令: mvn spring-boot:run 或 java -jar target/docker-registry-lite-1.0.0.jar" -ForegroundColor Yellow
        return $false
    }
}

# ================================================================================
# --- 预检查 ---
# ================================================================================
if (-not (Test-RegistryRunning)) {
    exit 1
}

# ================================================================================
# --- 第 1 部分: 基础 API 测试 ---
# ================================================================================
Write-Host "--- PART 1: 基础 API 测试 ---" -ForegroundColor Magenta

# TEST: GET /v2/ (Base API)
Write-Host "--- TEST: GET /v2/ (Base API Check) ---" -ForegroundColor Cyan
try {
    $baseResponse = Invoke-WebRequest -Uri "$API_BASE_URL/" -Method GET -UseBasicParsing
    
    # 详细调试信息
    Write-Host "状态码: $($baseResponse.StatusCode)" -ForegroundColor Gray
    $apiVersionHeader = $baseResponse.Headers['Docker-Distribution-Api-Version']
    Write-Host "API版本头: '$apiVersionHeader'" -ForegroundColor Gray
    Write-Host "状态码检查: $($baseResponse.StatusCode -eq 200)" -ForegroundColor Gray
    Write-Host "版本头检查: $($apiVersionHeader -eq 'registry/2.0')" -ForegroundColor Gray
    
    if ($baseResponse.StatusCode -eq 200 -and $apiVersionHeader -eq 'registry/2.0') {
        Assert-Success "Base API 检查"
    } else {
        Write-Host "--- ❌ TEST FAILED: Base API 检查 ---" -ForegroundColor Red
        Write-Host "状态码: $($baseResponse.StatusCode)" -ForegroundColor Yellow
        Write-Host "API版本头: '$apiVersionHeader'" -ForegroundColor Yellow
        Write-Host "状态码正确: $($baseResponse.StatusCode -eq 200)" -ForegroundColor Yellow
        Write-Host "版本头正确: $($apiVersionHeader -eq 'registry/2.0')" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: Base API 检查 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# ================================================================================
# --- 第 2 部分: Blob 上传流程测试 ---
# ================================================================================
Write-Host "--- PART 2: Blob 上传流程测试 ---" -ForegroundColor Magenta

$uploadApiUrl = "$API_BASE_URL/$REPO_NAME/blobs/uploads/"

# TEST: POST /blobs/uploads/ (开始上传)
Write-Host "--- TEST: POST /blobs/uploads/ (开始上传) ---" -ForegroundColor Cyan
try {
    $startUploadResponse = Invoke-WebRequest -Uri $uploadApiUrl -Method POST -UseBasicParsing
    if ($startUploadResponse.StatusCode -eq 202) {
        $uploadUrl = $startUploadResponse.Headers['Location']
        $uploadUuid = $startUploadResponse.Headers['Docker-Upload-UUID']
        Assert-Success "开始 Blob 上传"
        Write-Host "上传 URL: $uploadUrl" -ForegroundColor Yellow
        Write-Host "上传 UUID: $uploadUuid" -ForegroundColor Yellow
    } else {
        Write-Host "--- ❌ TEST FAILED: 开始 Blob 上传 ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 开始 Blob 上传 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# TEST: GET /blobs/uploads/{uuid} (获取上传状态)
Write-Host "--- TEST: GET /blobs/uploads/{uuid} (获取上传状态) ---" -ForegroundColor Cyan
try {
    $statusResponse = Invoke-WebRequest -Uri $uploadUrl -Method GET -UseBasicParsing
    if ($statusResponse.StatusCode -eq 204) {
        Assert-Success "获取 Blob 上传状态"
    } else {
        Write-Host "--- ❌ TEST FAILED: 获取 Blob 上传状态 ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 获取 Blob 上传状态 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# TEST: PATCH /blobs/uploads/{uuid} (上传数据块)
Write-Host "--- TEST: PATCH /blobs/uploads/{uuid} (上传数据块) ---" -ForegroundColor Cyan
try {
    $testData = [System.Text.Encoding]::UTF8.GetBytes("Hello Docker Registry!")
    $patchResponse = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $testData -ContentType "application/octet-stream" -UseBasicParsing
    if ($patchResponse.StatusCode -eq 202) {
        Assert-Success "上传 Blob 数据块"
    } else {
        Write-Host "--- ❌ TEST FAILED: 上传 Blob 数据块 ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 上传 Blob 数据块 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# 计算测试数据的 SHA256 digest
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hash = $sha256.ComputeHash($testData)
$digest = "sha256:" + [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
Write-Host "计算的 digest: $digest" -ForegroundColor Yellow

# TEST: PUT /blobs/uploads/{uuid}?digest={digest} (完成上传)
Write-Host "--- TEST: PUT /blobs/uploads/{uuid}?digest={digest} (完成上传) ---" -ForegroundColor Cyan
try {
    $commitUrl = "$uploadUrl" + "?digest=$digest"
    $commitResponse = Invoke-WebRequest -Uri $commitUrl -Method PUT -UseBasicParsing
    if ($commitResponse.StatusCode -eq 201) {
        Assert-Success "完成 Blob 上传"
        $blobLocation = $commitResponse.Headers['Location']
        Write-Host "Blob 位置: $blobLocation" -ForegroundColor Yellow
    } else {
        Write-Host "--- ❌ TEST FAILED: 完成 Blob 上传 ---" -ForegroundColor Red
        Write-Host "状态码: $($commitResponse.StatusCode)" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 完成 Blob 上传 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# ================================================================================
# --- 第 3 部分: Blob 访问测试 ---
# ================================================================================
Write-Host "--- PART 3: Blob 访问测试 ---" -ForegroundColor Magenta

$blobUrl = "$API_BASE_URL/$REPO_NAME/blobs/$digest"

# TEST: HEAD /blobs/{digest} (检查 Blob 存在性)
Write-Host "--- TEST: HEAD /blobs/{digest} (检查 Blob 存在性) ---" -ForegroundColor Cyan
try {
    $headBlobResponse = Invoke-WebRequest -Uri $blobUrl -Method HEAD -UseBasicParsing
    if ($headBlobResponse.StatusCode -eq 200 -and $headBlobResponse.Headers['Docker-Content-Digest'] -eq $digest) {
        Assert-Success "检查 Blob 存在性"
    } else {
        Write-Host "--- ❌ TEST FAILED: 检查 Blob 存在性 ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 检查 Blob 存在性 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# TEST: GET /blobs/{digest} (下载 Blob)
Write-Host "--- TEST: GET /blobs/{digest} (下载 Blob) ---" -ForegroundColor Cyan
try {
    $getBlobResponse = Invoke-WebRequest -Uri $blobUrl -Method GET -UseBasicParsing
    if ($getBlobResponse.StatusCode -eq 200) {
        $downloadedData = [System.Text.Encoding]::UTF8.GetString($getBlobResponse.Content)
        if ($downloadedData -eq "Hello Docker Registry!") {
            Assert-Success "下载 Blob"
        } else {
            Write-Host "--- ❌ TEST FAILED: 下载 Blob (数据不匹配) ---" -ForegroundColor Red
            Write-Host "预期: Hello Docker Registry!" -ForegroundColor Yellow
            Write-Host "实际: $downloadedData" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "--- ❌ TEST FAILED: 下载 Blob ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 下载 Blob (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# ================================================================================
# --- 第 4 部分: 上传会话管理测试 ---
# ================================================================================
Write-Host "--- PART 4: 上传会话管理测试 ---" -ForegroundColor Magenta

# TEST: DELETE /blobs/uploads/{uuid} (取消上传)
Write-Host "--- TEST: DELETE /blobs/uploads/{uuid} (取消上传) ---" -ForegroundColor Cyan
try {
    # 开始新的上传会话
    $startUploadResponse2 = Invoke-WebRequest -Uri $uploadApiUrl -Method POST -UseBasicParsing
    $uploadUrl2 = $startUploadResponse2.Headers['Location']

    # 取消上传
    $cancelResponse = Invoke-WebRequest -Uri $uploadUrl2 -Method DELETE -UseBasicParsing
    if ($cancelResponse.StatusCode -eq 204) {
        # 验证上传会话已被删除
        try {
            Invoke-WebRequest -Uri $uploadUrl2 -Method GET -UseBasicParsing -ErrorAction Stop
            Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (验证失败，会话仍然存在) ---" -ForegroundColor Red
            exit 1
        } catch {
            if ($_.Exception.Response.StatusCode -eq 'NotFound') {
                Assert-Success "取消 Blob 上传"
            } else {
                Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (验证时返回了非预期的错误) ---" -ForegroundColor Red
                Write-Host $_.Exception.ToString()
                exit 1
            }
        }
    } else {
        Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# ================================================================================
# --- 第 5 部分: Manifest 操作测试 ---
# ================================================================================
Write-Host "--- PART 5: Manifest 操作测试 ---" -ForegroundColor Magenta

# 创建一个简单的测试 manifest
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

$manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestJson)
$manifestDigest = "sha256:" + [System.BitConverter]::ToString($sha256.ComputeHash($manifestBytes)).Replace("-", "").ToLower()

Write-Host "Manifest JSON:" -ForegroundColor Yellow
Write-Host $manifestJson -ForegroundColor Gray
Write-Host "Manifest Digest: $manifestDigest" -ForegroundColor Yellow

# TEST: PUT /manifests/{reference} (上传 Manifest)
Write-Host "--- TEST: PUT /manifests/{reference} (上传 Manifest) ---" -ForegroundColor Cyan
try {
    $manifestUrl = "$API_BASE_URL/$REPO_NAME/manifests/latest"
    $putManifestResponse = Invoke-WebRequest -Uri $manifestUrl -Method PUT -Body $manifestJson -ContentType "application/vnd.docker.distribution.manifest.v2+json" -UseBasicParsing
    if ($putManifestResponse.StatusCode -eq 201) {
        Assert-Success "上传 Manifest"
        Write-Host "Manifest 位置: $($putManifestResponse.Headers['Location'])" -ForegroundColor Yellow
    } else {
        Write-Host "--- ❌ TEST FAILED: 上传 Manifest ---" -ForegroundColor Red
        Write-Host "状态码: $($putManifestResponse.StatusCode)" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 上传 Manifest (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# TEST: HEAD /manifests/{reference} (检查 Manifest 存在性)
Write-Host "--- TEST: HEAD /manifests/{reference} (检查 Manifest 存在性) ---" -ForegroundColor Cyan
try {
    $headManifestResponse = Invoke-WebRequest -Uri $manifestUrl -Method HEAD -UseBasicParsing
    if ($headManifestResponse.StatusCode -eq 200) {
        Assert-Success "检查 Manifest 存在性"
    } else {
        Write-Host "--- ❌ TEST FAILED: 检查 Manifest 存在性 ---" -ForegroundColor Red
        Write-Host "状态码: $($headManifestResponse.StatusCode)" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 检查 Manifest 存在性 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# TEST: GET /manifests/{reference} (获取 Manifest)
Write-Host "--- TEST: GET /manifests/{reference} (获取 Manifest) ---" -ForegroundColor Cyan
try {
    $getManifestResponse = Invoke-WebRequest -Uri $manifestUrl -Method GET -UseBasicParsing
    if ($getManifestResponse.StatusCode -eq 200) {
        Write-Host "状态码: $($getManifestResponse.StatusCode)" -ForegroundColor Gray
        Write-Host "Content-Type: $($getManifestResponse.Headers['Content-Type'])" -ForegroundColor Gray
        
        # 检查响应内容类型并正确处理
        $manifestContent = ""
        if ($getManifestResponse.Content -is [byte[]]) {
            # 如果是字节数组，转换为字符串
            $manifestContent = [System.Text.Encoding]::UTF8.GetString($getManifestResponse.Content)
            Write-Host "内容类型: 字节数组，已转换为字符串" -ForegroundColor Gray
        } else {
            # 如果已经是字符串
            $manifestContent = $getManifestResponse.Content
            Write-Host "内容类型: 字符串" -ForegroundColor Gray
        }
        
        Write-Host "响应内容: $manifestContent" -ForegroundColor Gray
        
        $retrievedManifest = $manifestContent | ConvertFrom-Json
        Write-Host "解析后的 schemaVersion: $($retrievedManifest.schemaVersion)" -ForegroundColor Gray
        Write-Host "解析后的 mediaType: '$($retrievedManifest.mediaType)'" -ForegroundColor Gray
        
        $schemaOk = $retrievedManifest.schemaVersion -eq 2
        $mediaTypeOk = $retrievedManifest.mediaType -eq "application/vnd.docker.distribution.manifest.v2+json"
        Write-Host "schemaVersion 检查: $schemaOk" -ForegroundColor Gray
        Write-Host "mediaType 检查: $mediaTypeOk" -ForegroundColor Gray
        
        if ($schemaOk -and $mediaTypeOk) {
            Assert-Success "获取 Manifest"
        } else {
            Write-Host "--- ❌ TEST FAILED: 获取 Manifest (数据验证失败) ---" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "--- ❌ TEST FAILED: 获取 Manifest ---" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 获取 Manifest (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# ================================================================================
# --- 总结 ---
# ================================================================================
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 恭喜！所有 Docker Registry API 测试均已通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "测试覆盖的功能：" -ForegroundColor Cyan
Write-Host "✅ Base API (GET /v2/)" -ForegroundColor Green
Write-Host "✅ Blob 分片上传流程 (POST/PATCH/PUT)" -ForegroundColor Green
Write-Host "✅ Blob 访问 (HEAD/GET)" -ForegroundColor Green
Write-Host "✅ 上传会话管理 (DELETE)" -ForegroundColor Green
Write-Host "✅ Manifest 操作 (PUT/HEAD/GET)" -ForegroundColor Green
Write-Host "`n你的 Spring Boot Docker Registry 实现运行正常！" -ForegroundColor Yellow