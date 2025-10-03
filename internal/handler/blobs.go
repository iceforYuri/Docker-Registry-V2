// file: internal/handler/blobs.go
package handler

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"docker-registry-lite/internal/registry"

	"github.com/gorilla/mux"
)

// handleBlobGet 负责处理 GET /v2/{name}/blobs/{digest} 请求，下载一个 blob。
func (h *Handler) handleBlobGet(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量
	vars := mux.Vars(r)
	// repoName := vars["name"] // 'name' 在这里仅用于路由匹配，下载 blob 不需要
	digest := vars["digest"]

	// 2. 调用存储层获取 blob 的可读流
	blobReader, err := h.Storage.GetBlob(digest)
	if err != nil {
		if errors.Is(err, registry.ErrBlobNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UNKNOWN", "blob unknown to registry")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve blob")
		return
	}
	// 确保在函数结束时关闭文件句柄
	defer blobReader.Close()

	// 3. 为了设置 Content-Length，需要先获取 blob 的大小
	size, err := h.Storage.StatBlob(digest)
	if err != nil {
		// 理论上，如果 GetBlob 成功，StatBlob 不应该失败，但作为健壮性检查
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to stat blob after opening")
		return
	}

	// 4. 设置成功的响应头
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
	w.Header().Set("Docker-Content-Digest", digest)
	w.WriteHeader(http.StatusOK)

	// 5. 将 blob 内容流式传输到响应体
	// io.Copy 是最高效的方式，它避免将整个 blob 读入内存
	io.Copy(w, blobReader)
}

// handleBlobHead 负责处理 HEAD /v2/{name}/blobs/{digest} 请求，检查 blob 是否存在。
func (h *Handler) handleBlobHead(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	digest := vars["digest"]

	// 1. 调用存储层检查 blob 状态
	size, err := h.Storage.StatBlob(digest)
	if err != nil {
		if errors.Is(err, registry.ErrBlobNotFound) {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	// 2. 设置成功的响应头
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
	w.Header().Set("Docker-Content-Digest", digest)
	w.WriteHeader(http.StatusOK)
	// 对于 HEAD 请求，不写入响应体
}

// handleBlobUploadStart 负责处理 POST /v2/{name}/blobs/uploads/ 请求。
// 这个函数有两种主要逻辑：
// 1. 如果提供了 `mount` 和 `from` 查询参数，尝试跨仓库挂载 blob。
// 2. 否则，开始一个新的分片上传会话。
func (h *Handler) handleBlobUploadStart(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量和查询参数
	vars := mux.Vars(r)
	repoName := vars["name"]

	mountDigest := r.URL.Query().Get("mount")
	fromRepo := r.URL.Query().Get("from")

	// --- 逻辑 1: 尝试挂载 Blob ---
	if mountDigest != "" && fromRepo != "" {
		// 客户端尝试进行跨仓库挂载。
		// 在内容寻址存储中，这简化为检查 blob 是否已存在。
		_, err := h.Storage.StatBlob(mountDigest)
		if err == nil {

			// 验证用户是否有权限从 fromRepo 挂载到 repoName
			// if !h.canMountBetweenRepos(fromRepo, repoName, userContext) {
			//     registry.WriteErrorResponse(w, http.StatusForbidden, "DENIED", "insufficient permission to mount")
			//     return
			// }
			// 简化实现：总是允许

			// Blob 已存在，挂载成功！
			// 根据规范，返回 201 Created。
			// Location header 指向 blob 的最终位置。
			locationURL := fmt.Sprintf("/v2/%s/blobs/%s", repoName, mountDigest)
			absoluteURL := buildAbsoluteURL(r, locationURL)
			w.Header().Set("Location", absoluteURL)
			w.Header().Set("Docker-Content-Digest", mountDigest)
			w.WriteHeader(http.StatusCreated)
			return // 请求处理完毕
		}
		// 如果 StatBlob 出错 (例如 ErrBlobNotFound)，说明挂载失败。
		// 我们不需要在这里返回错误，而是优雅地回退到标准的上传流程。
	}

	// --- 逻辑 2: 开始新的上传 ---
	// 如果代码执行到这里，意味着：
	// a) 客户端没有请求挂载。
	// b) 客户端请求挂载，但 blob 不存在，挂载失败。
	uploadID, err := h.Storage.StartUpload(repoName)
	if err != nil {
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to start upload session")
		return
	}

	// 成功开始上传，根据规范返回 202 Accepted。
	// Location header 指向这个新的上传会话。
	locationURL := fmt.Sprintf("/v2/%s/blobs/uploads/%s", repoName, uploadID)
	absoluteURL := buildAbsoluteURL(r, locationURL)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Upload-UUID", uploadID)
	// Range header 表示目前已接收 0 字节。
	w.Header().Set("Range", "0-0")
	w.WriteHeader(http.StatusAccepted)
}

func (h *Handler) handleBlobUploadStatus(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量
	vars := mux.Vars(r)
	repoName := vars["name"]
	uploadID := vars["uuid"]

	// 2. 调用存储层获取上传状态
	size, err := h.Storage.StatUpload(repoName, uploadID)
	if err != nil {
		if errors.Is(err, registry.ErrUploadNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get upload status")
		return
	}

	// 3. 设置成功的响应头
	// Location 应该是上传会话本身的 URL
	locationURL := fmt.Sprintf("/v2/%s/blobs/uploads/%s", repoName, uploadID)
	absoluteURL := buildAbsoluteURL(r, locationURL)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Upload-UUID", uploadID)

	// Range header 表示已接收的字节范围，从 0 到 size-1
	// 如果 size 为 0，Range header 将是 "0--1"，这是一个有效的但可能不常见的表示法
	// 客户端应该能够从中计算出已接收的字节数为 0
	w.Header().Set("Range", fmt.Sprintf("0-%d", size-1))

	// 4. 返回 204 No Content 状态码
	// 这个状态码表示请求成功，但响应中没有 body 内容。
	// 所有客户端需要的信息都在头信息里。
	w.WriteHeader(http.StatusNoContent)
}

// handleBlobUploadChunk 负责处理 PATCH /v2/{name}/blobs/uploads/{uuid} 请求。
// 它接收一个数据块并将其追加到上传会话中。
func (h *Handler) handleBlobUploadChunk(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量
	vars := mux.Vars(r)
	repoName := vars["name"]
	uploadID := vars["uuid"]

	// 2. 验证 Content-Type
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/octet-stream" {
		// 有些客户端可能不发送这个头，所以我们只记录日志而不是直接拒绝
		log.Printf("Warning: received PATCH request with non-standard Content-Type: %s", contentType)
	}

	// 3. 调用存储层追加数据块
	// r.Body 本身就是一个 io.Reader，可以直接流式传递，非常高效
	newSize, err := h.Storage.AppendChunk(repoName, uploadID, r.Body)
	if err != nil {
		if errors.Is(err, registry.ErrUploadNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to append chunk")
		return
	}

	// 4. 设置成功的响应头
	locationURL := fmt.Sprintf("/v2/%s/blobs/uploads/%s", repoName, uploadID)
	absoluteURL := buildAbsoluteURL(r, locationURL)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Upload-UUID", uploadID)
	w.Header().Set("Range", fmt.Sprintf("0-%d", newSize-1))

	// 5. 返回 202 Accepted
	w.WriteHeader(http.StatusAccepted)
}

// handleBlobUploadCommit 负责处理 PUT /v2/{name}/blobs/uploads/{uuid} 请求。
// 它完成一个上传，对其进行校验，并将其移动到最终位置。
func (h *Handler) handleBlobUploadCommit(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量和查询参数
	vars := mux.Vars(r)
	repoName := vars["name"]
	uploadID := vars["uuid"]

	digest := r.URL.Query().Get("digest")
	if digest == "" {
		registry.WriteErrorResponse(w, http.StatusBadRequest, "DIGEST_INVALID", "digest parameter is required")
		return
	}

	// 2. 处理可选的请求体
	// 规范允许 PUT 请求包含最后一个数据块。
	// Content-Length = -1 表示 chunked encoding，我们仍然需要读取 body

	// 即使 Content-Length 是 -1，也要尝试读取 body
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("[ERROR] handleBlobUploadCommit: failed to read request body: %v", err)
		registry.WriteErrorResponse(w, http.StatusBadRequest, "BLOB_UPLOAD_INVALID", "failed to read request body")
		return
	}

	if len(body) > 0 {
		// 将字节数组转换为 io.Reader
		bodyReader := io.NopCloser(strings.NewReader(string(body)))

		if _, err := h.Storage.AppendChunk(repoName, uploadID, bodyReader); err != nil {
			if errors.Is(err, registry.ErrUploadNotFound) {
				registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
				return
			}
			registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to append body data")
			return
		}
	}

	// 3. 调用存储层提交上传
	err = h.Storage.CommitUpload(repoName, uploadID, digest)
	if err != nil {
		log.Printf("[ERROR] CommitUpload failed: %v", err)
		if errors.Is(err, registry.ErrUploadNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
			return
		}
		if errors.Is(err, registry.ErrDigestMismatch) {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "DIGEST_INVALID", "provided digest did not match calculated digest")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to commit upload")
		return
	}

	// 4. 设置成功的响应头
	// Location 指向的是 blob 的最终、不可变的位置
	locationURL := fmt.Sprintf("/v2/%s/blobs/%s", repoName, digest)
	absoluteURL := buildAbsoluteURL(r, locationURL)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Content-Digest", digest)

	// 5. 返回 201 Created
	w.WriteHeader(http.StatusCreated)
}

// handleBlobUploadCancel 负责处理 DELETE /v2/{name}/blobs/uploads/{uuid} 请求。
// 它会取消一个进行中的上传并清理临时文件。
func (h *Handler) handleBlobUploadCancel(w http.ResponseWriter, r *http.Request) {
	// 1. 从 URL 提取变量
	vars := mux.Vars(r)
	repoName := vars["name"]
	uploadID := vars["uuid"]

	// 2. 调用存储层取消上传
	err := h.Storage.CancelUpload(repoName, uploadID)
	if err != nil {
		if errors.Is(err, registry.ErrUploadNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to cancel upload")
		return
	}

	// 3. 返回 204 No Content
	w.WriteHeader(http.StatusNoContent)
}
