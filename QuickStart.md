## 🚀 快速上手

### 第 1 步：配置 Docker

编辑 Docker 配置文件 (在 Docker Desktop 中是 `Settings > Docker Engine`)，加入以下内容，然后**重启 Docker**。

```json
{
  "insecure-registries": ["localhost:5000"]
}
```

*(在 Windows/macOS 的 Docker Desktop 中，可能需要使用 `host.docker.internal:5000`)*

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

打开一个新的终端，体验完整的 `push` 和 `pull` 流程：

```bash
# 1. 拉取一个官方镜像
docker pull hello-world

# 2. 给它打上指向本地 Registry 的标签
docker tag hello-world localhost:5000/my-cool-repo/hello-world:latest

# 3. 推送 Registry，观察 Go/Java 服务终端，会看到滚动的 HTTP 请求日志
docker push localhost:5000/my-cool-repo/hello-world:latest

# 4. 拉取 Registry 
docker pull localhost:5000/my-cool-repo/hello-world:latest
```

如果想直接测试也可以使用 /test 下的测试文件，但有些由于测试时期不同、版本不同不能通过，不能保证测试准确性
