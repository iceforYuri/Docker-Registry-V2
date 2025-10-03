# --------------------------------------------------------------------------------
# 文件: test_all.ps1 (最终版)
# 描述: [终极版] 包含自动 Manifest List 生成功能验证的完整测试脚本。
# --------------------------------------------------------------------------------

# --- 配置变量 ---
$REGISTRY_HOST = "host.docker.internal:5000"
$API_BASE_URL = "http://$REGISTRY_HOST/v2"

# Test Part 1 & 2 Variables
$REPO_NAME_SINGLE = "my-comprehensive-test"
$BASE_IMAGE_SINGLE = "alpine:latest"
$IMAGE_TAG_SINGLE_LATEST = "$REGISTRY_HOST/$REPO_NAME_SINGLE`:latest"

# Test Part 3 Variables
$REPO_NAME_MULTI = "my-multi-arch-test"
$BASE_IMAGE_A = "alpine:3.17" # 模拟 "平台 A"
$BASE_IMAGE_B = "alpine:3.18" # 模拟 "平台 B"
$IMAGE_TAG_MULTI_LATEST = "$REGISTRY_HOST/$REPO_NAME_MULTI`:latest"


# --- 辅助函数 ---
function Assert-Success {
    param(
        [string]$TestName
    )
    if ($LASTEXITCODE -ne 0) {
        Write-Host "--- ❌ TEST FAILED: $TestName ---" -ForegroundColor Red
        Read-Host "按 Enter 键退出脚本..."
        exit 1
    }
    Write-Host "--- ✅ TEST PASSED: $TestName ---" -ForegroundColor Green
}

function Clean-Environment {
    Write-Host "--- 🧹 清理环境... ---" -ForegroundColor Yellow
    docker rmi -f $IMAGE_TAG_SINGLE_LATEST 2>$null
    docker rmi -f $IMAGE_TAG_MULTI_LATEST 2>$null
    docker rmi -f $BASE_IMAGE_SINGLE 2>$null
    docker rmi -f $BASE_IMAGE_A 2>$null
    docker rmi -f $BASE_IMAGE_B 2>$null
    $storagePath = "C:\docker-registry-data\v2"
    if (Test-Path $storagePath) { Remove-Item -Recurse -Force $storagePath }
    Write-Host "--- 清理完成。---`n" -ForegroundColor Yellow
}

# ================================================================================
# --- 脚本开始 ---
# ================================================================================
Clean-Environment

# --- PART 1: 核心端到端流程测试 ---
Write-Host "--- PART 1: 核心端到端流程测试 ---" -ForegroundColor Magenta
docker pull $BASE_IMAGE_SINGLE
Assert-Success "PART 1: 拉取基础镜像"
docker tag $BASE_IMAGE_SINGLE $IMAGE_TAG_SINGLE_LATEST
docker push $IMAGE_TAG_SINGLE_LATEST
Assert-Success "PART 1: 核心 PUSH 流程"
docker rmi -f $IMAGE_TAG_SINGLE_LATEST
docker rmi -f $BASE_IMAGE_SINGLE
docker pull $IMAGE_TAG_SINGLE_LATEST
Assert-Success "PART 1: 核心 PULL 流程"
docker run --rm $IMAGE_TAG_SINGLE_LATEST echo "Core flow success!"
Assert-Success "PART 1: 核心镜像完整性检查"
Write-Host "`n"


# --- PART 2: 显式的独立 API 接口测试 ---
Write-Host "--- PART 2: 显式的独立 API 接口测试 ---" -ForegroundColor Magenta
$inspectOutput = (docker inspect $IMAGE_TAG_SINGLE_LATEST | Out-String) | ConvertFrom-Json
$manifestDigest = ($inspectOutput[0]).RepoDigests[0].Split('@')[1]
$manifestUrl = "$API_BASE_URL/$REPO_NAME_SINGLE/manifests/$manifestDigest"

Write-Host "--- TEST: DELETE /manifests/{reference} (by digest - 应该被拒绝) ---" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $manifestUrl -Method DELETE -UseBasicParsing -ErrorAction Stop
    Write-Host "--- ❌ TEST FAILED: 按 digest 删除 Manifest (未被拒绝) ---" -ForegroundColor Red; exit 1
} catch {
    if ($_.Exception.Response.StatusCode -eq 'MethodNotAllowed') {
        Assert-Success "PART 2: 按 digest 删除 Manifest (被正确拒绝)"
    } else {
        Write-Host "--- ❌ TEST FAILED: 按 digest 删除 Manifest (返回了非预期的错误: $($_.Exception.Message)) ---" -ForegroundColor Red; exit 1
    }
}
Write-Host "`n"


# --- PART 3: 自动 Manifest List 生成/更新功能测试 ---
Write-Host "--- PART 3: 自动 Manifest List 生成/更新功能测试 ---" -ForegroundColor Magenta

# 步骤 1: 推送第一个 "平台" 的镜像
Write-Host "--- Step 3.1: 推送第一个 '平台' ($BASE_IMAGE_A) ---" -ForegroundColor Cyan
docker pull $BASE_IMAGE_A
Assert-Success "PART 3: 拉取 $BASE_IMAGE_A"
docker tag $BASE_IMAGE_A $IMAGE_TAG_MULTI_LATEST
$pushOutputA = docker push $IMAGE_TAG_MULTI_LATEST 2>&1 | Out-String
Assert-Success "PART 3: 推送 $BASE_IMAGE_A"
$digestA = ($pushOutputA -split 'digest: ')[1].Trim().Split(' ')[0]
Write-Host "第一个 Manifest Digest: $digestA"
Write-Host "`n"

# 步骤 2: 推送第二个 "平台" 的镜像到同一个 tag
Write-Host "--- Step 3.2: 推送第二个 '平台' ($BASE_IMAGE_B) 到同一个 tag ---" -ForegroundColor Cyan
docker pull $BASE_IMAGE_B
Assert-Success "PART 3: 拉取 $BASE_IMAGE_B"
docker tag $BASE_IMAGE_B $IMAGE_TAG_MULTI_LATEST
$pushOutputB = docker push $IMAGE_TAG_MULTI_LATEST 2>&1 | Out-String
Assert-Success "PART 3: 推送 $BASE_IMAGE_B"
$digestB = ($pushOutputB -split 'digest: ')[1].Trim().Split(' ')[0]
Write-Host "第二个 Manifest Digest: $digestB"
Write-Host "`n"

# 步骤 3: 最终验证！
Write-Host "--- Step 3.3: 验证 'latest' tag 是否被正确更新 ---" -ForegroundColor Cyan
try {
    # 因为我们推送了两个相同平台的镜像，服务器应该执行替换逻辑。
    # 所以 'latest' 最终应该指向第二个镜像 (B) 的单架构 manifest。
    $finalManifestUrl = "$API_BASE_URL/$REPO_NAME_MULTI/manifests/latest"
    $response = Invoke-WebRequest -Uri $finalManifestUrl -Method GET -UseBasicParsing -ErrorAction Stop

    # 验证1: Content-Type 应该是单架构 manifest 类型
    $contentType = $response.Headers['Content-Type']
    if ($contentType -match "manifest.list" -or $contentType -match "image.index") {
        Write-Host "--- ❌ TEST FAILED: Content-Type 不正确，它应该是一个单架构 Manifest。实际是: $contentType ---" -ForegroundColor Red; exit 1
    }
    Assert-Success "PART 3: Content-Type 验证 (单架构)"

    # 验证2: Digest 应该匹配我们推送的第二个镜像 (B) 的 digest
    $finalDigestFromServer = $response.Headers['Docker-Content-Digest']
    if ($finalDigestFromServer -ne $digestB) {
        Write-Host "--- ❌ TEST FAILED: Digest 不匹配。预期是 $digestB, 实际是: $finalDigestFromServer ---" -ForegroundColor Red; exit 1
    }
    Assert-Success "PART 3: Digest 验证 (正确替换)"

} catch {
    Write-Host "--- ❌ TEST FAILED: 验证时发生异常 ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"


# --- 总结 ---
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 恭喜！所有核心流程及高级功能均已通过测试！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green