package main

import(
	"fmt"
	// "os"
	"strings"
	"github.com/gorilla/mux"
	"net/http"
)


func testSaveToFile() {
    // 示例：将字符串保存到文件
    content := "Hello, Save to File!"
    reader := strings.NewReader(content)
    err := SaveReaderToFile(reader, "../output/test.txt")
    if err != nil {
        fmt.Println("保存失败:", err)
    } else {
        fmt.Println("保存成功！")
    }
}

func testDigestWriter() {
	dw, err := NewDigestWriter("../output/blob.data")
    if err != nil {
        fmt.Println("创建失败:", err)
        return
    }
    defer dw.Close()

    data := []byte("Hello, DigestWriter!")
    _, err = dw.Write(data)
    if err != nil {
        fmt.Println("写入失败:", err)
        return
    }

    fmt.Printf("SHA256 摘要: %x\n", dw.Digest())
}

func BlobsHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    repoName := vars["repoName"]
    fmt.Fprintf(w, "repoName: %s\n", repoName)
}

func BlobsRouter(){
	r := mux.NewRouter()
    r.HandleFunc("/api/repos/{repoName}/blobs", BlobsHandler).Methods("GET", "POST")
    http.Handle("/", r)
    fmt.Println("服务器启动: http://localhost:8080")
    http.ListenAndServe(":8080", nil)
}

func main() {
	// testSaveToFile()
	// testDigestWriter()
	// BlobsRouter()
	manifestHandler()
}