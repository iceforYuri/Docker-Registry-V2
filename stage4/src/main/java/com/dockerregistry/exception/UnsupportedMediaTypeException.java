package com.dockerregistry.exception;

/**
 * 不支持的媒体类型异常
 */
public class UnsupportedMediaTypeException extends RegistryException {
    public UnsupportedMediaTypeException(String mediaType) {
        super("Unsupported media type: " + mediaType);
    }
}