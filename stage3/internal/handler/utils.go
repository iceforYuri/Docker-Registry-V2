// file: internal/handler/utils.go
package handler

import (
	"fmt"
	"net/http"
)

// buildAbsoluteURL 根据传入的请求动态构建一个完整的绝对 URL。
func buildAbsoluteURL(r *http.Request, path string) string {
	scheme := "http"
	// 检查请求是否通过 TLS (HTTPS)
	if r.TLS != nil {
		scheme = "https"
	}
	// r.Host 会包含主机名和端口，例如 "host.docker.internal:5000"
	return fmt.Sprintf("%s://%s%s", scheme, r.Host, path)
}
