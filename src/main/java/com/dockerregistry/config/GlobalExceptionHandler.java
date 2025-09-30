package com.dockerregistry.config;

import com.dockerregistry.exception.*;
import com.dockerregistry.model.ErrorDetail;
import com.dockerregistry.model.ErrorResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

import java.util.Collections;

/**
 * 全局异常处理器
 * 统一处理 Docker Registry 相关异常
 */
@ControllerAdvice
public class GlobalExceptionHandler {
    
    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);
    
    @ExceptionHandler(BlobNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleBlobNotFound(BlobNotFoundException e) {
        logger.debug("Blob not found: {}", e.getMessage());
        return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UNKNOWN", "blob unknown to registry");
    }
    
    @ExceptionHandler(ManifestNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleManifestNotFound(ManifestNotFoundException e) {
        logger.debug("Manifest not found: {}", e.getMessage());
        return createErrorResponse(HttpStatus.NOT_FOUND, "MANIFEST_UNKNOWN", "manifest unknown");
    }
    
    @ExceptionHandler(UploadNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleUploadNotFound(UploadNotFoundException e) {
        logger.debug("Upload not found: {}", e.getMessage());
        return createErrorResponse(HttpStatus.NOT_FOUND, "BLOB_UPLOAD_UNKNOWN", "blob upload unknown to registry");
    }
    
    @ExceptionHandler(DigestMismatchException.class)
    public ResponseEntity<ErrorResponse> handleDigestMismatch(DigestMismatchException e) {
        logger.warn("Digest mismatch: {}", e.getMessage());
        return createErrorResponse(HttpStatus.BAD_REQUEST, "DIGEST_INVALID", "provided digest did not match calculated digest");
    }
    
    @ExceptionHandler(UnsupportedMediaTypeException.class)
    public ResponseEntity<ErrorResponse> handleUnsupportedMediaType(UnsupportedMediaTypeException e) {
        logger.debug("Unsupported media type: {}", e.getMessage());
        return createErrorResponse(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "UNSUPPORTED_MEDIA_TYPE", e.getMessage());
    }
    
    @ExceptionHandler(RegistryException.class)
    public ResponseEntity<ErrorResponse> handleRegistryException(RegistryException e) {
        logger.error("Registry exception: {}", e.getMessage(), e);
        return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "an internal error occurred");
    }
    
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGenericException(Exception e) {
        logger.error("Unexpected error: {}", e.getMessage(), e);
        return createErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "an internal error occurred");
    }
    
    private ResponseEntity<ErrorResponse> createErrorResponse(HttpStatus status, String code, String message) {
        ErrorDetail error = new ErrorDetail(code, message);
        ErrorResponse errorResponse = new ErrorResponse(Collections.singletonList(error));
        return ResponseEntity.status(status)
                .header("Content-Type", "application/json; charset=utf-8")
                .body(errorResponse);
    }
}