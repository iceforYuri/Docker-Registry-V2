## 🚀 快速上手

### 第 1 步：配置 Docker（仅docker测试中使用需要）

编辑 Docker 配置文件 (在 Docker Desktop 中是 `Settings > Docker Engine`)，加入以下内容，然后**重启 Docker**。

```json
{
  "insecure-registries": ["localhost:5000"]
}
```

### 第 2 步：直接运行或者使用已编译的可执行文件

**Go 版本 (stage3)**

```bash
# 导航到 Go 版本目录
cd stage3

# 构建并运行
go run ./cmd/registry/main.go

# 在目录下直接执行二进制文件
./registry
```

### 第 3 步：尝试操作

打开一个新的终端，体验完整的 docker `push` 和 `pull` 流程：

```bash
# 1. 拉取一个官方镜像
docker pull hello-world

# 2. 给它打上指向本地 Registry 的标签
docker tag hello-world localhost:5000/my-cool-repo/hello-world:latest

# 3. 推送 Registry，观察 Go 服务终端，会看到滚动的 HTTP 请求日志
docker push localhost:5000/my-cool-repo/hello-world:latest

# 4. 拉取 Registry 
docker pull localhost:5000/my-cool-repo/hello-world:latest
```

当然不安装 docker 可以使用 bash 语法进行简单测试：

```bash
# 1. 服务就绪检查
curl -i http://localhost:5000/v2/

# 2. 启动一个 blob 上传（POST），记录 Location 和 UUID
resp=$(curl -i -s -X POST http://localhost:5000/v2/myrepo/blobs/uploads/)
echo "$resp"    # 查看响应头，找到 Location: /v2/...
upload_url=$(echo "$resp" | awk '/Location:/ {print $2}' | tr -d '\r\n')

# 3. 查询上传状态（expect 204）
curl -i -X GET "$upload_url"

# 4. 上传一个小块（PATCH），示例用 "hello" 作为内容
curl -i -X PATCH --data-binary 'hello' -H "Content-Type: application/octet-stream" "$upload_url"

# 5. 完成上传：用 ?digest=sha256:<digest>
digest=$(printf 'hello' | sha256sum | awk '{print $1}')
curl -i -X PUT --data-binary '' "$upload_url?digest=sha256:$digest"

# 6. 验证 manifest/blob 可被访问（视实现而定）
curl -i http://localhost:5000/v2/myrepo/blobs/sha256:$digest
```

Powershell 运行版本：

```powershell
$REGISTRY_HOST = "localhost:5000"
$API_BASE = "http://$REGISTRY_HOST/v2"
$REPO_NAME = "myrepo"

Write-Host "`n=== 1. 服务就绪检查 ===" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$API_BASE/" -Method GET -UseBasicParsing
    Write-Host "✅ Registry 可访问，状态码: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ Registry 不可访问: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== 2. 启动 blob 上传 (POST) ===" -ForegroundColor Cyan
$startUploadUrl = "$API_BASE/$REPO_NAME/blobs/uploads/"
$response = Invoke-WebRequest -Uri $startUploadUrl -Method POST -UseBasicParsing
$uploadUrl = $response.Headers['Location']  # 这是相对路径，如 /v2/myrepo/blobs/uploads/xxx
$uuid = $response.Headers['Docker-Upload-UUID']
Write-Host "✅ 上传已启动" -ForegroundColor Green
Write-Host "   Location: $uploadUrl"
Write-Host "   UUID: $uuid"

# 修复：如果 Location 是相对路径，补全为绝对 URL
if ($uploadUrl -notmatch "^https?://") {
    $uploadUrl = "http://$REGISTRY_HOST$uploadUrl"
}

Write-Host "`n=== 3. 查询上传状态 (GET) ===" -ForegroundColor Cyan
$response = Invoke-WebRequest -Uri $uploadUrl -Method GET -UseBasicParsing
Write-Host "✅ 状态码: $($response.StatusCode) (期望 204)" -ForegroundColor Green

Write-Host "`n=== 4. 上传数据块 (PATCH) ===" -ForegroundColor Cyan
$content = "hello"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
$response = Invoke-WebRequest -Uri $uploadUrl `
    -Method PATCH `
    -Body $bytes `
    -ContentType "application/octet-stream" `
    -UseBasicParsing
Write-Host "✅ 数据已上传，状态码: $($response.StatusCode)" -ForegroundColor Green

# 更新 uploadUrl（可能返回新的 Location）
$newLocation = $response.Headers['Location']
if ($newLocation) {
    if ($newLocation -notmatch "^https?://") {
        $uploadUrl = "http://$REGISTRY_HOST$newLocation"
    } else {
        $uploadUrl = $newLocation
    }
}

Write-Host "`n=== 5. 计算 SHA256 并完成上传 (PUT) ===" -ForegroundColor Cyan
# PowerShell 计算 SHA256
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($bytes)
$digest = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ''
Write-Host "   计算的 digest: sha256:$digest"

# 修复：直接在 uploadUrl 上追加 digest 参数
$completeUrl = $uploadUrl + "?digest=sha256:$digest"
Write-Host "   完成 URL: $completeUrl"

$response = Invoke-WebRequest -Uri $completeUrl -Method PUT -UseBasicParsing
Write-Host "✅ 上传完成，状态码: $($response.StatusCode) (期望 201)" -ForegroundColor Green

Write-Host "`n=== 6. 验证 blob 可被访问 (GET) ===" -ForegroundColor Cyan
$blobUrl = "$API_BASE/$REPO_NAME/blobs/sha256:$digest"
try {
    $response = Invoke-WebRequest -Uri $blobUrl -Method GET -UseBasicParsing
    Write-Host "✅ Blob 可访问，状态码: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "   内容: $([System.Text.Encoding]::UTF8.GetString($response.Content))"
} catch {
    $errorBody = $_.ErrorDetails.Message
    Write-Host "❌ Blob 访问失败: $errorBody" -ForegroundColor Red
}

Write-Host "`n=== 测试完成 ===" -ForegroundColor Green
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
```

如果想直接测试也可以使用 /test 下的测试文件，但有些由于测试时期不同、版本不同不能通过，不能保证测试准确性
