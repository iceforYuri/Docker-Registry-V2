package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"

	"github.com/gorilla/mux"

	"docker-registry-lite/internal/handler"
	"docker-registry-lite/internal/middleware"
	"docker-registry-lite/internal/storage"
)

func main() {
	// 允许通过环境变量覆盖监听地址，Linux 默认 :5000
	listenAddr := os.Getenv("REGISTRY_LISTEN")
	if listenAddr == "" {
		listenAddr = ":5000"
	}

	// 优先使用 REGISTRY_STORAGE_ROOT；否则根据 OS 给出合理默认
	storageRoot := os.Getenv("REGISTRY_STORAGE_ROOT")
	if storageRoot == "" {
		if runtime.GOOS == "windows" {
			storageRoot = `F:\docker-registry-data`
		} else {
			// Linux: 优先 XDG_DATA_HOME，其次 ~/.local/share，最后 /var/lib
			dataHome := os.Getenv("XDG_DATA_HOME")
			if dataHome == "" {
				if home, err := os.UserHomeDir(); err == nil {
					dataHome = filepath.Join(home, ".local", "share")
				} else {
					dataHome = "/var/lib"
				}
			}
			storageRoot = filepath.Join(dataHome, "docker-registry")
		}
	}

	log.Printf("Starting Docker Registry Lite...")
	log.Printf("Listening on %s", listenAddr)
	log.Printf("Using storage root: %s", storageRoot)

	// 确保目录存在
	if err := os.MkdirAll(storageRoot, 0755); err != nil {
		log.Fatalf("FATAL: Failed to create storage directory %s: %v. Set REGISTRY_STORAGE_ROOT to a writable path.", storageRoot, err)
	}

	storageDriver, err := storage.NewFileSystemStorage(storageRoot)
	if err != nil {
		log.Fatalf("FATAL: Failed to initialize storage driver: %v", err)
	}

	router := mux.NewRouter()
	handler.RegisterRoutes(router, storageDriver)

	finalHandler := middleware.Recovery(router)

	if err := http.ListenAndServe(listenAddr, finalHandler); err != nil {
		log.Fatalf("FATAL: HTTP server failed to start: %v", err)
	}
}
