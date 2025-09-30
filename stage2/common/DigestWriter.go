package main

import (
    "crypto/sha256"
    // "io"
	"hash"
    "os"
    "path/filepath"
    // "fmt"
)

// DigestWriter 结构体
type DigestWriter struct {
    file   *os.File
    hasher hash.Hash
}

// 构造函数
func NewDigestWriter(filePath string) (*DigestWriter, error) {
    dir := filepath.Dir(filePath)
    if err := os.MkdirAll(dir, os.ModePerm); err != nil {
        return nil, err
    }
    f, err := os.Create(filePath)
    if err != nil {
        return nil, err
    }
    return &DigestWriter{
        file:   f,
        hasher: sha256.New(),
    }, nil
}

// 实现 io.Writer 接口
func (dw *DigestWriter) Write(p []byte) (int, error) {
    n, err := dw.file.Write(p)
    if err != nil {
        return n, err
    }
    _, err = dw.hasher.Write(p[:n])
    return n, err
}

// 获取 SHA256 摘要
func (dw *DigestWriter) Digest() []byte {
    return dw.hasher.Sum(nil)
}

// 关闭文件
func (dw *DigestWriter) Close() error {
    return dw.file.Close()
}