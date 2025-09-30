package com.dockerregistry;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Docker Registry Lite - Spring Boot Application
 * 
 * 一个符合 Docker Registry HTTP API V2 规范的简化后端服务
 * 支持 Blob 分片上传、Manifest 管理和完整性校验
 */
@SpringBootApplication
public class DockerRegistryApplication {

    public static void main(String[] args) {
        SpringApplication.run(DockerRegistryApplication.class, args);
    }
}