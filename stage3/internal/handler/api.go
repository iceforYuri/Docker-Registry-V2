// file: internal/handler/api.go
package handler

import (
	"github.com/gorilla/mux"

	"docker-registry-lite/internal/storage"
)

// RegisterRoutes 将所有 Docker Registry API 的路由注册到给定的 mux.Router 上。
func RegisterRoutes(r *mux.Router, storageDriver *storage.FileSystemStorage) {
	h := NewHandler(storageDriver)

	// --- 1. Base API ---
	r.HandleFunc("/v2/", h.handleBase).Methods("GET")

	// --- 2. Manifests API ---
	r.HandleFunc("/v2/{name:.+}/manifests/{reference}", h.handleManifestGet).Methods("GET")
	r.HandleFunc("/v2/{name:.+}/manifests/{reference}", h.handleManifestHead).Methods("HEAD")
	r.HandleFunc("/v2/{name:.+}/manifests/{reference}", h.handleManifestPut).Methods("PUT")
	r.HandleFunc("/v2/{name:.+}/manifests/{reference}", h.handleManifestDelete).Methods("DELETE")

	// --- 3. Blobs API ---
	r.HandleFunc("/v2/{name:.+}/blobs/{digest}", h.handleBlobGet).Methods("GET")
	r.HandleFunc("/v2/{name:.+}/blobs/{digest}", h.handleBlobHead).Methods("HEAD")

	// --- 4. Blob Uploads API (分片上传) ---
	r.HandleFunc("/v2/{name:.+}/blobs/uploads/", h.handleBlobUploadStart).Methods("POST")
	r.HandleFunc("/v2/{name:.+}/blobs/uploads/{uuid}", h.handleBlobUploadStatus).Methods("GET")
	r.HandleFunc("/v2/{name:.+}/blobs/uploads/{uuid}", h.handleBlobUploadChunk).Methods("PATCH")
	r.HandleFunc("/v2/{name:.+}/blobs/uploads/{uuid}", h.handleBlobUploadCommit).Methods("PUT")
	r.HandleFunc("/v2/{name:.+}/blobs/uploads/{uuid}", h.handleBlobUploadCancel).Methods("DELETE")
}
