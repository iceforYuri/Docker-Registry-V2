package main

import ("fmt"
	"os"
	// "io/ioutil"
)

var FILE_PATH = "src/data/"

// 定义镜像结构体
type Image struct {
    Name    string
    Version string
    SizeMB  int
}

type Storage interface{
	SaveBlob(name string,data []byte) (string, error)
	GetBlob(name string) ([]byte, error)
}

type FileStorage struct {
	Dir string
}

func (fs *FileStorage) SaveBlob(name string, data []byte) (string, error) {
	// 实现保存数据到文件的逻辑
	path := fs.Dir + "/" + name
	err := os.WriteFile(path, data, 0644)
	if err != nil {
		return "", err
	}
	return path, nil
}

func (fs *FileStorage) GetBlob(name string) ([]byte, error) {
	// 实现从文件读取数据的逻辑
	path := fs.Dir + "/" + name
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return data, nil
}


func main() {
    // 用 map 存储多个镜像对象
    images := make(map[string]Image)

    // 添加镜像
    images["nginx"] = Image{Name: "nginx", Version: "1.21.1", SizeMB: 25}
    images["redis"] = Image{Name: "redis", Version: "6.2.6", SizeMB: 10}
    images["mysql"] = Image{Name: "mysql", Version: "8.0.26", SizeMB: 200}

    // 遍历并打印所有镜像
    for _, img := range images {
        fmt.Printf("镜像名: %s, 版本: %s, 大小: %dMB\n", img.Name, img.Version, img.SizeMB)
    }

	// 创建文件存储实例
	fs := &FileStorage{Dir: FILE_PATH}

	// 保存一个 blob
	message, err := fs.SaveBlob("example.txt", []byte("Hello, Docker Registry!"))
	if err != nil {
		fmt.Println("Error saving blob:", err)
	} else {
		fmt.Println("Blob saved at:", message)
	}

	// 读取一个 blob
	data, err := fs.GetBlob("example.txt")
	if err != nil {
		fmt.Println("Error getting blob:", err)
	} else {
		fmt.Println("Blob data:", string(data))
	}
}