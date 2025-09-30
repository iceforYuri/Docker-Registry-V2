# Docker Registry Lite

一个符合 Docker Registry HTTP API V2 规范的简化后端服务，使用 Go 语言实现。支持完整的容器镜像推送、拉取和存储功能。

## 项目结构

```
docker-registry-lite/
├── cmd/
│   └── registry/
│       └── main.go         # 程序主入口，HTTP 服务器启动和配置
├── internal/                # 内部包，不对外暴露
│   ├── handler/            # HTTP 请求处理层
│   │   ├── api.go          # 路由注册和基础 API
│   │   ├── handler.go      # 处理器基础结构
│   │   ├── blobs.go        # Blob 相关操作实现
│   │   ├── manifests.go    # Manifest 相关操作实现
│   │   └── utils.go        # 通用工具函数
│   ├── middleware/         # HTTP 中间件
│   │   └── recovery.go     # Panic 恢复和错误处理
│   ├── registry/           # 核心业务模型
│   │   ├── errors.go       # 自定义错误类型和响应格式
│   │   └── types.go        # Manifest、Blob 等数据结构定义
│   └── storage/            # 存储抽象层
│       └── filesystem.go   # 文件系统存储实现
├── go.mod                  # Go 模块定义
├── go.sum                  # 依赖版本锁定
├── build.sh               # Linux 编译脚本
├── test_api.sh            # API 功能测试脚本（Bash）
├── test_all.ps1           # 综合测试脚本（PowerShell）
└── registry.exe           # Windows 可执行文件
```

## 完整功能特性

### ✅ 核心 API 端点
- **基础 API**: `GET /v2/` - API 版本检查和兼容性验证
- **完整的容器镜像推送/拉取支持**
- **跨平台兼容**：Windows 和 Linux 环境

### ✅ Blob 操作（分层文件管理）
| 方法 | 端点 | 功能 | 状态 |
|------|------|------|------|
| `POST` | `/v2/{name}/blobs/uploads/` | 开始分片上传 | ✅ 完整实现 |
| `GET` | `/v2/{name}/blobs/uploads/{uuid}` | 查询上传状态 | ✅ 完整实现 |
| `PATCH` | `/v2/{name}/blobs/uploads/{uuid}` | 上传数据分片 | ✅ 完整实现 |
| `PUT` | `/v2/{name}/blobs/uploads/{uuid}?digest=<digest>` | 完成上传并校验 | ✅ 完整实现 |
| `DELETE` | `/v2/{name}/blobs/uploads/{uuid}` | 取消上传 | ✅ 完整实现 |
| `HEAD` | `/v2/{name}/blobs/{digest}` | 检查 Blob 存在性 | ✅ 完整实现 |
| `GET` | `/v2/{name}/blobs/{digest}` | 下载 Blob 数据 | ✅ 完整实现 |

### ✅ Manifest 操作（镜像元数据管理）
| 方法 | 端点 | 功能 | 状态 |
|------|------|------|------|
| `PUT` | `/v2/{name}/manifests/{reference}` | 上传 Manifest | ✅ 完整实现 |
| `GET` | `/v2/{name}/manifests/{reference}` | 获取 Manifest | ✅ 完整实现 |
| `HEAD` | `/v2/{name}/manifests/{reference}` | 检查 Manifest 存在性 | ✅ 完整实现 |
| `DELETE` | `/v2/{name}/manifests/{reference}` | 删除 Manifest（按标签） | ✅ 简化实现 |

### ✅ 数据完整性和安全性
- **SHA256 Digest 校验**：所有 Blob 上传都进行完整性验证
- **原子性操作**：确保部分失败时的数据一致性
- **错误恢复**：Panic 恢复机制防止服务器崩溃
- **标准错误响应**：符合 Docker Registry API 错误格式

### ✅ 存储和性能
- **内容寻址存储**：基于 SHA256 的去重存储
- **分片上传支持**：支持大文件的断点续传
- **文件系统布局**：与官方 Docker Registry 兼容的存储结构
- **跨平台路径处理**：自动适配 Windows/Linux 路径差异

## 环境配置

### 环境变量
- `REGISTRY_LISTEN`: 监听地址（默认 `:5000`）
- `REGISTRY_STORAGE_ROOT`: 存储根目录（Windows 默认 `F:\docker-registry-data`，Linux 默认 `~/.local/share/docker-registry`）

### Windows 环境编译运行
```powershell
# 编译
go build -o registry.exe ./cmd/registry

# 运行
.\registry.exe

# 或指定存储位置
$env:REGISTRY_STORAGE_ROOT = "D:\docker-data"
.\registry.exe
```

### Linux 环境编译运行
```bash
# 使用提供的编译脚本
./build.sh

# 或手动编译
go build -o registry ./cmd/registry

# 运行
./registry

# 或指定存储位置
REGISTRY_STORAGE_ROOT=/opt/registry-data ./registry
```

## 测试和验证

### 1. 使用真实 Docker 客户端测试
```bash
# 配置 Docker 信任本地 registry（/etc/docker/daemon.json）
{
  "insecure-registries" : ["host.docker.internal:5000", "localhost:5000"]
}

# 重启 Docker 服务
sudo systemctl restart docker  # Linux
# 或重启 Docker Desktop    # Windows

# 测试推送
docker pull alpine:latest
docker tag alpine:latest localhost:5000/test/alpine:latest
docker push localhost:5000/test/alpine:latest

# 测试拉取
docker rmi localhost:5000/test/alpine:latest
docker pull localhost:5000/test/alpine:latest
```

### 2. 使用提供的测试脚本
```bash
# Linux/WSL
./test_api.sh

# Windows PowerShell
.\test_all.ps1
```

## 存储结构详解

```
{REGISTRY_STORAGE_ROOT}/
└── docker/
    └── registry/
        └── v2/
            ├── blobs/                    # 内容寻址 Blob 存储
            │   └── sha256/
            │       ├── xx/               # 按 digest 前两位分目录
            │       │   └── xxxx...       # 实际 Blob 文件
            │       └── yy/
            └── repositories/             # 仓库元数据
                └── {repository-name}/
                    ├── _manifests/
                    │   ├── revisions/    # Manifest 版本存储
                    │   │   └── sha256/
                    │   └── tags/         # 标签到 digest 映射
                    │       └── {tag}/
                    └── _uploads/         # 临时上传会话
                        └── {upload-uuid}/
                            ├── data      # 上传数据文件
                            └── startedat # 上传开始时间
```

## 支持的媒体类型

### Manifest 格式
- `application/vnd.docker.distribution.manifest.v2+json` （Docker Manifest v2）
- `application/vnd.docker.distribution.manifest.list.v2+json` （Docker Manifest List）
- `application/vnd.oci.image.manifest.v1+json` （OCI Image Manifest）
- `application/vnd.oci.image.index.v1+json` （OCI Image Index）

### Blob 格式
- `application/octet-stream` （所有 Blob 数据）

## 设计权衡和限制

### ✅ 已实现的生产特性
- 完整的 Docker Registry API v2 核心功能
- 数据完整性校验和原子性操作
- 标准错误处理和恢复机制
- 跨平台兼容性（Windows/Linux）

### ⚠️ 简化的实现
- **DELETE 操作**：仅支持按标签删除，不支持按 digest 删除（避免引用计数复杂性）
- **Content-Type 持久化**：Manifest 的 Content-Type 暂时硬编码返回
- **认证授权**：未实现用户认证和权限控制（适用于内网环境）
- **垃圾回收**：未实现自动清理孤立 Blob 的机制

### 🎯 适用场景
- ✅ **开发测试环境**：本地容器镜像存储和分发
- ✅ **内网环境**：私有容器镜像仓库
- ✅ **学习研究**：理解 Docker Registry 工作原理
- ❌ **生产环境**：建议使用官方 Docker Registry 或商业解决方案

## 依赖项
- **Go 1.21+**：主要编程语言
- **gorilla/mux v1.8.0**：HTTP 路由框架
- **google/uuid v1.3.0**：UUID 生成库

## 性能特点
- **低资源占用**：单一二进制文件，无需数据库
- **高并发支持**：基于 Go 的协程并发模型
- **快速启动**：秒级启动时间
- **内存效率**：流式处理大文件，避免内存占用过大