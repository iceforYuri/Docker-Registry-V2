package main

import (
    "fmt"
    "io/ioutil"
    "net/http"
)

func main() {
    // 请求所有书籍（ids参数可自定义，如 ids=1,2）
    resp, err := http.Get("http://localhost:8080/books?ids=1,2")
    if err != nil {
        fmt.Println("请求失败:", err)
        return
    }
    defer resp.Body.Close()

    body, err := ioutil.ReadAll(resp.Body)
    if err != nil {
        fmt.Println("读取响应失败:", err)
        return
    }

    fmt.Println("响应内容：")
    fmt.Println(string(body))
}