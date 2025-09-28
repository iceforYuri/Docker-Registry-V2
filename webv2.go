package main

import (
    "fmt"
    "net/http"
)

func main() {
    http.HandleFunc("/v2/", func(w http.ResponseWriter, r *http.Request) {
        // 示例：只允许 GET 请求，其他方法返回 405
        if r.Method != http.MethodGet {
            errMsg := fmt.Sprintf("不支持的方法: %s", r.Method)
            http.Error(w, errMsg, http.StatusMethodNotAllowed)
            fmt.Println("错误:", errMsg)
            return
        }

        // 正常处理
        w.WriteHeader(http.StatusOK)
        _, err := fmt.Fprintln(w, "200 OK")
        if err != nil {
            http.Error(w, "服务器写入响应失败", http.StatusInternalServerError)
            fmt.Println("写入响应失败:", err)
            return
        }
        fmt.Println("收到请求:", r.Method, r.URL.Path)
    })

    fmt.Println("Web 服务器已启动，监听端口 8090 ...")
    err := http.ListenAndServe(":8090", nil)
    if err != nil {
        fmt.Println("服务器启动失败:", err)
    }
}