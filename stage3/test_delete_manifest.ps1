# --------------------------------------------------------------------------------
# 文件: test_delete_manifest.ps1
# 描述: 专门用于测试 DELETE /v2/{name}/manifests/{digest} 接口的脚本。
#       验证了引用检查、错误处理和成功删除的完整逻辑。
# --------------------------------------------------------------------------------

# --- 配置变量 ---
$REGISTRY_HOST = "host.docker.internal:5000"
$REPO_NAME = "delete-validation-test"
$API_BASE_URL = "http://$REGISTRY_HOST/v2/$REPO_NAME"

# 使用两个不同的镜像来创建“被引用的”和“未被引用的”两种状态
$IMAGE_A = "alpine:3.17"
$IMAGE_B = "alpine:3.18"

$TAG_TO_KEEP = "keepme"
$TAG_TO_OVERWRITE = "overwriteme"

# --- 辅助函数 ---
function Assert-HttpFailure {
    param(
        [Parameter(Mandatory=$true)][string]$TestName,
        [Parameter(Mandatory=$true)][System.Management.Automation.ErrorRecord]$Exception,
        [Parameter(Mandatory=$true)][string]$ExpectedStatusCode
    )
    # --- 最终的 Bug 修复在这里！ ---
    # 我们必须使用传递进来的参数 $Exception，而不是自动变量 $_
    if ($Exception.Exception.Response.StatusCode -eq $ExpectedStatusCode) {
        Write-Host "--- ✅ TEST PASSED: $TestName (收到了预期的 $($Exception.Exception.Response.StatusCode) 错误) ---" -ForegroundColor Green
    } else {
        Write-Host "--- ❌ TEST FAILED: $TestName ---" -ForegroundColor Red
        Write-Host "预期状态码: $ExpectedStatusCode, 实际收到: $($Exception.Exception.Response.StatusCode)" -ForegroundColor Yellow
        Read-Host "按 Enter 键退出脚本..."
        exit 1
    }
}

# --- 准备阶段：构建一个特定的仓库状态 ---
function Setup-Registry-State {
    Write-Host "--- ⚙️  准备阶段: 正在构建测试所需的仓库状态... ---" -ForegroundColor Cyan
    
    # 1. 清理环境
    docker rmi -f "$REGISTRY_HOST/$REPO_NAME`:keepme" 2>$null
    docker rmi -f "$REGISTRY_HOST/$REPO_NAME`:temp-tag" 2>$null
    docker rmi -f $IMAGE_A 2>$null
    docker rmi -f $IMAGE_B 2>$null
    $storagePath = "C:\docker-registry-data\v2\repositories\$REPO_NAME"
    if (Test-Path $storagePath) { Remove-Item -Recse -Force $storagePath }

    # 2. 拉取基础镜像
    docker pull $IMAGE_A
    docker pull $IMAGE_B

    # 3. 创建一个“将被删除的”(untagged) manifest
    Write-Host "  - 创建 untagged manifest..."
    docker tag $IMAGE_A "$REGISTRY_HOST/$REPO_NAME`:temp-tag"
    $pushOutputA = docker push "$REGISTRY_HOST/$REPO_NAME`:temp-tag" 2>&1 | Out-String
    # 捕获 IMAGE_A 的 digest，这是我们的删除目标
    $digestToDelete = ($pushOutputA -split 'digest: ')[1].Trim().Split(' ')[0]
    
    # 用 IMAGE_B 覆盖 'temp-tag'，使 IMAGE_A 的 manifest 变为 untagged
    docker tag $IMAGE_B "$REGISTRY_HOST/$REPO_NAME`:temp-tag"
    docker push "$REGISTRY_HOST/$REPO_NAME`:temp-tag"

    # 4. 创建一个“将被保留的”(tagged) manifest
    Write-Host "  - 创建 tagged manifest..."
    docker tag $IMAGE_B "$REGISTRY_HOST/$REPO_NAME`:keepme"
    $pushOutputB = docker push "$REGISTRY_HOST/$REPO_NAME`:keepme" 2>&1 | Out-String
    # 捕获 IMAGE_B 的 digest，这是我们不能删除的目标
    $digestToKeep = ($pushOutputB -split 'digest: ')[1].Trim().Split(' ')[0]

    Write-Host "准备完成。"
    Write-Host "  - 将被保留的 Manifest (tagged as 'keepme'): $digestToKeep"
    Write-Host "  - 将被删除的 Manifest (untagged):         $digestToDelete"
    Write-Host "---`n"

    return @{
        DigestToKeep = $digestToKeep
        DigestToDelete = $digestToDelete
    }
}

# ================================================================================
# --- 测试开始 ---
# ================================================================================
$testState = Setup-Registry-State
$digestToKeep = $testState.DigestToKeep
$digestToDelete = $testState.DigestToDelete
$nonExistentDigest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

# --- 用例 1: [失败] 尝试通过 TAG 删除 ---
Write-Host "--- TEST 1: 尝试通过 Tag 删除 (应返回 400) ---" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "$API_BASE_URL/manifests/$TAG_TO_KEEP" -Method DELETE -UseBasicParsing -ErrorAction Stop
    Write-Host "--- ❌ TEST FAILED: 服务器接受了按 Tag 删除的请求 ---" -ForegroundColor Red; exit 1
} catch {
    Assert-HttpFailure "按 Tag 删除" $_ "BadRequest"
}
Write-Host "`n"

# --- 用例 2: [失败] 尝试删除一个不存在的 Digest ---
Write-Host "--- TEST 2: 尝试删除一个不存在的 Digest (应返回 404) ---" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "$API_BASE_URL/manifests/$nonExistentDigest" -Method DELETE -UseBasicParsing -ErrorAction Stop
    Write-Host "--- ❌ TEST FAILED: 服务器未对不存在的 Digest 返回 404 ---" -ForegroundColor Red; exit 1
} catch {
    Assert-HttpFailure "删除不存在的 Digest" $_ "NotFound"
}
Write-Host "`n"

# --- 用例 3: [失败] 尝试删除一个被引用的 Manifest ---
Write-Host "--- TEST 3: 尝试删除一个被引用的 Manifest (应返回 403) ---" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "$API_BASE_URL/manifests/$digestToKeep" -Method DELETE -UseBasicParsing -ErrorAction Stop
    Write-Host "--- ❌ TEST FAILED: 服务器允许了删除被引用的 Manifest ---" -ForegroundColor Red; exit 1
} catch {
    Assert-HttpFailure "删除被引用的 Manifest" $_ "Forbidden"
}
Write-Host "`n"

# --- 用例 4: [成功] 尝试删除一个未被引用的 Manifest ---
Write-Host "--- TEST 4: 尝试删除一个未被引用的 Manifest (应返回 202) ---" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$API_BASE_URL/manifests/$digestToDelete" -Method DELETE -UseBasicParsing -ErrorAction Stop
    if ($response.StatusCode -eq 202) {
        Write-Host "--- ✅ TEST PASSED: 删除未被引用的 Manifest (收到了预期的 202 Accepted) ---" -ForegroundColor Green
    } else {
        Write-Host "--- ❌ TEST FAILED: 删除未被引用的 Manifest 未返回 202 ---" -ForegroundColor Red; exit 1
    }
} catch {
    Write-Host "--- ❌ TEST FAILED: 删除未被引用的 Manifest 时发生异常 ---" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    exit 1
}
Write-Host "`n"

# --- 用例 5: [验证] 确认 Manifest 已被删除 ---
Write-Host "--- TEST 5: 验证 Manifest 是否已被删除 (应返回 404) ---" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "$API_BASE_URL/manifests/$digestToDelete" -Method HEAD -UseBasicParsing -ErrorAction Stop
    Write-Host "--- ❌ TEST FAILED: 已删除的 Manifest 仍然可以被访问 ---" -ForegroundColor Red; exit 1
} catch {
    Assert-HttpFailure "验证 Manifest 已被删除" $_ "NotFound"
}
Write-Host "`n"


# --- 总结 ---
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 恭喜！DELETE Manifest 的所有测试用例均已通过！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green```
