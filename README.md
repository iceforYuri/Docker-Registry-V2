# Docker Registry Lite 🚀

[![Go version](https://img.shields.io/badge/Go-1.21%2B-blue.svg)](https://golang.org/)
[![Java version](https://img.shields.io/badge/Java-17-orange.svg)](https://www.java.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

本仓库从零开始，完整实现了一个符合 **Docker Registry HTTP API V2** 核心规范的轻量级后端服务，并同时提供了两种主流语言的版本：

* **`stage3`**: **Go 实现**
* **`stage4`**: **Java Spring Boot 实现**

两个版本在 API 行为上完全一致，并都通过了完整的端到端自动化测试。

## 🚀 快速上手

### 第 1 步：配置 Docker

编辑 Docker 配置文件 (在 Docker Desktop 中是 `Settings > Docker Engine`)，加入以下内容，然后**重启 Docker**。

```json
{
  "insecure-registries": ["localhost:5000"]
}
```

*(在 Windows/macOS 的 Docker Desktop 中，可能需要使用 `host.docker.internal:5000`)*

### 第 2 步：选择一个版本并运行

**Go 版本 (stage3)**

```bash
# 导航到 Go 版本目录
cd stage3

# 构建并运行
go run ./cmd/registry/main.go

# 或者，构建一个独立的二进制文件
# go build -o registry ./cmd/registry/main.go
# ./registry
```

**Java 版本 (stage4)**

```bash
# 导航到 Java 版本目录
cd stage4

# 使用 Maven 构建并运行
mvn spring-boot:run

# 或者，构建一个 jar 包
# mvn clean package
# java -jar target/docker-registry-lite-1.0.0.jar
```

服务在 `5000` 端口上成功启动的日志时，表示可以开始下一步了~

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

## ✅ 功能清单

这个项目虽小，但尽力实现了 [Docker Registry HTTP API V2 规范](https://docs.docker.com/reference/api/registry/latest/) 所需的**全部核心接口**：

* [X] **API 版本检查**: `GET /v2/`
* [X] **完整的 Blob 分片上传流程**:

  * `POST` 开始上传 (支持跨仓库挂载！)
  * `GET` 查询上传状态 (支持断点续传)
  * `PATCH` 上传数据块
  * `PUT` 完成并校验
  * `DELETE` 取消上传
* [X] **Blob 下载与检查**: `GET` 和 `HEAD`
* [X] **Manifest 操作**: `GET`, `HEAD`, 和 `PUT`
* [X] **数据完整性**: 所有上传都经过严格的 SHA256 `digest` 校验。
* [X] **广泛的兼容性**: 同时支持 Docker V2.2 和 OCI v1 的 Manifest 与 Index 媒体类型。

## 🧪 测试？覆盖

两个版本都配备了**自动化的端到端测试脚本**，模拟了从 `push` 到 `pull` 的完整流程，并对每一个独立的 API 接口进行了显式验证。

* **Go 版本**: `stage3/test_all.ps1` (Windows), `stage3/test_api.sh` (Linux)
* **Java 版本**: `stage4/test_registry_comprehensive.ps1` (Windows), `stage4/test_basic.sh` (Linux)

**结论**: 两个版本的接口经调整后行为基本一致，所有测试均已通过

## 📚 深入探索

每个版本的目录都有一份更详细的、专注于其自身实现的文档。

* **Go 版本深度解析**: `stage3/README.md`
* **Java 版本深度解析**: `stage4/README.md`

项目的基础设计文档被放在`stage3/设计与实现文档.md`，项目也是在这个基础上学习和借鉴文档一步步搭建起来的

---

感谢你的探索！希望这个项目能帮助你更好地理解 Docker Registry 的内部工作原理。欢迎提出问题或建议！
