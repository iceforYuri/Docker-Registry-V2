package com.dockerregistry.exception;

/**
 * Registry 相关异常的基类
 */
public class RegistryException extends RuntimeException {
    
    public RegistryException(String message) {
        super(message);
    }
    
    public RegistryException(String message, Throwable cause) {
        super(message, cause);
    }
}