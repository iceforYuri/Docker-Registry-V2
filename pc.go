package main

import (
    "fmt"
    "time"
)

func producer(tasks chan<- int, count int) {
    for i := 1; i <= count; i++ {
        fmt.Printf("生产者生产任务: %d\n", i)
        tasks <- i
        time.Sleep(100 * time.Millisecond)
    }
    close(tasks) // 生产结束，关闭通道
}

func consumer(id int, tasks <-chan int, done chan<- bool) {
    for task := range tasks {
        fmt.Printf("消费者%d处理任务: %d\n", id, task)
        time.Sleep(200 * time.Millisecond)
    }
    done <- true
}

func main() {
    taskChan := make(chan int, 10)
    doneChan := make(chan bool)

    // 启动生产者
    go producer(taskChan, 20)

    // 启动多个消费者
    consumerCount := 3
    for i := 1; i <= consumerCount; i++ {
        go consumer(i, taskChan, doneChan)
    }

    // 等待所有消费者完成
    for i := 0; i < consumerCount; i++ {
        <-doneChan
    }

    fmt.Println("所有任务处理完毕！")
}