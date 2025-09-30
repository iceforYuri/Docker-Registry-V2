package main

import "fmt"

func add(a int, b int) int {
	return a + b
}

func addgo() {
	var result = add(3, 5)

	fmt.Println("3 + 5 =", result)
}

func main() {
	addgo()
	a := "Runboob"
	fmt.Println(a)
}