// file: internal/handler/manifests.go
package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"docker-registry-lite/internal/registry"
	// "docker-registry-lite/"
	"github.com/gorilla/mux"
)

// handleManifestGet 负责处理 GET /v2/{name}/manifests/{reference} 请求。
// 它可以获取一个 Manifest 或 Manifest List。
func (h *Handler) handleManifestGet(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 中提取变量
	vars := mux.Vars(r)
	repoName := vars["name"]
	reference := vars["reference"]

	// TODO: 验证 'Accept' 头，确保客户端可以接收我们支持的 manifest 类型。
	// 为简化起见，暂时跳过此步骤。

	// 2. 调用存储层获取 Manifest
	content, digest, contentType, err := h.Storage.GetManifest(repoName, reference)
	if err != nil {
		// 3. 错误处理
		if errors.Is(err, registry.ErrManifestNotFound) {
			// 如果 manifest 不存在，返回 404 Not Found
			// 根据规范，这里应该返回一个标准的错误 JSON 体
			registry.WriteErrorResponse(w, http.StatusNotFound, "MANIFEST_UNKNOWN", "manifest unknown")
			return
		}
		// 对于其他未知错误，返回 500
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "an internal error occurred")
		return
	}

	// 4. 设置成功的响应头
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(content)))
	w.Header().Set("Docker-Content-Digest", digest)

	// 5. 写入 200 OK 状态码和 Manifest 内容
	w.WriteHeader(http.StatusOK)
	w.Write(content)
}

// handleManifestHead 负责处理 HEAD /v2/{name}/manifests/{reference} 请求。
// 它用于检查 Manifest 的存在性并获取其元数据，但不返回 Manifest 内容本身。
func (h *Handler) handleManifestHead(w http.ResponseWriter, r *http.Request) {
	// 逻辑与 GET 请求几乎完全相同，只是最后不写入响应体。
	vars := mux.Vars(r)
	repoName := vars["name"]
	reference := vars["reference"]

	content, digest, contentType, err := h.Storage.GetManifest(repoName, reference)
	if err != nil {
		if errors.Is(err, registry.ErrManifestNotFound) {
			w.WriteHeader(http.StatusNotFound) // 对于 HEAD 请求，可以不返回 body
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	// 设置与 GET 请求完全相同的头信息
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(content)))
	w.Header().Set("Docker-Content-Digest", digest)

	w.WriteHeader(http.StatusOK)
	// 注意：对于 HEAD 请求，我们在这里停止，不调用 w.Write()
}

// handleManifestPut 负责处理 PUT /v2/{name}/manifests/{reference} 请求。
func (h *Handler) handleManifestPut(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量
	vars := mux.Vars(r)
	repoName := vars["name"]
	reference := vars["reference"]

	// 2. 验证 Content-Type
	contentType := r.Header.Get("Content-Type")
	log.Printf("[DEBUG] handleManifestPut: received Content-Type: '%s'", contentType)

	// --- Bug 修复：增加对 OCI 媒体类型的支持 ---
	switch contentType {
	case "application/vnd.docker.distribution.manifest.v2+json",
		"application/vnd.docker.distribution.manifest.list.v2+json",
		"application/vnd.oci.image.manifest.v1+json",
		"application/vnd.oci.image.index.v1+json":
		// 这是我们支持的类型，什么也不做，继续执行
	default:
		// 如果不是以上任何一种，则返回错误
		registry.WriteErrorResponse(w, http.StatusUnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE", "unsupported manifest media type")
		return
	}

	// Docker 客户端可能使用各种不同的 manifest 格式
	supportedTypes := []string{
		"application/vnd.docker.distribution.manifest.v2+json",
		"application/vnd.docker.distribution.manifest.list.v2+json",
		"application/vnd.docker.distribution.manifest.v1+json", // OCI 格式
		"application/vnd.oci.image.manifest.v1+json",           // OCI Image manifest
	}

	supported := false
	for _, supportedType := range supportedTypes {
		if contentType == supportedType {
			supported = true
			break
		}
	}

	if !supported {
		log.Printf("[ERROR] handleManifestPut: unsupported Content-Type: '%s'", contentType)
		registry.WriteErrorResponse(w, http.StatusUnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE", "unsupported manifest media type")
		return
	}

	// 3. 读取请求体
	body, err := io.ReadAll(r.Body)
	if err != nil {
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to read request body")
		return
	}
	if len(body) == 0 {
		registry.WriteErrorResponse(w, http.StatusBadRequest, "MANIFEST_INVALID", "empty manifest")
		return
	}

	// 4. 验证 Manifest 依赖的所有 Blob 是否都存在
	var digestsToCheck []string
	switch contentType {
	case "application/vnd.docker.distribution.manifest.v2+json":
		var manifest registry.Manifest
		if err := json.Unmarshal(body, &manifest); err != nil {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "MANIFEST_INVALID", "failed to parse manifest")
			return
		}
		digestsToCheck = append(digestsToCheck, manifest.Config.Digest)
		for _, layer := range manifest.Layers {
			digestsToCheck = append(digestsToCheck, layer.Digest)
		}
	case "application/vnd.docker.distribution.manifest.list.v2+json":
		var manifestList registry.ManifestList
		if err := json.Unmarshal(body, &manifestList); err != nil {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "MANIFEST_INVALID", "failed to parse manifest list")
			return
		}
		for _, manifestDesc := range manifestList.Manifests {
			digestsToCheck = append(digestsToCheck, manifestDesc.Digest)
		}
	}

	for _, digest := range digestsToCheck {
		if _, err := h.Storage.StatBlob(digest); err != nil {
			if errors.Is(err, registry.ErrBlobNotFound) {
				registry.WriteErrorResponse(w, http.StatusBadRequest, "MANIFEST_BLOB_UNKNOWN", fmt.Sprintf("blob unknown to registry: %s", digest))
				return
			}
			registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check blob existence")
			return
		}
	}

	// 5. 计算并验证 Manifest 的 Digest
	hasher := sha256.New()
	hasher.Write(body)
	calculatedDigest := "sha256:" + hex.EncodeToString(hasher.Sum(nil))

	// 如果 reference 本身是一个 digest，它必须与计算出的 digest 匹配
	if strings.HasPrefix(reference, "sha256:") && reference != calculatedDigest {
		registry.WriteErrorResponse(w, http.StatusBadRequest, "DIGEST_INVALID", "provided digest did not match calculated digest")
		return
	}

	// 6. 调用存储层，持久化 Manifest
	digest, err := h.Storage.PutManifest(repoName, reference, contentType, body)
	if err != nil {
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to save manifest")
		return
	}

	// 7. 返回成功的响应
	// Location header 应该指向 manifest 的不可变 URL (通过 digest)
	locationURL := fmt.Sprintf("/v2/%s/manifests/%s", repoName, digest)
	absoluteURL := buildAbsoluteURL(r, locationURL)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Content-Digest", digest)
	w.WriteHeader(http.StatusCreated)
}

// handleManifestDelete 负责处理 DELETE /v2/{name}/manifests/{reference} 请求。
// 在我们的简化实现中，我们只支持删除 tag，而不是删除 digest。
// 删除 digest 属于垃圾回收(GC)的范畴，更为复杂。
func (h *Handler) handleManifestDelete(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	repoName := vars["name"]
	reference := vars["reference"]

	// 规范要求通过 digest 来删除 manifest，但实际使用中删除 tag 更常见。
	// 我们在这里做一个简化：如果 reference 是 digest，我们返回未实现。
	if strings.HasPrefix(reference, "sha256:") {
		// 删除 manifest blob 是一个复杂操作，通常由 GC 完成
		registry.WriteErrorResponse(w, http.StatusMethodNotAllowed, "UNSUPPORTED", "deleting manifest by digest is not supported")
		return
	}

	// reference 是一个 tag
	err := h.Storage.DeleteTag(repoName, reference)
	if err != nil {
		if errors.Is(err, registry.ErrTagNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "TAG_UNKNOWN", "tag not known")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete tag")
		return
	}

	// 成功删除，根据规范返回 202 Accepted
	w.WriteHeader(http.StatusAccepted)
}
