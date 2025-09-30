# --------------------------------------------------------------------------------
# 文件: test_registry_comprehensive.ps1
# 描述: [全面版] Docker Registry V2 核心 API 端到端和独立接口测试脚本。
# --------------------------------------------------------------------------------

# --- 配置变量 ---
$REGISTRY_HOST = "host.docker.internal:5000"
$REPO_NAME = "my-comprehensive-test"
$BASE_IMAGE = "alpine"
$IMAGE_TAG_LATEST = "$REGISTRY_HOST/$REPO_NAME`:latest"
$API_BASE_URL = "http://$REGISTRY_HOST/v2"

# --- 辅助函数 ---
function Assert-Success {
    param([string]$TestName)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "--- ❌ TEST FAILED: $TestName ---" -ForegroundColor Red; exit 1
    }
    Write-Host "--- ✅ TEST PASSED: $TestName ---" -ForegroundColor Green
}

function Clean-Environment {
    Write-Host "--- 🧹 清理环境... ---" -ForegroundColor Yellow
    docker rmi -f $IMAGE_TAG_LATEST 2>$null
    docker rmi -f $BASE_IMAGE 2>$null
    $storagePath = "C:\docker-registry-data\v2"
    if (Test-Path $storagePath) { Remove-Item -Recurse -Force $storagePath }
    Write-Host "--- 清理完成。---`n" -ForegroundColor Yellow
}

# ================================================================================
# --- 第 1 部分: 核心流程测试 (与之前类似) ---
# ================================================================================
# Clean-Environment

Write-Host "--- PART 1: 核心端到端流程测试 ---" -ForegroundColor Magenta
docker pull $BASE_IMAGE
docker tag $BASE_IMAGE $IMAGE_TAG_LATEST
docker push $IMAGE_TAG_LATEST
Assert-Success "核心 PUSH 流程"
docker rmi -f $IMAGE_TAG_LATEST
docker rmi -f $BASE_IMAGE
docker pull $IMAGE_TAG_LATEST
Assert-Success "核心 PULL 流程"
docker run --rm $IMAGE_TAG_LATEST echo "Core flow success!"
Assert-Success "核心镜像完整性检查"
Write-Host "`n"

# ================================================================================
# --- 第 2 部分: 显式的、独立的 API 接口测试 (增强调试版) ---
# ================================================================================
Write-Host "--- PART 2: 显式的独立 API 接口测试 ---" -ForegroundColor Magenta

# --- 测试 Manifest 接口 ---
try {
    $inspectOutput = (docker inspect $IMAGE_TAG_LATEST | Out-String) | ConvertFrom-Json
    $manifestDigest = ($inspectOutput[0]).RepoDigests[0].Split('@')[1]
} catch {
    Write-Host "--- ❌ TEST FAILED: 无法从 'docker inspect' 解析 manifest digest ---" -ForegroundColor Red
    Write-Host "错误信息: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$manifestUrl = "$API_BASE_URL/$REPO_NAME/manifests/$manifestDigest"
$manifestTagUrl = "$API_BASE_URL/$REPO_NAME/manifests/latest"

# TEST: HEAD /manifests/{reference}
Write-Host "--- TEST: HEAD /manifests/{reference} (handleManifestHead) ---" -ForegroundColor Cyan
try {
    $headResponse = Invoke-WebRequest -Uri $manifestTagUrl -Method HEAD -UseBasicParsing
    if ($headResponse.StatusCode -eq 200 -and $headResponse.Headers['Docker-Content-Digest'] -eq $manifestDigest) {
        Assert-Success "Manifest HEAD 请求"
    } else {
        Write-Host "--- ❌ TEST FAILED: Manifest HEAD 请求 (逻辑断言失败) ---" -ForegroundColor Red
        Write-Host "预期状态码: 200, 实际: $($headResponse.StatusCode)" -ForegroundColor Yellow
        Write-Host "预期 Digest: $manifestDigest" -ForegroundColor Yellow
        Write-Host "实际 Digest: $($headResponse.Headers['Docker-Content-Digest'])" -ForegroundColor Yellow
        exit 1
    }
} catch {
    # --- 这是关键的修改：打印完整的异常信息 ---
    Write-Host "--- ❌ TEST FAILED: Manifest HEAD 请求 (捕获到 PowerShell 异常) ---" -ForegroundColor Red
    Write-Host "----------------- PowerShell Exception Details -----------------" -ForegroundColor Yellow
    # $_.Exception 会给出异常对象，.ToString() 会提供详细的堆栈跟踪
    Write-Host $_.Exception.ToString()
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    
    # 我们可以进一步检查响应对象是否存在
    if ($_.Exception.Response) {
        Write-Host "HTTP 状态码: $($_.Exception.Response.StatusCode) - $($_.Exception.Response.StatusDescription)"
    }
    exit 1
    # --- 修改结束 ---
}
Write-Host "`n"

# TEST: DELETE /manifests/{reference} (by digest - 应该被拒绝)
try {
    # 最终修正：添加 -ErrorAction Stop 来强制触发 catch 块
    Invoke-WebRequest -Uri $manifestUrl -Method DELETE -UseBasicParsing -ErrorAction Stop
    
    # 如果代码能执行到这里，说明没有抛出异常，测试失败
    Write-Host "--- ❌ TEST FAILED: 按 digest 删除 Manifest (未被拒绝) ---" -ForegroundColor Red; exit 1
} catch {
    # 现在 catch 块会被正确触发
    if ($_.Exception.Response.StatusCode -eq 'MethodNotAllowed') {
        Assert-Success "按 digest 删除 Manifest (被正确拒绝)"
    } else {
        Write-Host "--- ❌ TEST FAILED: 按 digest 删除 Manifest (返回了非预期的错误: $($_.Exception.Message)) ---" -ForegroundColor Red; exit 1
    }
}
Write-Host "`n"


# --- 测试 Blob Upload 接口的特殊路径 (同样添加 -ErrorAction Stop) ---
$uploadApiUrl = "$API_BASE_URL/$REPO_NAME/blobs/uploads/"

# TEST: POST to get UUID, then GET status
Write-Host "--- TEST: GET /blobs/uploads/{uuid} (handleBlobUploadStatus) ---" -ForegroundColor Cyan
try {
    $startUploadResponse = Invoke-WebRequest -Uri $uploadApiUrl -Method POST -UseBasicParsing -ErrorAction Stop
    $uploadUrl = $startUploadResponse.Headers['Location']

    $statusResponse = Invoke-WebRequest -Uri $uploadUrl -Method GET -UseBasicParsing -ErrorAction Stop
    if ($statusResponse.StatusCode -eq 204 -and $statusResponse.Headers['Range'] -eq '0--1') {
        Assert-Success "获取 Blob 上传状态"
    } else {
        Write-Host "--- ❌ TEST FAILED: 获取 Blob 上传状态 ---" -ForegroundColor Red; exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 获取 Blob 上传状态 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"


# TEST: DELETE /blobs/uploads/{uuid}
Write-Host "--- TEST: DELETE /blobs/uploads/{uuid} (handleBlobUploadCancel) ---" -ForegroundColor Cyan
try {
    $startUploadResponse2 = Invoke-WebRequest -Uri $uploadApiUrl -Method POST -UseBasicParsing -ErrorAction Stop
    $uploadUrl2 = $startUploadResponse2.Headers['Location']

    $cancelResponse = Invoke-WebRequest -Uri $uploadUrl2 -Method DELETE -UseBasicParsing -ErrorAction Stop
    if ($cancelResponse.StatusCode -ne 204) {
         Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (未返回 204) ---" -ForegroundColor Red; exit 1
    }

    try {
        Invoke-WebRequest -Uri $uploadUrl2 -Method GET -UseBasicParsing -ErrorAction Stop
        Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (验证失败，会话仍然存在) ---" -ForegroundColor Red; exit 1
    } catch {
        if ($_.Exception.Response.StatusCode -eq 'NotFound') {
            Assert-Success "取消 Blob 上传 (验证已删除)"
        } else {
            Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (验证时返回了非预期的错误: $($_.Exception.Message)) ---" -ForegroundColor Red; exit 1
        }
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 取消 Blob 上传 (请求异常) ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"


# --- 总结 ---
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 恭喜！所有核心流程和独立 API 接口均已通过测试！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green