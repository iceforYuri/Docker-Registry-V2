#!/bin/bash

# Docker Registry Lite - Build Script

echo "Building Docker Registry Lite..."

# Clean and compile
mvn clean compile

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    
    # Package
    mvn package -DskipTests
    
    if [ $? -eq 0 ]; then
        echo "Build successful!"
        echo "JAR file: target/docker-registry-lite-1.0.0.jar"
        echo ""
        echo "To run the application:"
        echo "  java -jar target/docker-registry-lite-1.0.0.jar"
        echo "  or"
        echo "  mvn spring-boot:run"
    else
        echo "Build failed during packaging!"
        exit 1
    fi
else
    echo "Build failed during compilation!"
    exit 1
fi