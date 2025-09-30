package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.Map;

/**
 * ManifestDescriptor 在 Manifest List 中描述一个具体的 manifest 引用。
 * 它基本上是一个带有平台信息的 Descriptor。
 */
@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ManifestDescriptor {
    
    @JsonProperty("mediaType")
    private String mediaType;
    
    @JsonProperty("size")
    private Long size;
    
    @JsonProperty("digest")
    private String digest;
    
    @JsonProperty("platform")
    private PlatformSpec platform;
    
    @JsonProperty("annotations")
    private Map<String, String> annotations;
    
    public ManifestDescriptor() {}
}