package main

import(
	"fmt"
	"os"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"strings"
	// "time"
)

var BOOKS_FILE = "../src/data/books.json"

type Book struct{
	ID int
	Title string
	Author string
}

type BookManager interface{
	AddBook(book Book) error
	GetBookByID(id int) (*Book, error)
}

// 内存管理器

type InMemoryManager struct{
	Books map[int]Book
}

func (bm *InMemoryManager) AddBook(book Book) error {
	if _, exists := bm.Books[book.ID]; exists {
		return fmt.Errorf("Book with ID %d already exists", book.ID)
	}
	bm.Books[book.ID] = book
	return nil
}

func (bm *InMemoryManager) GetBookByID(id int) (*Book, error) {
	if book, exists := bm.Books[id]; exists {
		return &book, nil
	}
	return nil, fmt.Errorf("Book with ID %d not found", id)
}

// 文件管理器

type FileManager struct{
	FilePath string
}

func (fm *FileManager) AddBook(book Book) error {
	// // 通过文件读取现有书籍
	// data, err := ioutil.ReadFile(fm.FilePath)
	// if err != nil{
	// 	return err
	// }
	// var books map[int]Book
	// if len(data) > 0 {
	// 	err = json.Unmarshal(data, &books)
	// 	if err != nil{
	// 		return err
	// 	}
	// } else {
	// 	books = make(map[int]Book)
	// }

	// // 检查书籍是否已存在
	// if _, exists := books[book.ID]; exists {
	// 	return fmt.Errorf("Book with ID %d already exists", book.ID)
	// }

	// // 添加新书籍
	// books[book.ID] = book

	// // 将更新后的书籍写回文件
	// updatedData, err := json.MarshalIndent(books, "", "  ")
	// if err != nil{
	// 	return err
	// }

	// // 将更新后的书籍写回文件
	// err = ioutil.WriteFile(fm.FilePath, updatedData, 0644)
	// if err != nil{
	// 	return err
	// }

	// return nil
	books, err := fm.loadBooks()
	if err != nil{
		return err
	}
	if _, exists := books[book.ID]; exists {
		return fmt.Errorf("Book with ID %d already exists", book.ID)
	}
	books[book.ID] = book
	return fm.saveBooks(books)

}

func (fm *FileManager) GetBookByID(id int) (*Book, error) {
	// // 通过文件读取现有书籍
	// data, err := ioutil.ReadFile(fm.FilePath)
	// if err != nil{
	// 	return nil, err
	// }
	// var books map[int]Book
	// if len(data) > 0 {
	// 	err = json.Unmarshal(data, &books)
	// 	if err != nil{
	// 		return nil, err
	// 	}
	// } else {
	// 	books = make(map[int]Book)
	// }
	// if book, exists := books[id]; exists {
	// 	return &book, nil
	// }
	// return nil, fmt.Errorf("Book with ID %d not found", id)
	books, err := fm.loadBooks()
	if err != nil{
		return nil, err
	}
	if book, exists := books[id]; exists {
		fmt.Printf("响应内容：%v\n", book)
		return &book, nil
	}
	return nil, fmt.Errorf("Book with ID %d not found", id)

}

func (fm *FileManager) saveBooks(books map[int]Book) error {
	data, err := json.MarshalIndent(books, "", "  ")
	if err != nil{
		return err
	}
	return ioutil.WriteFile(fm.FilePath, data, 0644)
}

func (fm* FileManager) loadBooks() (map[int]Book, error) {
	data, err := ioutil.ReadFile(fm.FilePath)
	if err != nil{
		return nil, err
	}
	var books map[int]Book
	if(len(data) > 0){
		err = json.Unmarshal(data, &books)
		if err != nil{
			return nil, err
		}
	} else {
		books = make(map[int]Book)
	}
	return books, nil
}

func testFileManager(){
	// 使用内存管理器
	memManager := &InMemoryManager{Books: make(map[int]Book)}

	err := memManager.AddBook(Book{ID: 1, Title: "1984", Author: "George Orwell"})
	if err != nil {
		fmt.Println("Error adding book to memory manager:", err)
	}
	book, err := memManager.GetBookByID(1)
	if err != nil {
		fmt.Println("Error getting book from memory manager:", err)
	}

	fmt.Println("Memory Manager - Retrieved Book:", book)

	// 使用文件管理器
	// 确保数据目录存在
	os.MkdirAll("src/data", os.ModePerm)
	fileManager := &FileManager{FilePath: BOOKS_FILE}

	err = fileManager.AddBook(Book{ID: 2, Title: "To Kill a Mockingbird", Author: "Harper Lee"})
	if err != nil {
		fmt.Println("Error adding book to file manager:", err)
	}
	book, err = fileManager.GetBookByID(2)
	if err != nil {
		fmt.Println("Error getting book from file manager:", err)
	}
	fmt.Println("File Manager - Retrieved Book:", book)

}

// HTTP Handler: GET /books/{ids}
func BooksHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	fmt.Println("Received request:", r.URL.String())

	// 解析 ids 参数
	idsParam := r.URL.Query().Get("ids")
	if idsParam == "" {
		http.Error(w, "Missing ids parameter", http.StatusBadRequest)
		return
	}
	fmt.Printf("请求参数 ids: %s\n", idsParam)

	// 逐步解析 ids
	var ids []int
	for _, idStr := range strings.Split(idsParam, ",") {
		var id int
		_, err := fmt.Sscanf(idStr, "%d", &id)
		if err == nil {
			ids = append(ids, id)
		}
	}
	fmt.Printf("解析后的 ids: %v\n", ids)

	// 获取书籍信息

	fileManager := &FileManager{FilePath: BOOKS_FILE}
	var books []Book
	for _, id := range ids {
		book, err := fileManager.GetBookByID(id)
		fmt.Printf("获取书籍 ID %d: %v, err: %v\n", id, book, err)
		if err == nil && book != nil {
			books = append(books, *book)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Printf("响应内容：%v\n", books)
	json.NewEncoder(w).Encode(books)
}

func main() {
	// testFileManager()
	http.HandleFunc("/books", BooksHandler)
	fmt.Println("Starting server on :8080")
	http.ListenAndServe(":8080", nil)

}