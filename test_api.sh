#!/bin/bash

# Docker Registry API Test Script

BASE_URL="http://localhost:5000"

echo "Testing Docker Registry API..."

# Test 1: API Version Check
echo "1. Testing API version check..."
response=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL/v2/")
if [ "$response" -eq 200 ]; then
    echo "✓ API version check passed"
else
    echo "✗ API version check failed (HTTP $response)"
fi

# Test 2: Start blob upload
echo "2. Testing blob upload start..."
response=$(curl -s -w "%{http_code}" -X POST "$BASE_URL/v2/test/blobs/uploads/" -o /tmp/upload_response.json)
if [ "$response" -eq 202 ]; then
    echo "✓ Blob upload start passed"
    # Extract upload URL from Location header
    location=$(curl -s -I -X POST "$BASE_URL/v2/test/blobs/uploads/" | grep -i "location:" | cut -d' ' -f2 | tr -d '\r\n')
    echo "Upload URL: $location"
else
    echo "✗ Blob upload start failed (HTTP $response)"
fi

echo "Test completed."
echo ""
echo "To run full Docker integration test:"
echo "1. Configure Docker daemon.json with insecure-registries"
echo "2. Run: docker push localhost:5000/test/hello-world:latest"