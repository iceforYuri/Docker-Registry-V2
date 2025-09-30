package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;

/**
 * Manifest 代表一个镜像的元数据，对应于 content type
 * "application/vnd.docker.distribution.manifest.v2+json" 或 OCI 的
 * "application/vnd.oci.image.manifest.v1+json"。
 */
@Data
public class Manifest {
    
    @JsonProperty("schemaVersion")
    private Integer schemaVersion;
    
    @JsonProperty("mediaType")
    private String mediaType;
    
    /**
     * Config 描述了镜像的配置文件。
     */
    @JsonProperty("config")
    private Descriptor config;
    
    /**
     * Layers 是一个有序列表，描述了构成镜像文件系统的各个层。
     */
    @JsonProperty("layers")
    private List<Descriptor> layers;
    
    public Manifest() {}
}