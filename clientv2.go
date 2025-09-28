package main

import (
    "fmt"
    "net/http"
    "io/ioutil"
)

func main() {
    resp, err := http.Get("http://localhost:8090/v2/")
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

    fmt.Println("响应状态码:", resp.StatusCode)
    fmt.Println("响应内容:", string(body))

	resp, err = http.Post("http://localhost:8090/v2/", "application/json", nil)
	if err != nil {
		fmt.Println("POST 请求失败:", err)
		return
	}
	defer resp.Body.Close()

	body, err = ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("读取响应失败:", err)
		return
	}

	fmt.Println("响应状态码:", resp.StatusCode)
	fmt.Println("响应内容:", string(body))
}