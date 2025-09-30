package com.dockerregistry.controller;

import com.dockerregistry.exception.*;
import com.dockerregistry.model.ErrorDetail;
import com.dockerregistry.model.ErrorResponse;
import com.dockerregistry.service.FileSystemStorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StreamUtils;
import org.springframework.web.bind.annotation.*;

import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.InputStream;
import java.util.Collections;

/**
 * Docker Registry API V2 控制器
 * 处理所有与 Docker Registry 相关的 HTTP 请求
 */
@RestController
@RequestMapping("/v2")
public class RegistryController {
    
    private static final Logger logger = LoggerFactory.getLogger(RegistryController.class);
    
    @Autowired
    private FileSystemStorageService storageService;
    
    /**
     * API 版本检查 - GET /v2/
     */
    @GetMapping("/")
    public ResponseEntity<Void> checkApiVersion() {
        return ResponseEntity.ok()
                .header("Docker-Distribution-Api-Version", "registry/2.0")
                .build();
    }
    
    // --- Blob 操作 ---
    
    /**
     * 检查 Blob 是否存在 - HEAD /v2/{name}/blobs/{digest}
     */
    @RequestMapping(value = "/{name:.+}/blobs/{digest}", method = RequestMethod.HEAD)
    public ResponseEntity<Void> checkBlobExists(
            @PathVariable String name,
            @PathVariable String digest) {
        
        try {
            long size = storageService.statBlob(digest);
            return ResponseEntity.ok()
                    .header("Content-Type", "application/octet-stream")
                    .header("Content-Length", String.valueOf(size))
                    .header("Docker-Content-Digest", digest)
                    .build();
        } catch (BlobNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            logger.error("Error checking blob existence: {}", digest, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
    
    /**
     * 下载 Blob - GET /v2/{name}/blobs/{digest}
     */
    @GetMapping("/{name:.+}/blobs/{digest}")
    public void downloadBlob(
            @PathVariable String name,
            @PathVariable String digest,
            HttpServletResponse response) throws IOException {
        
        try {
            long size = storageService.statBlob(digest);
            InputStream blobStream = storageService.getBlobStream(digest);
            
            response.setContentType("application/octet-stream");
            response.setContentLengthLong(size);
            response.setHeader("Docker-Content-Digest", digest);
            response.setStatus(HttpStatus.OK.value());
            
            StreamUtils.copy(blobStream, response.getOutputStream());
            blobStream.close();
            
        } catch (BlobNotFoundException e) {
            writeErrorResponse(response, HttpStatus.NOT_FOUND, "BLOB_UNKNOWN", "blob unknown to registry");
        } catch (Exception e) {
            logger.error("Error downloading blob: {}", digest, e);
            writeErrorResponse(response, HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to retrieve blob");
        }
    }
    
    // --- Blob Upload 操作 ---
    
    /**
     * 开始 Blob 上传 - POST /v2/{name}/blobs/uploads/
     */
    @PostMapping("/{name:.+}/blobs/uploads/")
    public ResponseEntity<?> startBlobUpload(
            @PathVariable String name,
            @RequestParam(required = false) String mount,
            @RequestParam(required = false) String from) {
        
        try {
            // 检查是否是挂载请求
            if (mount != null && from != null) {
                try {
                    storageService.statBlob(mount);
                    // Blob 已存在，挂载成功
                    String locationUrl = String.format("/v2/%s/blobs/%s", name, mount);
                    return ResponseEntity.status(HttpStatus.CREATED)
                            .header("Location", locationUrl)
                            .header("Docker-Content-Digest", mount)
                            .build();
                } catch (BlobNotFoundException e) {
                    // 挂载失败，继续正常上传流程
                }
            }
            
            // 开始新的上传会话
            String uploadId = storageService.startUpload(name);
            String locationUrl = String.format("/v2/%s/blobs/uploads/%s", name, uploadId);
            
            return ResponseEntity.status(HttpStatus.ACCEPTED)
                    .header("Location", locationUrl)
                    .header("Docker-Upload-UUID", uploadId)
                    .header("Range", "0-0")
                    .build();
                    
        } catch (Exception e) {
            logger.error("Error starting blob upload for repository: {}", name, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to start upload session");
        }
    }
    
    /**
     * 获取上传状态 - GET /v2/{name}/blobs/uploads/{uuid}
     */
    @GetMapping("/{name:.+}/blobs/uploads/{uuid}")
    public ResponseEntity<?> getUploadStatus(
            @PathVariable String name,
            @PathVariable String uuid) {
        
        try {
            long size = storageService.statUpload(name, uuid);
            String locationUrl = String.format("/v2/%s/blobs/uploads/%s", name, uuid);
            
            return ResponseEntity.status(HttpStatus.NO_CONTENT)
                    .header("Location", locationUrl)
                    .header("Docker-Upload-UUID", uuid)
                    .header("Range", String.format("0-%d", size - 1))
                    .build();
                    
        } catch (UploadNotFoundException e) {
            return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry");
        } catch (Exception e) {
            logger.error("Error getting upload status: {}", uuid, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to get upload status");
        }
    }
    
    /**
     * 上传数据块 - PATCH /v2/{name}/blobs/uploads/{uuid}
     */
    @PatchMapping("/{name:.+}/blobs/uploads/{uuid}")
    public ResponseEntity<?> uploadChunk(
            @PathVariable String name,
            @PathVariable String uuid,
            InputStream requestBody) {
        
        try {
            long newSize = storageService.appendChunk(name, uuid, requestBody);
            String locationUrl = String.format("/v2/%s/blobs/uploads/%s", name, uuid);
            
            return ResponseEntity.status(HttpStatus.ACCEPTED)
                    .header("Location", locationUrl)
                    .header("Docker-Upload-UUID", uuid)
                    .header("Range", String.format("0-%d", newSize - 1))
                    .build();
                    
        } catch (UploadNotFoundException e) {
            return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry");
        } catch (Exception e) {
            logger.error("Error uploading chunk to: {}", uuid, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to append chunk");
        }
    }
    
    /**
     * 完成上传 - PUT /v2/{name}/blobs/uploads/{uuid}
     */
    @PutMapping("/{name:.+}/blobs/uploads/{uuid}")
    public ResponseEntity<?> completeUpload(
            @PathVariable String name,
            @PathVariable String uuid,
            @RequestParam String digest,
            InputStream requestBody) {
        
        try {
            // 如果有最后的数据块，先添加
            if (requestBody.available() > 0) {
                storageService.appendChunk(name, uuid, requestBody);
            }
            
            // 提交上传
            storageService.commitUpload(name, uuid, digest);
            
            String locationUrl = String.format("/v2/%s/blobs/%s", name, digest);
            return ResponseEntity.status(HttpStatus.CREATED)
                    .header("Location", locationUrl)
                    .header("Docker-Content-Digest", digest)
                    .build();
                    
        } catch (UploadNotFoundException e) {
            return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry");
        } catch (DigestMismatchException e) {
            return createErrorResponse(HttpStatus.BAD_REQUEST, "DIGEST_INVALID", "provided digest did not match calculated digest");
        } catch (Exception e) {
            logger.error("Error completing upload: {}", uuid, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to commit upload");
        }
    }
    
    /**
     * 取消上传 - DELETE /v2/{name}/blobs/uploads/{uuid}
     */
    @DeleteMapping("/{name:.+}/blobs/uploads/{uuid}")
    public ResponseEntity<?> cancelUpload(
            @PathVariable String name,
            @PathVariable String uuid) {
        
        try {
            storageService.cancelUpload(name, uuid);
            return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
        } catch (UploadNotFoundException e) {
            return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry");
        } catch (Exception e) {
            logger.error("Error cancelling upload: {}", uuid, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to cancel upload");
        }
    }
    
    // --- Manifest 操作 ---
    
    /**
     * 检查 Manifest 是否存在 - HEAD /v2/{name}/manifests/{reference}
     */
    @RequestMapping(value = "/{name:.+}/manifests/{reference}", method = RequestMethod.HEAD)
    public ResponseEntity<Void> checkManifestExists(
            @PathVariable String name,
            @PathVariable String reference) {
        
        try {
            FileSystemStorageService.ManifestData manifestData = storageService.getManifest(name, reference);
            return ResponseEntity.ok()
                    .header("Content-Type", manifestData.getContentType())
                    .header("Content-Length", String.valueOf(manifestData.getContent().length))
                    .header("Docker-Content-Digest", manifestData.getDigest())
                    .build();
        } catch (ManifestNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            logger.error("Error checking manifest existence: {} for repository: {}", reference, name, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
    
    /**
     * 获取 Manifest - GET /v2/{name}/manifests/{reference}
     */
    @GetMapping("/{name:.+}/manifests/{reference}")
    public ResponseEntity<?> getManifest(
            @PathVariable String name,
            @PathVariable String reference) {
        
        try {
            FileSystemStorageService.ManifestData manifestData = storageService.getManifest(name, reference);
            
            return ResponseEntity.ok()
                    .header("Content-Type", manifestData.getContentType())
                    .header("Content-Length", String.valueOf(manifestData.getContent().length))
                    .header("Docker-Content-Digest", manifestData.getDigest())
                    .body(manifestData.getContent());
                    
        } catch (ManifestNotFoundException e) {
            return createErrorResponse(HttpStatus.NOT_FOUND, "MANIFEST_UNKNOWN", "manifest unknown");
        } catch (Exception e) {
            logger.error("Error getting manifest: {} for repository: {}", reference, name, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "an internal error occurred");
        }
    }
    
    /**
     * 上传 Manifest - PUT /v2/{name}/manifests/{reference}
     */
    @PutMapping("/{name:.+}/manifests/{reference}")
    public ResponseEntity<?> putManifest(
            @PathVariable String name,
            @PathVariable String reference,
            @RequestHeader("Content-Type") String contentType,
            @RequestBody byte[] requestBody) {
        
        try {
            // 验证 Content-Type
            if (!isValidManifestContentType(contentType)) {
                return createErrorResponse(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "UNSUPPORTED_MEDIA_TYPE", 
                        "unsupported manifest media type");
            }
            
            if (requestBody.length == 0) {
                return createErrorResponse(HttpStatus.BAD_REQUEST, "MANIFEST_INVALID", "empty manifest");
            }
            
            // 验证 Manifest 依赖的所有 Blob 是否都存在
            try {
                storageService.validateManifestBlobs(contentType, requestBody);
            } catch (BlobNotFoundException e) {
                return createErrorResponse(HttpStatus.BAD_REQUEST, "MANIFEST_BLOB_UNKNOWN", 
                        "blob unknown to registry: " + e.getMessage());
            }
            
            // 如果reference是digest，需要验证digest匹配
            if (reference.startsWith("sha256:")) {
                String calculatedDigest = calculateDigest(requestBody);
                if (!reference.equals(calculatedDigest)) {
                    return createErrorResponse(HttpStatus.BAD_REQUEST, "DIGEST_INVALID", 
                            "provided digest did not match calculated digest");
                }
            }
            
            // 存储 Manifest
            String digest = storageService.putManifest(name, reference, contentType, requestBody);
            
            String locationUrl = String.format("/v2/%s/manifests/%s", name, digest);
            return ResponseEntity.status(HttpStatus.CREATED)
                    .header("Location", locationUrl)
                    .header("Docker-Content-Digest", digest)
                    .build();
                    
        } catch (UnsupportedMediaTypeException e) {
            return createErrorResponse(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "UNSUPPORTED_MEDIA_TYPE", e.getMessage());
        } catch (Exception e) {
            logger.error("Error putting manifest: {} for repository: {}", reference, name, e);
            return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "failed to save manifest");
        }
    }
    
    /**
     * 验证 Manifest Content-Type 是否有效
     */
    private boolean isValidManifestContentType(String contentType) {
        return contentType != null && (
                contentType.equals("application/vnd.docker.distribution.manifest.v2+json") ||
                contentType.equals("application/vnd.docker.distribution.manifest.list.v2+json") ||
                contentType.equals("application/vnd.oci.image.manifest.v1+json") ||
                contentType.equals("application/vnd.oci.image.index.v1+json")
        );
    }
    
    /**
     * 计算字节数组的 SHA256 digest
     */
    private String calculateDigest(byte[] content) {
        try {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(content);
            
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) {
                    hexString.append('0');
                }
                hexString.append(hex);
            }
            return "sha256:" + hexString.toString();
        } catch (java.security.NoSuchAlgorithmException e) {
            logger.error("SHA-256 algorithm not available", e);
            throw new RuntimeException("SHA-256 algorithm not available", e);
        }
    }
    
    // --- 错误响应辅助方法 ---
    
    private ResponseEntity<ErrorResponse> createErrorResponse(HttpStatus status, String code, String message) {
        ErrorDetail error = new ErrorDetail(code, message);
        ErrorResponse errorResponse = new ErrorResponse(Collections.singletonList(error));
        return ResponseEntity.status(status)
                .header("Content-Type", "application/json; charset=utf-8")
                .body(errorResponse);
    }
    
    private void writeErrorResponse(HttpServletResponse response, HttpStatus status, String code, String message) throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/json; charset=utf-8");
        
        // 直接序列化 JSON 响应
        String json = String.format("{\"errors\":[{\"code\":\"%s\",\"message\":\"%s\"}]}", code, message);
        response.getWriter().write(json);
    }
}