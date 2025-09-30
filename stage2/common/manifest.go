package main

import (
    "encoding/json"
    "fmt"
    "io/ioutil"
    "regexp"
)

var MANIFEST_FILE = "../src/manifest.json"

// Manifest 结构体示例
type Manifest struct {
    Blobs []struct {
        Digest string `json:"digest"`
    } `json:"blobs"`
}

// 检查 SHA256 格式
func isSHA256Digest(digest string) bool {
    re := regexp.MustCompile(`^sha256:[a-fA-F0-9]{64}$`)
    return re.MatchString(digest)
}

func manifestHandler(){
	// 读取并解析 JSON 文件
    data, err := ioutil.ReadFile(MANIFEST_FILE)
    if err != nil {
        fmt.Println("读取失败:", err)
        return
    }

    var manifest Manifest
    err = json.Unmarshal(data, &manifest)
    if err != nil {
        fmt.Println("解析失败:", err)
        return
    }

    // 检查每个 digest
    for i, blob := range manifest.Blobs {
        if isSHA256Digest(blob.Digest) {
            fmt.Printf("Blob %d digest 合法: %s\n", i, blob.Digest)
        } else {
            fmt.Printf("Blob %d digest 非法: %s\n", i, blob.Digest)
        }
    }
}
