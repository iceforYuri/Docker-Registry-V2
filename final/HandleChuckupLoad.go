package main

import(
	"fmt"
	"io"
	"os"
	"encoding/json"
	"net/http"
	"crypto/sha256" // 添加这一行
)

func HandleChunkUpload(w http.ResponseWriter, r *http.Request) {
	// 仅允许 POST 方法
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	// 创建临时文件
	tmpFile, err := os.CreateTemp("", "upload-*.tmp")	
	if err != nil {
		http.Error(w, "Failed to create temp file", http.StatusInternalServerError)
		return
	}
	defer os.Remove(tmpFile.Name()) // 处理完成后删除临时文件
	defer tmpFile.Close()

	// 创建 SHA256 摘要计算器
	hasher := sha256.New()

	// 使用 io.TeeReader 同时写入文件和计算摘要，创建临时写入器writer
	writer := io.MultiWriter(tmpFile, hasher)
	_, err = io.Copy(writer, r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusInternalServerError)
		return
	}
	
	// 计算并获取 SHA256 摘要
	digest := hasher.Sum(nil)


	fmt.Printf("SHA256 摘要: %x\n", digest)

	// 返回成功响应和摘要
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Upload successful",
		"digest": fmt.Sprintf("%x", digest),
	})

}

func main() {
	http.HandleFunc("/v2/chunks", HandleChunkUpload)
	fmt.Println("服务器启动: http://localhost:8080")
	http.ListenAndServe(":8080", nil)
}