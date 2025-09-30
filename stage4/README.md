# Docker Registry Lite - Java Spring Boot 实现

一个符合 Docker Registry HTTP API V2 规范的简化后端服务，使用 Java Spring Boot 实现。

## 功能特性

- ✅ API 版本检查 (`GET /v2/`)
- ✅ Blob 分片上传功能
  - 开始上传 (`POST /v2/<name>/blobs/uploads/`)
  - 上传分片 (`PATCH /v2/<name>/blobs/uploads/<uuid>`)
  - 完成上传 (`PUT /v2/<name>/blobs/uploads/<uuid>?digest=<digest>`)
- ✅ Blob 查询功能
  - 检查存在性 (`HEAD /v2/<name>/blobs/<digest>`)
  - 下载 (`GET /v2/<name>/blobs/<digest>`)
- ✅ Manifest 操作功能
  - 上传 (`PUT /v2/<name>/manifests/<reference>`)
  - 下载 (`GET /v2/<name>/manifests/<reference>`)
  - 检查存在性 (`HEAD /v2/<name>/manifests/<reference>`)
- ✅ 完整性校验（SHA256 digest 验证）
- ✅ 错误处理和恢复机制
- ✅ 标准的 Docker Registry API 错误响应格式

## 技术栈

- Java 17
- Spring Boot 3.2.0
- Maven 3.x
- Apache Commons IO
- Lombok

## 项目结构

```
src/main/java/com/dockerregistry/
├── DockerRegistryApplication.java    # 主应用类
├── controller/
│   └── RegistryController.java       # REST API 控制器
├── service/
│   └── FileSystemStorageService.java # 文件系统存储服务
├── model/                            # 数据模型
│   ├── Descriptor.java
│   ├── Manifest.java
│   ├── ManifestList.java
│   ├── ManifestDescriptor.java
│   ├── PlatformSpec.java
│   ├── ErrorResponse.java
│   └── ErrorDetail.java
├── exception/                        # 异常类
│   ├── RegistryException.java
│   ├── BlobNotFoundException.java
│   ├── ManifestNotFoundException.java
│   ├── UploadNotFoundException.java
│   ├── DigestMismatchException.java
│   └── UnsupportedMediaTypeException.java
└── config/                          # 配置类
    ├── GlobalExceptionHandler.java
    └── WebConfig.java
```

## 编译和运行

### 前提条件

- Java 17 或更高版本
- Maven 3.6 或更高版本

### 编译

```bash
mvn clean compile
```

### 运行

```bash
mvn spring-boot:run
```

或者编译成 JAR 包后运行：

```bash
mvn clean package
java -jar target/docker-registry-lite-1.0.0.jar
```

程序将在 `:5000` 端口启动服务。

### 配置

可以通过环境变量或 application.properties 修改配置：

- `REGISTRY_STORAGE_ROOT`: 存储根目录路径，默认为 `${user.home}/.docker-registry`
- `SERVER_PORT`: 服务端口，默认为 5000

## 存储结构

数据存储在配置的存储根目录下，采用与官方 Docker Registry 兼容的文件系统布局：

```
<storage-root>/
└── v2/
    ├── blobs/          # 存放所有 Blob 数据
    │   └── sha256/
    │       └── xx/     # 按 digest 前两位分目录
    └── repositories/   # 存放仓库元数据
        └── <repo-name>/
            ├── _manifests/
            └── _uploads/   # 临时上传文件
```

## API 支持

本实现支持以下 Content-Type：

### Manifest 格式
- `application/vnd.docker.distribution.manifest.v2+json`
- `application/vnd.docker.distribution.manifest.list.v2+json`
- `application/vnd.oci.image.manifest.v1+json`
- `application/vnd.oci.image.index.v1+json`

### Blob 格式
- `application/octet-stream`

## 测试

在 Linux 系统中，你可以使用真实的 Docker 客户端来测试：

1. 配置 Docker 允许不安全的 registry（编辑 `/etc/docker/daemon.json`）：

```json
{
  "insecure-registries" : ["localhost:5000"]
}
```

2. 重启 Docker 服务：

```bash
sudo systemctl restart docker
```

3. 测试推送镜像：

```bash
# 拉取测试镜像
docker pull hello-world

# 给镜像打标签
docker tag hello-world localhost:5000/test/hello-world:latest

# 推送到本地 registry
docker push localhost:5000/test/hello-world:latest

# 拉取验证
docker pull localhost:5000/test/hello-world:latest
```

## 注意事项

- 本实现为简化版本，未包含认证和授权功能
- 目前只支持文件系统存储，未实现云存储支持
- 为简化实现，某些 OCI 特性可能不完整
- 适用于开发和测试环境，生产环境建议使用官方 Docker Registry

## 开发说明

这个实现与 stage3 中的 Go 版本功能完全一致，主要包括：

1. **完整的 Blob 分片上传支持** - 支持大文件的分片上传
2. **完整性校验** - 对所有上传内容进行 SHA256 校验
3. **错误处理** - 实现了完整的错误处理机制，防止程序意外退出
4. **标准错误响应** - 所有接口都实现了 400 和 404 错误响应
5. **Content-Type 处理** - 正确处理所有 HTTP 请求的 content-type
6. **Manifest 格式支持** - 支持多种 Manifest 和 Manifest List 格式