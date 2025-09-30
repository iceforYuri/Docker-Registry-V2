package com.dockerregistry.exception;

/**
 * Digest 不匹配异常
 */
public class DigestMismatchException extends RegistryException {
    public DigestMismatchException(String expected, String actual) {
        super("Digest mismatch. Expected: " + expected + ", Actual: " + actual);
    }
}