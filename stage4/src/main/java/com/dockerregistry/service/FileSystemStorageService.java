package com.dockerregistry.service;

import com.dockerregistry.exception.*;
import org.apache.commons.io.IOUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.UUID;

/**
 * 基于文件系统的存储服务实现
 * 负责处理 Blob 和 Manifest 的存储操作
 */
@Service
public class FileSystemStorageService {
    
    private static final Logger logger = LoggerFactory.getLogger(FileSystemStorageService.class);
    
    private final String rootDirectory;
    
    public FileSystemStorageService(@Value("${registry.storage.root}") String rootDirectory) {
        this.rootDirectory = rootDirectory;
        initializeStorageDirectories();
    }
    
    /**
     * 初始化存储目录结构
     */
    private void initializeStorageDirectories() {
        try {
            Path root = Paths.get(rootDirectory);
            Files.createDirectories(root);
            Files.createDirectories(getRepositoriesPath());
            Files.createDirectories(getBlobsPath());
            logger.info("Storage directories initialized at: {}", rootDirectory);
        } catch (IOException e) {
            throw new RuntimeException("Failed to initialize storage directories", e);
        }
    }
    
    // --- 路径辅助方法 ---
    
    private Path getRepositoriesPath() {
        return Paths.get(rootDirectory, "v2", "repositories");
    }
    
    private Path getBlobsPath() {
        return Paths.get(rootDirectory, "v2", "blobs");
    }
    
    private Path getBlobPath(String digest) {
        String[] parts = digest.split(":", 2);
        if (parts.length != 2) {
            throw new IllegalArgumentException("Invalid digest format: " + digest);
        }
        String alg = parts[0];
        String hex = parts[1];
        if (hex.length() < 2) {
            throw new IllegalArgumentException("Invalid digest hex: " + hex);
        }
        return Paths.get(rootDirectory, "v2", "blobs", alg, hex.substring(0, 2), hex, "data");
    }
    
    private Path getUploadPath(String repoName, String uploadId) {
        return Paths.get(rootDirectory, "v2", "repositories", repoName, "_uploads", uploadId);
    }
    
    private Path getManifestTagPath(String repoName, String tag) {
        return Paths.get(rootDirectory, "v2", "repositories", repoName, "_manifests", "tags", tag, "current", "link");
    }
    
    // --- Blob 操作 ---
    
    /**
     * 检查 Blob 是否存在并返回其大小
     */
    public long statBlob(String digest) throws BlobNotFoundException {
        Path blobPath = getBlobPath(digest);
        if (!Files.exists(blobPath)) {
            throw new BlobNotFoundException(digest);
        }
        
        try {
            return Files.size(blobPath);
        } catch (IOException e) {
            logger.error("Failed to get blob size for digest: {}", digest, e);
            throw new RuntimeException("Failed to get blob size", e);
        }
    }
    
    /**
     * 获取 Blob 内容的输入流
     */
    public InputStream getBlobStream(String digest) throws BlobNotFoundException {
        Path blobPath = getBlobPath(digest);
        if (!Files.exists(blobPath)) {
            throw new BlobNotFoundException(digest);
        }
        
        try {
            return Files.newInputStream(blobPath);
        } catch (IOException e) {
            logger.error("Failed to open blob stream for digest: {}", digest, e);
            throw new RuntimeException("Failed to open blob stream", e);
        }
    }
    
    // --- 上传操作 ---
    
    /**
     * 开始一个新的 Blob 上传会话
     */
    public String startUpload(String repoName) {
        String uploadId = UUID.randomUUID().toString();
        Path uploadPath = getUploadPath(repoName, uploadId);
        
        try {
            Files.createDirectories(uploadPath.getParent());
            Files.createFile(uploadPath);
            logger.debug("Started upload session: {} for repository: {}", uploadId, repoName);
            return uploadId;
        } catch (IOException e) {
            logger.error("Failed to start upload session for repository: {}", repoName, e);
            throw new RuntimeException("Failed to start upload session", e);
        }
    }
    
    /**
     * 获取上传会话的当前大小
     */
    public long statUpload(String repoName, String uploadId) throws UploadNotFoundException {
        Path uploadPath = getUploadPath(repoName, uploadId);
        if (!Files.exists(uploadPath)) {
            throw new UploadNotFoundException(uploadId);
        }
        
        try {
            return Files.size(uploadPath);
        } catch (IOException e) {
            logger.error("Failed to get upload size for uploadId: {}", uploadId, e);
            throw new RuntimeException("Failed to get upload size", e);
        }
    }
    
    /**
     * 向上传会话追加数据块
     */
    public long appendChunk(String repoName, String uploadId, InputStream dataStream) 
            throws UploadNotFoundException {
        Path uploadPath = getUploadPath(repoName, uploadId);
        if (!Files.exists(uploadPath)) {
            throw new UploadNotFoundException(uploadId);
        }
        
        try (FileOutputStream fos = new FileOutputStream(uploadPath.toFile(), true)) {
            IOUtils.copy(dataStream, fos);
            long newSize = Files.size(uploadPath);
            logger.debug("Appended chunk to upload: {}, new size: {}", uploadId, newSize);
            return newSize;
        } catch (IOException e) {
            logger.error("Failed to append chunk to upload: {}", uploadId, e);
            throw new RuntimeException("Failed to append chunk", e);
        }
    }
    
    /**
     * 提交上传，验证 digest 并移动到最终位置
     */
    public void commitUpload(String repoName, String uploadId, String expectedDigest) 
            throws UploadNotFoundException, DigestMismatchException {
        Path uploadPath = getUploadPath(repoName, uploadId);
        if (!Files.exists(uploadPath)) {
            throw new UploadNotFoundException(uploadId);
        }
        
        try {
            // 计算实际的 digest
            String actualDigest = calculateDigest(uploadPath);
            if (!expectedDigest.equals(actualDigest)) {
                throw new DigestMismatchException(expectedDigest, actualDigest);
            }
            
            // 移动到最终位置
            Path finalPath = getBlobPath(expectedDigest);
            Files.createDirectories(finalPath.getParent());
            Files.move(uploadPath, finalPath, StandardCopyOption.REPLACE_EXISTING);
            
            // 清理上传目录
            cleanupUploadDirectory(uploadPath.getParent());
            
            logger.info("Committed upload: {} as blob: {}", uploadId, expectedDigest);
        } catch (IOException | NoSuchAlgorithmException e) {
            logger.error("Failed to commit upload: {}", uploadId, e);
            throw new RuntimeException("Failed to commit upload", e);
        }
    }
    
    /**
     * 取消上传会话
     */
    public void cancelUpload(String repoName, String uploadId) throws UploadNotFoundException {
        Path uploadPath = getUploadPath(repoName, uploadId);
        if (!Files.exists(uploadPath)) {
            throw new UploadNotFoundException(uploadId);
        }
        
        try {
            Files.deleteIfExists(uploadPath);
            cleanupUploadDirectory(uploadPath.getParent());
            logger.debug("Cancelled upload session: {}", uploadId);
        } catch (IOException e) {
            logger.error("Failed to cancel upload: {}", uploadId, e);
            throw new RuntimeException("Failed to cancel upload", e);
        }
    }
    
    /**
     * 清理空的上传目录
     */
    private void cleanupUploadDirectory(Path uploadDir) {
        try {
            if (Files.exists(uploadDir) && Files.list(uploadDir).findAny().isEmpty()) {
                Files.delete(uploadDir);
            }
        } catch (IOException e) {
            logger.warn("Failed to cleanup upload directory: {}", uploadDir, e);
        }
    }
    
    /**
     * 计算文件的 SHA256 digest
     */
    private String calculateDigest(Path filePath) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream fis = Files.newInputStream(filePath)) {
            byte[] buffer = new byte[8192];
            int bytesRead;
            while ((bytesRead = fis.read(buffer)) != -1) {
                digest.update(buffer, 0, bytesRead);
            }
        }
        
        byte[] hash = digest.digest();
        StringBuilder hexString = new StringBuilder();
        for (byte b : hash) {
            String hex = Integer.toHexString(0xff & b);
            if (hex.length() == 1) {
                hexString.append('0');
            }
            hexString.append(hex);
        }
        return "sha256:" + hexString.toString();
    }
    
    // --- Manifest 操作 ---
    
    /**
     * 获取 Manifest 内容
     */
    public ManifestData getManifest(String repoName, String reference) throws ManifestNotFoundException {
        try {
            Path manifestPath;
            
            // 检查reference是否是digest
            if (reference.startsWith("sha256:")) {
                // 直接通过digest查找
                manifestPath = getBlobPath(reference);
            } else {
                // 通过tag查找
                Path linkPath = getManifestTagPath(repoName, reference);
                if (!Files.exists(linkPath)) {
                    throw new ManifestNotFoundException(repoName, reference);
                }
                
                // 读取link文件获取digest
                String digest = new String(Files.readAllBytes(linkPath)).trim();
                manifestPath = getBlobPath(digest);
            }
            
            if (!Files.exists(manifestPath)) {
                throw new ManifestNotFoundException(repoName, reference);
            }
            
            byte[] content = Files.readAllBytes(manifestPath);
            String digest = calculateDigest(manifestPath);
            
            // 根据内容判断content type
            String contentType = determineManifestContentType(content);
            
            return new ManifestData(content, digest, contentType);
            
        } catch (IOException | NoSuchAlgorithmException e) {
            logger.error("Failed to get manifest: {} for repository: {}", reference, repoName, e);
            throw new ManifestNotFoundException(repoName, reference);
        }
    }
    
    /**
     * 存储 Manifest
     */
    public String putManifest(String repoName, String reference, String contentType, byte[] content) {
        try {
            // 计算digest
            String digest = calculateDigestFromBytes(content);
            
            // 存储manifest内容到blob位置
            Path manifestPath = getBlobPath(digest);
            Files.createDirectories(manifestPath.getParent());
            Files.write(manifestPath, content);
            
            // 如果reference不是digest，创建tag链接
            if (!reference.startsWith("sha256:")) {
                Path linkPath = getManifestTagPath(repoName, reference);
                Files.createDirectories(linkPath.getParent());
                Files.write(linkPath, digest.getBytes());
            }
            
            logger.info("Stored manifest {} for repository: {} with digest: {}", reference, repoName, digest);
            return digest;
            
        } catch (IOException | NoSuchAlgorithmException e) {
            logger.error("Failed to store manifest: {} for repository: {}", reference, repoName, e);
            throw new RuntimeException("Failed to store manifest", e);
        }
    }
    
    /**
     * 从字节数组计算digest
     */
    private String calculateDigestFromBytes(byte[] content) throws NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
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
    }
    
    /**
     * 验证Manifest依赖的所有Blob是否存在
     */
    public void validateManifestBlobs(String contentType, byte[] content) throws BlobNotFoundException {
        try {
            String contentStr = new String(content);
            
            if (contentType.equals("application/vnd.docker.distribution.manifest.v2+json") ||
                contentType.equals("application/vnd.oci.image.manifest.v1+json")) {
                
                // 解析单个manifest
                validateSingleManifestBlobs(contentStr);
                
            } else if (contentType.equals("application/vnd.docker.distribution.manifest.list.v2+json") ||
                       contentType.equals("application/vnd.oci.image.index.v1+json")) {
                
                // 解析manifest list
                validateManifestListBlobs(contentStr);
            }
            
        } catch (Exception e) {
            logger.error("Failed to validate manifest blobs", e);
            throw new RuntimeException("Failed to validate manifest blobs", e);
        }
    }
    
    /**
     * 验证单个manifest的blob依赖
     */
    private void validateSingleManifestBlobs(String manifestJson) throws BlobNotFoundException {
        // 简单的JSON解析来提取digest值
        // 这里用正则表达式提取所有的sha256 digest
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("\"digest\"\\s*:\\s*\"(sha256:[a-f0-9]{64})\"");
        java.util.regex.Matcher matcher = pattern.matcher(manifestJson);
        
        while (matcher.find()) {
            String digest = matcher.group(1);
            try {
                statBlob(digest); // 如果blob不存在会抛出BlobNotFoundException
            } catch (BlobNotFoundException e) {
                logger.error("Required blob not found: {}", digest);
                throw e;
            }
        }
    }
    
    /**
     * 验证manifest list的manifest依赖
     */
    private void validateManifestListBlobs(String manifestListJson) throws BlobNotFoundException {
        // 对于manifest list，我们验证其中引用的manifest是否存在
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("\"digest\"\\s*:\\s*\"(sha256:[a-f0-9]{64})\"");
        java.util.regex.Matcher matcher = pattern.matcher(manifestListJson);
        
        while (matcher.find()) {
            String digest = matcher.group(1);
            try {
                statBlob(digest); // 检查引用的manifest是否存在
            } catch (BlobNotFoundException e) {
                logger.error("Required manifest not found: {}", digest);
                throw e;
            }
        }
    }
    
    /**
     * 根据内容判断Manifest类型
     */
    private String determineManifestContentType(byte[] content) {
        String contentStr = new String(content);
        
        if (contentStr.contains("\"manifests\"")) {
            // 包含manifests字段，可能是manifest list
            if (contentStr.contains("application/vnd.docker.distribution.manifest.list.v2+json")) {
                return "application/vnd.docker.distribution.manifest.list.v2+json";
            } else if (contentStr.contains("application/vnd.oci.image.index.v1+json")) {
                return "application/vnd.oci.image.index.v1+json";
            }
            return "application/vnd.docker.distribution.manifest.list.v2+json";
        } else {
            // 单个manifest
            if (contentStr.contains("application/vnd.oci.image.manifest.v1+json")) {
                return "application/vnd.oci.image.manifest.v1+json";
            }
            return "application/vnd.docker.distribution.manifest.v2+json";
        }
    }
    
    /**
     * Manifest 数据包装类
     */
    public static class ManifestData {
        private final byte[] content;
        private final String digest;
        private final String contentType;
        
        public ManifestData(byte[] content, String digest, String contentType) {
            this.content = content;
            this.digest = digest;
            this.contentType = contentType;
        }
        
        public byte[] getContent() { return content; }
        public String getDigest() { return digest; }
        public String getContentType() { return contentType; }
    }
}