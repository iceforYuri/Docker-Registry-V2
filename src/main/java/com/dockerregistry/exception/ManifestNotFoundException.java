package com.dockerregistry.exception;

/**
 * Manifest 不存在异常
 */
public class ManifestNotFoundException extends RegistryException {
    public ManifestNotFoundException(String repository, String reference) {
        super("Manifest not found: " + repository + ":" + reference);
    }
}