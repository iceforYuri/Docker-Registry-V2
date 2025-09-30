package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * 错误详情
 */
@Data
public class ErrorDetail {
    
    @JsonProperty("code")
    private String code;
    
    @JsonProperty("message")
    private String message;
    
    public ErrorDetail() {}
    
    public ErrorDetail(String code, String message) {
        this.code = code;
        this.message = message;
    }
}