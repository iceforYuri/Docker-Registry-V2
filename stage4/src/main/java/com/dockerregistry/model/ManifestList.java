package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;

/**
 * ManifestList (也称为 Fat Manifest 或 Image Index) 是一个 manifest 的集合，
 * 通常用于支持多架构镜像。它对应于 content type
 * "application/vnd.docker.distribution.manifest.list.v2+json" 或 OCI 的
 * "application/vnd.oci.image.index.v1+json"。
 */
@Data
public class ManifestList {
    
    @JsonProperty("schemaVersion")
    private Integer schemaVersion;
    
    @JsonProperty("mediaType")
    private String mediaType;
    
    /**
     * Manifests 列出了该 tag 下所有可用的 manifest。
     * Docker 客户端会根据自身的平台选择合适的 manifest 进行拉取。
     */
    @JsonProperty("manifests")
    private List<ManifestDescriptor> manifests;
    
    public ManifestList() {}
}