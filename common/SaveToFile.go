package main

import (
    "io"
    "os"
    "path/filepath"
	
)

// filepath: f:\Code\20250924_DockerRegistry\stage1\bookclient.go
func SaveReaderToFile(r io.Reader, filePath string) error {
    // 确保目录存在
    dir := filepath.Dir(filePath)
    if err := os.MkdirAll(dir, os.ModePerm); err != nil {
        return err
    }
    // 创建文件
    f, err := os.Create(filePath)
    if err != nil {
        return err
    }
    defer f.Close()
    // 写入内容
    _, err = io.Copy(f, r)
    return err
}