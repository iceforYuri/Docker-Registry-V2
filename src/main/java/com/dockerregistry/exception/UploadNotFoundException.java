package com.dockerregistry.exception;

/**
 * 上传会话不存在异常
 */
public class UploadNotFoundException extends RegistryException {
    public UploadNotFoundException(String uploadId) {
        super("Upload session not found: " + uploadId);
    }
}