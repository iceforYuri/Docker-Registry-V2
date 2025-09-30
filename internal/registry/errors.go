package registry

import (
	"encoding/json"
	"errors"
	"net/http"
)

// ErrorCode 定义了 Registry API 错误代码
type ErrorCode string

const (
	ErrorCodeBlobUnknown         ErrorCode = "BLOB_UNKNOWN"
	ErrorCodeBlobUploadInvalid   ErrorCode = "BLOB_UPLOAD_INVALID"
	ErrorCodeBlobUploadUnknown   ErrorCode = "BLOB_UPLOAD_UNKNOWN"
	ErrorCodeDigestInvalid       ErrorCode = "DIGEST_INVALID"
	ErrorCodeManifestBlobUnknown ErrorCode = "MANIFEST_BLOB_UNKNOWN"
	ErrorCodeManifestInvalid     ErrorCode = "MANIFEST_INVALID"
	ErrorCodeManifestUnknown     ErrorCode = "MANIFEST_UNKNOWN"
	ErrorCodeNameInvalid         ErrorCode = "NAME_INVALID"
	ErrorCodeUnsupported         ErrorCode = "UNSUPPORTED"
	ErrorCodeInternalError       ErrorCode = ""
)

var (
	ErrBlobNotFound     = errors.New("blob not found")
	ErrDigestMismatch   = errors.New("digest mismatch")
	ErrManifestNotFound = errors.New("manifest not found")
	ErrUploadNotFound   = errors.New("upload not found")
	ErrTagNotFound      = errors.New("tag not found")
)

type ErrorResponse struct {
	Errors []ErrorDetail `json:"errors"`
}

type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func WriteErrorResponse(w http.ResponseWriter, status int, code, message string) {
	errResp := ErrorResponse{
		Errors: []ErrorDetail{
			{
				Code:    code,
				Message: message,
			},
		},
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)

	// 在实际项目中，这里的 json.NewEncoder().Encode() 错误也应该被处理
	json.NewEncoder(w).Encode(errResp)
}
