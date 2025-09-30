package com.dockerregistry.exception;

/**
 * Blob 不存在异常
 */
public class BlobNotFoundException extends RegistryException {
    public BlobNotFoundException(String digest) {
        super("Blob not found: " + digest);
    }
}