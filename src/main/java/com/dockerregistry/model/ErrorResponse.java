package com.dockerregistry.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;

/**
 * Docker Registry API 错误响应格式
 */
@Data
public class ErrorResponse {
    
    @JsonProperty("errors")
    private List<ErrorDetail> errors;
    
    public ErrorResponse() {}
    
    public ErrorResponse(List<ErrorDetail> errors) {
        this.errors = errors;
    }
}