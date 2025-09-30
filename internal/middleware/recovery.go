// file: internal/middleware/recovery.go
package middleware

import (
	"encoding/json"
	"log"
	"net/http"
	// "runtime/debug"
)

// ErrorResponse 定义了 API 错误响应的结构。
// (这个结构可以与 handler 包中的共享，放在一个公共的地方)
type ErrorResponse struct {
	Errors []ErrorDetail `json:"errors"`
}

// ErrorDetail 包含了错误的具体代码和消息。
type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Recovery 是一个 HTTP 中间件，用于从 handler 中的 panic 中恢复。
// 接收一个 http.Handler (例如我们的 mux.Router)，并返回一个新的 http.Handler。
func Recovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		defer func() {
			// 只有在延迟函数内部直接调用时，重新获得对一个 panic 的 goroutine 的控制
			if err := recover(); err != nil {
				// 如果 err 不是 nil，说明一个 panic 发生了。
				log.Printf("!!! PANIC RECOVERED !!!")
				log.Printf("Error: %v", err)

				// 向客户端返回一个标准的 500 错误，而不是让连接断开。
				w.Header().Set("Content-Type", "application/json; charset=utf-8")
				w.WriteHeader(http.StatusInternalServerError)

				// 构造并发送标准的错误 JSON 体
				errResp := ErrorResponse{
					Errors: []ErrorDetail{
						{
							Code:    "INTERNAL_ERROR",
							Message: "an internal server error occurred",
						},
					},
				}
				json.NewEncoder(w).Encode(errResp)
			}
		}()

		// 如果没有 panic，这行代码会正常执行，将请求传递给下一个 handler (我们的路由器)。
		// 如果下游的 handler (例如 handleBlobGet) 发生了 panic，
		// 执行会立即跳转到上面 defer 的函数中。
		next.ServeHTTP(w, r)
	})
}
