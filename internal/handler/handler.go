// file: internal/handler/handler.go
package handler

import (
	"net/http"

	"docker-registry-lite/internal/storage"
)

// Handler 负责持有所有 HTTP 处理函数所需要的依赖，
// 比如存储驱动。这种方式使得我们不必在每个 handler 函数签名中都传递依赖。
type Handler struct {
	Storage *storage.FileSystemStorage
}

// NewHandler 是 Handler 的构造函数。
func NewHandler(storage *storage.FileSystemStorage) *Handler {
	return &Handler{Storage: storage}
}

// handleBase 处理 GET /v2/ 请求 - Docker Registry API 版本检查
func (h *Handler) handleBase(w http.ResponseWriter, r *http.Request) {
	// 设置必要的响应头
	w.Header().Set("Docker-Distribution-Api-Version", "registry/2.0")
	w.WriteHeader(http.StatusOK)
}
