package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * Descriptor 描述了一个被引用的内容，是一个可复用组件
 * 对应 Docker Registry API 中的 Descriptor 结构
 */
@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Descriptor {
    
    @JsonProperty("mediaType")
    private String mediaType;
    
    @JsonProperty("size")
    private Long size;
    
    @JsonProperty("digest")
    private String digest;
    
    /**
     * Data 字段是 Manifest 中 config 描述符的一个可选字段。
     * 如果存在，它包含 base64 编码的配置 JSON。
     */
    @JsonProperty("data")
    private byte[] data;
    
    public Descriptor() {}
    
    public Descriptor(String mediaType, Long size, String digest) {
        this.mediaType = mediaType;
        this.size = size;
        this.digest = digest;
    }
}