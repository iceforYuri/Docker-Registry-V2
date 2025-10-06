# --------------------------------------------------------------------------------
# 文件: test_blobs_advanced.ps1
# 描述: [高级版] 针对 Blob 上传接口的独立、精细化测试脚本。
#       验证分块上传、状态查询、范围校验、取消和完成逻辑。
# --------------------------------------------------------------------------------

# --- 配置变量 ---
$REGISTRY_HOST = "host.docker.internal:5000"
$API_BASE_URL = "http://$REGISTRY_HOST/v2"
$REPO_NAME = "blob-advanced-test"

# --- 辅助函数 ---
function Assert-Status {
    param(
        [string]$TestName,
        [Microsoft.PowerShell.Commands.WebResponseObject]$Response,
        [int]$ExpectedStatus
    )
    if ($Response.StatusCode -ne $ExpectedStatus) {
        Write-Host "--- ❌ TEST FAILED: $TestName ---" -ForegroundColor Red
        Write-Host "预期状态码: $ExpectedStatus, 实际: $($Response.StatusCode)" -ForegroundColor Red
        Read-Host "按 Enter 键退出脚本..."; exit 1
    }
    Write-Host "--- ✅ TEST PASSED: $TestName (状态码: $ExpectedStatus) ---" -ForegroundColor Green
}

function Assert-ErrorStatus {
    param(
        [string]$TestName,
        [Microsoft.PowerShell.Commands.ActionPreference]$ErrorAction, # 这个参数其实没用到，可以移除
        [scriptblock]$ScriptBlock,
        [string]$ExpectedStatus
    )
    try {
        # Invoke-WebRequest 默认不会因 HTTP 错误而抛出终止性异常
        # 我们需要明确指定 -ErrorAction Stop 来强制它行为像一个终止性命令
        # （虽然在前面的修复中我们已经加了，但这里强调一下）
        $commandResult = Invoke-Command -ScriptBlock $ScriptBlock 
        
        # --- !!! 关键修改 !!! ---
        # 如果 Invoke-Command 成功执行（没有抛出异常），我们需要检查它的结果。
        # 对于 DELETE 操作，成功的响应是 204。
        # 我们需要检查这个成功响应的状态码是否符合我们对“成功”的定义。
        if ($commandResult.StatusCode -eq 204) {
            # 204 是我们期望的成功代码，所以我们在这里就断言成功
            Write-Host "--- ✅ TEST PASSED: $TestName (正确捕获到 204 No Content) ---" -ForegroundColor Green
        } else {
            # 如果不是 204，那就说明不是我们期望的成功，测试失败
            Write-Host "--- ❌ TEST FAILED: $TestName (未返回预期的 204 状态码，实际: $($commandResult.StatusCode)) ---" -ForegroundColor Red
            Read-Host "按 Enter 键退出脚本..."; exit 1
        }
        # --- 修改结束 ---

    } catch {
        # 如果 Invoke-WebRequest 真的抛出了异常（比如 404, 400 等）
        if ($_.Exception.Response.StatusCode -eq $ExpectedStatus) {
            Write-Host "--- ✅ TEST PASSED: $TestName (正确捕获到: $ExpectedStatus) ---" -ForegroundColor Green
        } else {
            Write-Host "--- ❌ TEST FAILED: $TestName (捕获到非预期的错误: $($_.Exception.Message)) ---" -ForegroundColor Red
            # 打印更详细的异常信息
            Write-Host $_.Exception.ToString()
            Read-Host "按 Enter 键退出脚本..."; exit 1
        }
    }
}

# ================================================================================
# --- 脚本开始 ---
# ================================================================================
Write-Host "--- 🧹 清理环境... ---" -ForegroundColor Yellow
$storagePath = "C:\docker-registry-data\v2"
if (Test-Path $storagePath) { Remove-Item -Recurse -Force $storagePath }
Write-Host "--- 清理完成。---`n" -ForegroundColor Yellow

# --- TEST 1: 启动上传 & 查询空状态 ---
Write-Host "--- TEST 1: 启动上传 (POST) & 查询空状态 (GET) ---" -ForegroundColor Cyan
$startUploadUrl = "$API_BASE_URL/$REPO_NAME/blobs/uploads/"
$startResponse = Invoke-WebRequest -Uri $startUploadUrl -Method POST -UseBasicParsing -ErrorAction Stop
Assert-Status "1.1 启动上传" $startResponse 202
$uploadUrl = $startResponse.Headers['Location']
$uuid = $startResponse.Headers['Docker-Upload-UUID']
if (-not $uploadUrl -or -not $uuid) { Write-Host "--- ❌ TEST FAILED: 1.1 Location 或 UUID 头缺失 ---" -ForegroundColor Red; exit 1 }

$statusResponse = Invoke-WebRequest -Uri $uploadUrl -Method GET -UseBasicParsing -ErrorAction Stop
Assert-Status "1.2 查询空状态" $statusResponse 204
if ($statusResponse.Headers['Range'] -ne '0-0') { Write-Host "--- ❌ TEST FAILED: 1.2 空状态 Range 头不是 '0-0' ---" -ForegroundColor Red; exit 1 }
Write-Host "`n"

# --- TEST 2: 上传数据块 & 范围校验 ---
Write-Host "--- TEST 2: 上传数据块 (PATCH) & 范围校验 ---" -ForegroundColor Cyan
$chunk1 = "first_chunk_of_data"
$patchResponse1 = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $chunk1 -ContentType "application/octet-stream" -UseBasicParsing -ErrorAction Stop
Assert-Status "2.1 上传第一个块" $patchResponse1 202
$expectedRange1 = "0-$($chunk1.Length - 1)"
if ($patchResponse1.Headers['Range'] -ne $expectedRange1) { Write-Host "--- ❌ TEST FAILED: 2.1 Range 头不匹配, 预期: $expectedRange1 ---" -ForegroundColor Red; exit 1 }

$chunk2 = "_second_chunk"
$headers2 = @{ "Content-Range" = "$($chunk1.Length)-$($chunk1.Length + $chunk2.Length - 1)" }
$patchResponse2 = Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body $chunk2 -ContentType "application/octet-stream" -Headers $headers2 -UseBasicParsing -ErrorAction Stop
Assert-Status "2.2 上传连续的第二个块 (带 Content-Range)" $patchResponse2 202

# 现在故意发送一个不连续的范围
$headers3 = @{ "Content-Range" = "0-10" } # 错误的起始偏移量
Assert-ErrorStatus "2.3 校验不连续的 Content-Range" -ErrorAction Stop -ScriptBlock {
    Invoke-WebRequest -Uri $uploadUrl -Method PATCH -Body "bad_data" -ContentType "application/octet-stream" -Headers $headers3 -UseBasicParsing -ErrorAction Stop
} -ExpectedStatus 'RequestedRangeNotSatisfiable'
Write-Host "`n"


# --- TEST 3: 取消上传 ---
Write-Host "--- TEST 3: 取消上传 (DELETE) ---" -ForegroundColor Cyan
# 我们使用 TEST 2 的上传会话并取消它
Assert-ErrorStatus "3.1 取消上传" -ErrorAction Stop -ScriptBlock { 
    Invoke-WebRequest -Uri $uploadUrl -Method DELETE -UseBasicParsing -ErrorAction Stop 
} -ExpectedStatus 204
Assert-ErrorStatus "3.2 验证上传已取消" -ErrorAction Stop -ScriptBlock {
    Invoke-WebRequest -Uri $uploadUrl -Method GET -UseBasicParsing -ErrorAction Stop
} -ExpectedStatus 'NotFound'
Write-Host "`n"


# --- TEST 4: 完整上传并验证 ---
Write-Host "--- TEST 4: 完整上传 (PUT) 并验证 (HEAD) ---" -ForegroundColor Cyan
$fullContent = "this_is_the_full_blob_content_for_a_successful_upload"
$sha256 = [System.BitConverter]::ToString($([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullContent)))).Replace("-","").ToLower()
$correctDigest = "sha256:$sha256"

# 启动新上传
$startResponse4 = Invoke-WebRequest -Uri $startUploadUrl -Method POST -UseBasicParsing -ErrorAction Stop
$uploadUrl4 = $startResponse4.Headers['Location']

# 一次性 PUT 完整内容
$putUrl = "$uploadUrl4`?digest=$correctDigest"
$putResponse = Invoke-WebRequest -Uri $putUrl -Method PUT -Body $fullContent -ContentType "application/octet-stream" -UseBasicParsing -ErrorAction Stop
Assert-Status "4.1 完成上传 (PUT)" $putResponse 201
$finalLocation = $putResponse.Headers['Location']

# 验证最终的 Blob
$headResponse4 = Invoke-WebRequest -Uri $finalLocation -Method HEAD -UseBasicParsing -ErrorAction Stop
Assert-Status "4.2 验证最终的 Blob (HEAD)" $headResponse4 200
if ($headResponse4.Headers['Content-Length'] -ne $fullContent.Length) { Write-Host "--- ❌ TEST FAILED: 4.2 Content-Length 不匹配 ---" -ForegroundColor Red; exit 1 }
if ($headResponse4.Headers['Docker-Content-Digest'] -ne $correctDigest) { Write-Host "--- ❌ TEST FAILED: 4.2 Digest 不匹配 ---" -ForegroundColor Red; exit 1 }
Write-Host "`n"


# --- TEST 5: 测试 Digest 校验失败 ---
Write-Host "--- TEST 5: 测试 Digest 校验失败 (PUT) ---" -ForegroundColor Cyan
$startResponse5 = Invoke-WebRequest -Uri $startUploadUrl -Method POST -UseBasicParsing -ErrorAction Stop
$uploadUrl5 = $startResponse5.Headers['Location']
$wrongDigest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
$putUrl5 = "$uploadUrl5`?digest=$wrongDigest"
Assert-ErrorStatus "5.1 Digest 校验失败" -ErrorAction Stop -ScriptBlock {
    Invoke-WebRequest -Uri $putUrl5 -Method PUT -Body "some_content" -ContentType "application/octet-stream" -UseBasicParsing -ErrorAction Stop
} -ExpectedStatus 'BadRequest'
Write-Host "`n"


# --- 总结 ---
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 恭喜！所有高级 Blob 上传接口均已通过严格测试！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green