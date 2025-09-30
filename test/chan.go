package main

import (
    "fmt"
)

func main() {
    ch := make(chan string, 10)

    go func() {
        var input string
        for {
            fmt.Print("请输入内容（#结束）：")
            fmt.Scanln(&input)
            if input == "#" {
                close(ch)
                break
            }
            ch <- input
        }
    }()

    for v := range ch {
        fmt.Println("收到：", v)
    }
}