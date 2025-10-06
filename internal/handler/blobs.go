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

	// --- 逻辑 1: 尝试挂载 Blob (升级版) ---
	if mountDigest != "" && fromRepo != "" {

		if !registry.DigestRegex.MatchString(mountDigest) {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "DIGEST_INVALID", "invalid digest format")
			return
		}
		// 1a. (模拟) 权限检查: 验证源仓库 fromRepo 是否存在。
		//     在一个真实的系统中，这里会进行复杂的认证授权检查。
		exists, err := h.Storage.RepositoryExists(fromRepo)
		if err != nil {
			registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check source repository")
			return
		}
		if !exists {
			// 如果源仓库不存在，挂载失败，回退到标准上传流程。
			goto StartStandardUpload
		}

		// 1b. 内容检查: 检查 blob 是否在全局存储中存在。
		_, err = h.Storage.StatBlob(mountDigest)
		if err == nil {
			// Blob 已存在，挂载成功！

			// 1c. 元数据关联: 在当前仓库中创建 blob 链接。
			if err := h.Storage.LinkBlob(repoName, mountDigest); err != nil {
				registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to link blob to repository")
				return
			}

			// 1d. 返回成功的响应
			relativePath := fmt.Sprintf("/v2/%s/blobs/%s", repoName, mountDigest)
			absoluteURL := buildAbsoluteURL(r, relativePath)
			w.Header().Set("Location", absoluteURL)
			w.Header().Set("Docker-Content-Digest", mountDigest)
			w.WriteHeader(http.StatusCreated)
			return // 挂载流程成功结束
		}
		// 如果 StatBlob 出错 (例如 ErrBlobNotFound)，挂载失败，回退到标准上传流程。
	}

	// --- 逻辑 2: 开始新的上传 (作为默认或回退路径) ---
StartStandardUpload:
	uploadID, err := h.Storage.StartUpload(repoName)
	if err != nil {
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to start upload session")
		return
	}

	// 返回 202 Accepted 响应
	relativePath := fmt.Sprintf("/v2/%s/blobs/uploads/%s", repoName, uploadID)
	absoluteURL := buildAbsoluteURL(r, relativePath)
	w.Header().Set("Location", absoluteURL)
	w.Header().Set("Docker-Upload-UUID", uploadID)
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
	var rangeHeader string
	if size > 0 {
		rangeHeader = fmt.Sprintf("0-%d", size-1)
	} else {
		// 当 size 为 0 时，返回与 POST 响应一致的 "0-0"，表示接收范围为空。
		rangeHeader = "0-0"
	}
	w.Header().Set("Range", rangeHeader)

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

	// 2. 严格的 Content-Range 校验
	// 获取当前上传的大小，作为我们期望的起始偏移量。
	currentSize, err := h.Storage.StatUpload(repoName, uploadID)
	if err != nil {
		if errors.Is(err, registry.ErrUploadNotFound) {
			registry.WriteErrorResponse(w, http.StatusNotFound, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry")
			return
		}
		registry.WriteErrorResponse(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get upload status for validation")
		return
	}

	// 2. 验证 Content-Type
	contentRange := r.Header.Get("Content-Range")
	if contentRange != "" {
		// 如果客户端提供了 Content-Range，我们必须校验它。
		var start, end int64
		// 格式应为 "start-end"
		parts := strings.SplitN(contentRange, "-", 2)
		if len(parts) != 2 {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "INVALID_RANGE", "invalid Content-Range format")
			return
		}
		start, err = strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "INVALID_RANGE", "invalid start of range")
			return
		}
		end, err = strconv.ParseInt(parts[1], 10, 64)
		if err != nil {
			registry.WriteErrorResponse(w, http.StatusBadRequest, "INVALID_RANGE", "invalid end of range")
			return
		}

		// 核心校验：
		// 1. 范围的起始必须等于我们已有的数据大小。
		// 2. 范围的结束必须大于等于起始。
		if start != currentSize || end < start {
			// 如果范围不连续，返回 416 Range Not Satisfiable。
			// 这是向客户端表明其提供的范围不正确的标准方式。
			w.Header().Set("Location", buildAbsoluteURL(r, r.URL.Path))
			w.Header().Set("Range", fmt.Sprintf("0-%d", currentSize-1)) // 告诉客户端我们真正拥有的范围
			w.WriteHeader(http.StatusRequestedRangeNotSatisfiable)
			return
		}
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

	// --- 修正：确保 Range 响应头的一致性和正确性 ---
	var rangeHeader string
	if newSize > 0 {
		rangeHeader = fmt.Sprintf("0-%d", newSize-1)
	} else {
		// 即使 newSize 为 0，也返回一个表示空范围的有效格式。
		// "0-0" 通常表示已接收 1 字节，所以对于 0 字节，返回一个空或特殊的 header 更合适。
		// 客户端应能从 Content-Length: 0 和 Range: 0-0 中推断出接收了 0 字节。
		// 一个更严谨的表达可能是 "0--1"，但 "0-0" 更安全。
		rangeHeader = "0-0"
	}
	w.Header().Set("Range", rangeHeader)
	w.Header().Set("Content-Length", "0") // PATCH 响应体为空

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
