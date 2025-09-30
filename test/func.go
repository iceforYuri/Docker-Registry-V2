package main

import "fmt"

// a := 100
var a int = 100

func main() {
   /* 定义局部变量 */
//    var a int = 100
   var b int = 200
   c := "google"
   var ret int

   /* 调用函数并返回最大值 */
   ret = max(a, b)

   fmt.Printf( "最大值是 : %d\n", ret )

   maxlen, isnum := maxlenth(a, c)
   fmt.Printf("最大长度是 : %d, isnum: %t\n", maxlen, isnum)
}

/* 函数返回两个数的最大值 */
func max(num1, num2 int) int {
   /* 定义局部变量 */
   var result int

   if (num1 > num2) {
      result = num1
   } else {
      result = num2
   }
   return result 
}

func maxlenth(s1 int, s2 string) (int, bool) {
	if(s1 > len(s2)){
		return s1, true
	}
	return len(s2), false
}