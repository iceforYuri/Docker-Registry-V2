package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * PlatformSpec 描述了一个 manifest 所适用的平台，包括操作系统和CPU架构。
 */
@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class PlatformSpec {
    
    @JsonProperty("architecture")
    private String architecture;
    
    @JsonProperty("os")
    private String os;
    
    // 其他可选字段，如 Variant, OSVersion, OSFeatures，为简化暂不包含
    
    public PlatformSpec() {}
    
    public PlatformSpec(String architecture, String os) {
        this.architecture = architecture;
        this.os = os;
    }
}