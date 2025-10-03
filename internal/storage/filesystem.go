package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	"docker-registry-lite/internal/registry"
)

// FileSystemStorage 实现了基于本地文件系统的存储驱动。
type FileSystemStorage struct {
	rootDirectory string
}

/**
	初始化文件系统存储
**/

// NewFileSystemStorage 创建一个新的文件系统存储实例
// 它会确保所有必要的根目录都已创建。
func NewFileSystemStorage(root string) (*FileSystemStorage, error) {
	// 确保根目录是绝对路径，避免混淆
	root, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}

	fs := &FileSystemStorage{rootDirectory: root}

	// 创建 Registry 所需的核心目录结构
	// 使用 MkdirAll 可以安全地重复调用，如果目录已存在则什么也不做
	if err := fs.ensureDir(fs.repositoriesPath()); err != nil {
		return nil, err
	}
	if err := fs.ensureDir(fs.blobsPath()); err != nil {
		return nil, err
	}

	return fs, nil
}

// --- 路径辅助函数 ---

// path 构建相对于存储根目录的路径
func (fs *FileSystemStorage) path(p ...string) string {
	return filepath.Join(fs.rootDirectory, filepath.Join(p...))
}

// repositoriesPath 返回仓库根目录路径
func (fs *FileSystemStorage) repositoriesPath() string {
	return fs.path("v2", "repositories")
}

// blobsPath 返回 blobs 根目录路径
func (fs *FileSystemStorage) blobsPath() string {
	return fs.path("v2", "blobs")
}

// --- 路径计算 ---

// getBlobPath 计算给定 digest 的 Blob 存储路径。
// 格式: <root>/v2/blobs/<alg>/<xx>/<digest>/data
func (fs *FileSystemStorage) getBlobPath(digest string) (string, error) {
	parts := strings.SplitN(digest, ":", 2)
	if len(parts) != 2 {
		return "", fmt.Errorf("invalid digest format: %s", digest)
	}
	alg, hex := parts[0], parts[1]
	if len(hex) < 2 {
		return "", fmt.Errorf("invalid digest hex: %s", hex)
	}

	return fs.path("v2", "blobs", alg, hex[:2], hex, "data"), nil
}

// getUploadPath 计算给定上传 ID 的临时目录路径。
// 格式: <root>/v2/repositories/<name>/_uploads/<uuid>
func (fs *FileSystemStorage) getUploadPath(repoName, uploadID string) string {
	return fs.path("v2", "repositories", repoName, "_uploads", uploadID)
}

// getManifestTagPath 计算给定仓库和 tag 的 link 文件路径。
// 格式: <root>/v2/repositories/<name>/_manifests/tags/<tag>/current/link
func (fs *FileSystemStorage) getManifestTagPath(repoName, tag string) string {
	return fs.path("v2", "repositories", repoName, "_manifests", "tags", tag, "current", "link")
}

// ensureDir 确保给定的目录路径存在。
func (fs *FileSystemStorage) ensureDir(path string) error {
	return os.MkdirAll(path, 0755)
}

// --- Blob 操作 ---

// --- 存在性检测 ---
// 检测Blob存在性，并返回其大小。
// 如果 Blob 不存在，返回 registry.ErrBlobNotFound 错误。
func (fs *FileSystemStorage) StatBlob(digest string) (int64, error) {
	path, err := fs.getBlobPath(digest)
	if err != nil {
		return 0, err
	}

	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, registry.ErrBlobNotFound
		}
		return 0, err
	}
	return info.Size(), nil
}

// --- 下载内容 ---
// GetBlob 返回一个可读的 io.ReadCloser 来访问 Blob 数据。
// 调用者有责任关闭返回的 reader。
func (fs *FileSystemStorage) GetBlob(digest string) (io.ReadCloser, error) {
	path, err := fs.getBlobPath(digest)
	if err != nil {
		return nil, err
	}

	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, registry.ErrBlobNotFound
		}
		return nil, err
	}
	return file, nil
}

// --- 上传操作 ---
// StartUpload 在指定仓库下开始一个新的 Blob 上传，返回一个唯一的上传ID。
func (fs *FileSystemStorage) StartUpload(repoName string) (string, error) {
	// 1. 生成唯一标识符
	// 每个上传会话都必须是唯一的，即使有成千上万个并发上传。
	// UUID (Universally Unique Identifier) 是实现这一点的完美工具。
	// 这个 UUID 就是客户端后续请求中需要携带的 <uuid>。
	uploadID := uuid.NewString()

	// 2. 确定临时工作区的路径
	// 我们利用之前定义的辅助函数，根据仓库名和新生成的 UUID 计算出一个唯一的目录路径。
	// 例如: /var/lib/registry/v2/repositories/my-app/_uploads/a1b2c3d4-....
	uploadPath := fs.getUploadPath(repoName, uploadID)

	// 创建工作区目录
	if err := fs.ensureDir(uploadPath); err != nil {
		return "", err
	}

	// 创建一个空的 data 文件，用于后续追加数据
	dataPath := filepath.Join(uploadPath, "data")
	file, err := os.Create(dataPath)
	if err != nil {
		return "", err
	}
	file.Close()

	// 创建一个 startedat 文件，记录开始时间，便于未来清理过期上传
	startedAtPath := filepath.Join(uploadPath, "startedat")

	return uploadID, os.WriteFile(startedAtPath, []byte(time.Now().Format(time.RFC3339)), 0644)
}

// AppendChunk 向一个正在进行的上传追加数据块。
// 返回追加后的总字节数。
func (fs *FileSystemStorage) AppendChunk(repoName, uploadID string, chunk io.Reader) (int64, error) {
	uploadPath := fs.getUploadPath(repoName, uploadID)
	dataPath := filepath.Join(uploadPath, "data")

	// 检查上传会话是否存在
	if _, err := os.Stat(uploadPath); os.IsNotExist(err) {
		return 0, registry.ErrUploadNotFound
	}

	// 以追加模式打开文件
	file, err := os.OpenFile(dataPath, os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Printf("[ERROR] AppendChunk: failed to open file for append: %v", err)
		return 0, err
	}
	defer file.Close()

	// 将 chunk 数据拷贝到文件末尾
	_, err = io.Copy(file, chunk)
	if err != nil {
		log.Printf("[ERROR] AppendChunk: failed to write chunk: %v", err)
		return 0, err
	}

	if err := file.Sync(); err != nil {
		return 0, err
	}
	// 解决在 handleBlobUploadCommit 中遇到的竞争条件问题。
	// 获取文件当前大小
	info, err := file.Stat()
	if err != nil {
		return 0, err
	}
	return info.Size(), nil
}

// CommitUpload 完成一个上传。
// 它会校验临时文件的 digest 是否与客户端提供的 digest 匹配。
// 如果匹配，将文件移动到最终的内容寻址位置，并清理临时目录。
func (fs *FileSystemStorage) CommitUpload(repoName, uploadID, expectedDigest string) error {
	uploadPath := fs.getUploadPath(repoName, uploadID)
	dataPath := filepath.Join(uploadPath, "data")

	// 检查数据文件是否存在
	_, err := os.Stat(dataPath)
	if err != nil {
		if os.IsNotExist(err) {
			return registry.ErrUploadNotFound
		}
		return err
	}

	// 1. 计算文件的实际 digest
	file, err := os.Open(dataPath)
	if err != nil {
		return err
	}

	hasher := sha256.New()
	_, err = io.Copy(hasher, file)
	file.Close() // *** 重要：立即关闭文件 ***

	if err != nil {
		return err
	}

	calculatedDigest := "sha256:" + hex.EncodeToString(hasher.Sum(nil))

	if calculatedDigest != expectedDigest {
		log.Printf("[ERROR] CommitUpload: digest mismatch - calculated=%s, expected=%s", calculatedDigest, expectedDigest)
		// 清理临时目录
		os.RemoveAll(uploadPath)
		return registry.ErrDigestMismatch
	}

	// 2. 移动文件到最终位置
	finalPath, err := fs.getBlobPath(expectedDigest)
	if err != nil {
		return err
	}

	// 如果 blob 已经存在，则无需移动，直接成功并清理
	if _, err := os.Stat(finalPath); err == nil {
		os.RemoveAll(uploadPath)
		return nil
	}

	// 创建目标目录
	if err := fs.ensureDir(filepath.Dir(finalPath)); err != nil {
		return err
	}

	// 使用 os.Rename，这在大多数文件系统上是原子操作
	if err := os.Rename(dataPath, finalPath); err != nil {
		log.Printf("[ERROR] CommitUpload: failed to move blob to final location: %v", err)
		return err
	}

	// 清理临时上传目录
	os.RemoveAll(uploadPath)

	return nil
}

// DeleteUpload 删除上传会话
func (fs *FileSystemStorage) DeleteUpload(repo, uploadID string) error {
	uploadPath := fs.getUploadPath(repo, uploadID)
	return os.Remove(uploadPath)
}

// --- Manifest 操作 ---

// getManifestPlatform 用于从一个 manifest 内容中解析出其平台信息。
// 通过读取 manifest 指向的 config blob 来实现。
func (fs *FileSystemStorage) getManifestPlatform(manifestBytes []byte) (*registry.PlatformSpec, error) {
	var m registry.Manifest
	if err := json.Unmarshal(manifestBytes, &m); err != nil {
		// 如果解析失败，可能不是一个单架构 manifest，我们暂时不处理这种情况
		return nil, fmt.Errorf("not a single-arch manifest")
	}

	configBytes, err := fs.GetBlobAsBytes(m.Config.Digest)
	if err != nil {
		return nil, fmt.Errorf("failed to get config blob %s: %w", m.Config.Digest, err)
	}

	var config registry.ImageConfig
	if err := json.Unmarshal(configBytes, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config json: %w", err)
	}

	return &registry.PlatformSpec{
		Architecture: config.Architecture,
		OS:           config.OS,
	}, nil
}

// GetBlobAsBytes 是 GetBlob 的一个便利封装，直接返回字节切片。
func (fs *FileSystemStorage) GetBlobAsBytes(digest string) ([]byte, error) {
	reader, err := fs.GetBlob(digest)
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	return io.ReadAll(reader)
}

// writeBlobData 封装了 Create->Write->Sync->Close 流程，用于以健壮的方式将数据写入 blob 存储。
func (fs *FileSystemStorage) writeBlobData(digest string, data []byte) error {
	path, err := fs.getBlobPath(digest)
	if err != nil {
		return err
	}
	if err := fs.ensureDir(filepath.Dir(path)); err != nil {
		return err
	}

	file, err := os.Create(path)
	if err != nil {
		return err
	}

	_, err = file.Write(data)
	if err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

// PutManifest (最终版) - 实现了智能的 manifest list 维护和健壮的文件写入。
// reference 可以是 tag 或 digest。
// newManifestBytes 是客户端上传的单架构 manifest 内容。
func (fs *FileSystemStorage) PutManifest(repoName, reference, contentType string, newManifestBytes []byte) (string, error) {
	// 步骤 1: 存储新上传的 manifest blob...
	hasher := sha256.New()
	hasher.Write(newManifestBytes)
	newDigest := "sha256:" + hex.EncodeToString(hasher.Sum(nil))
	if err := fs.writeBlobData(newDigest, newManifestBytes); err != nil {
		return "", fmt.Errorf("failed to write new manifest blob: %w", err)
	}

	if strings.HasPrefix(reference, "sha256:") {
		return newDigest, nil
	}

	tag := reference
	tagPath := fs.getManifestTagPath(repoName, tag)
	newPlatform, err := fs.getManifestPlatform(newManifestBytes)
	if err != nil {
		return newDigest, os.WriteFile(tagPath, []byte(newDigest), 0644)
	}

	// 步骤 2: 准备 worklist...
	var worklist []registry.ManifestDescriptor
	existingDigestBytes, err := os.ReadFile(tagPath)
	if err == nil {
		// ... (构建 worklist 的逻辑与之前相同) ...
		existingDigest := string(existingDigestBytes)
		existingContentBytes, _, _, err := fs.GetManifest(repoName, existingDigest)
		if err == nil {
			var existingList registry.ManifestList
			if json.Unmarshal(existingContentBytes, &existingList) == nil && (strings.Contains(existingList.MediaType, "list") || strings.Contains(existingList.MediaType, "index")) {
				worklist = existingList.Manifests
			} else {
				platform, err := fs.getManifestPlatform(existingContentBytes)
				if err == nil {
					worklist = append(worklist, registry.ManifestDescriptor{MediaType: "application/vnd.docker.distribution.manifest.v2+json", Size: int64(len(existingContentBytes)), Digest: existingDigest, Platform: *platform})
				}
			}
		}
	}

	// 步骤 3: 添加/更新 worklist...
	newDescriptor := registry.ManifestDescriptor{MediaType: contentType, Size: int64(len(newManifestBytes)), Digest: newDigest, Platform: *newPlatform}
	foundAndReplaced := false
	for i := range worklist {
		if worklist[i].Platform.OS == newPlatform.OS && worklist[i].Platform.Architecture == newPlatform.Architecture {
			worklist[i] = newDescriptor
			foundAndReplaced = true
			break
		}
	}
	if !foundAndReplaced {
		worklist = append(worklist, newDescriptor)
	}

	// 步骤 4: 决定最终要标记的 digest...
	var finalDigestToTag string
	if len(worklist) <= 1 {
		// --- 最终的逻辑修复！ ---
		// 明确地从 worklist 中获取唯一的 digest，而不是依赖外部的 newDigest。
		if len(worklist) == 1 {
			finalDigestToTag = worklist[0].Digest
		} else { // len is 0, should not happen, but for safety
			finalDigestToTag = newDigest
		}
	} else {
		// 创建并保存 manifest list
		finalList := registry.ManifestList{SchemaVersion: 2, MediaType: "application/vnd.docker.distribution.manifest.list.v2+json", Manifests: worklist}
		finalListBytes, _ := json.MarshalIndent(finalList, "", "   ")
		finalListHasher := sha256.New()
		finalListHasher.Write(finalListBytes)
		finalListDigest := "sha256:" + hex.EncodeToString(finalListHasher.Sum(nil))
		if err := fs.writeBlobData(finalListDigest, finalListBytes); err != nil {
			return "", fmt.Errorf("failed to write new manifest list blob: %w", err)
		}
		finalDigestToTag = finalListDigest
	}

	// 步骤 5: 更新 tag 文件...
	if err := os.WriteFile(tagPath, []byte(finalDigestToTag), 0644); err != nil {
		return "", err
	}

	return newDigest, nil
}

// GetManifest 根据 reference (tag 或 digest) 获取 Manifest。
// 返回值: Manifest内容, Manifest的digest, Manifest的Content-Type, 错误
func (fs *FileSystemStorage) GetManifest(repoName, reference string) ([]byte, string, string, error) {
	var digest string

	// 判断 reference 是 tag 还是 digest
	if strings.HasPrefix(reference, "sha256:") {
		digest = reference
	} else {
		// 如果是 tag，需要读取 link 文件来找到 digest
		tagPath := fs.getManifestTagPath(repoName, reference)
		digestBytes, err := os.ReadFile(tagPath)
		if err != nil {
			if os.IsNotExist(err) {
				return nil, "", "", registry.ErrManifestNotFound
			}
			return nil, "", "", err
		}
		digest = string(digestBytes)
	}

	content, err := fs.GetBlobAsBytes(digest)
	if err != nil {
		if errors.Is(err, registry.ErrBlobNotFound) {
			return nil, "", "", registry.ErrManifestNotFound
		}
		return nil, "", "", err
	}

	// 智能 Content-Type 检测 ---
	// 不再硬编码 Content-Type，而是从内容本身推断它。
	var mediaType struct {
		MediaType string `json:"mediaType"`
	}

	var contentType string
	if err := json.Unmarshal(content, &mediaType); err == nil && mediaType.MediaType != "" {
		// 如果内容可以被解析为一个包含 "mediaType" 字段的 JSON，
		// 我们就信任这个字段。这是最可靠的方式。
		contentType = mediaType.MediaType
	} else {
		// 如果解析失败，或者没有 mediaType 字段，我们回退到一个安全的默认值。
		contentType = "application/octet-stream"
	}

	return content, digest, contentType, nil
}

// DeleteTag 删除一个 tag 链接。
// 注意：这不会删除 manifest blob 或任何相关的 layer blob。
func (fs *FileSystemStorage) DeleteTag(repoName, tag string) error {
	tagPath := fs.getManifestTagPath(repoName, tag)

	err := os.Remove(tagPath)
	if err != nil {
		if os.IsNotExist(err) {
			// 如果 tag 文件不存在，返回一个更具体的业务错误
			return registry.ErrTagNotFound
		}
		return err
	}
	return nil
}

// StatUpload 获取一个正在进行的上传的状态，即已接收的字节数。
func (fs *FileSystemStorage) StatUpload(repoName, uploadID string) (int64, error) {
	uploadPath := fs.getUploadPath(repoName, uploadID)
	dataPath := filepath.Join(uploadPath, "data")

	// 检查上传会话是否存在
	info, err := os.Stat(dataPath)
	if err != nil {
		if os.IsNotExist(err) {
			// 如果 data 文件或 upload 目录不存在，都视为 UploadNotFound
			return 0, registry.ErrUploadNotFound
		}
		return 0, err
	}

	return info.Size(), nil
}

// CancelUpload 中止一个上传并清理其临时数据。
func (fs *FileSystemStorage) CancelUpload(repoName, uploadID string) error {
	uploadPath := fs.getUploadPath(repoName, uploadID)

	// 检查上传会话是否存在，以返回正确的错误
	if _, err := os.Stat(uploadPath); err != nil {
		if os.IsNotExist(err) {
			return registry.ErrUploadNotFound
		}
		return err
	}

	// os.RemoveAll 会递归删除目录及其所有内容
	return os.RemoveAll(uploadPath)
}
