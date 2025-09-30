@echo off
REM Docker Registry Lite - Build Script for Windows

echo Building Docker Registry Lite...

REM Clean and compile
call mvn clean compile

if %ERRORLEVEL% equ 0 (
    echo Compilation successful!
    
    REM Package
    call mvn package -DskipTests
    
    if %ERRORLEVEL% equ 0 (
        echo Build successful!
        echo JAR file: target\docker-registry-lite-1.0.0.jar
        echo.
        echo To run the application:
        echo   java -jar target\docker-registry-lite-1.0.0.jar
        echo   or
        echo   mvn spring-boot:run
    ) else (
        echo Build failed during packaging!
        exit /b 1
    )
) else (
    echo Build failed during compilation!
    exit /b 1
)