#!/bin/bash

# --------------------------------------------------------------------------------
# 文件: test_basic.sh
# 描述: Docker Registry 基础功能快速测试脚本 (Linux/macOS 版本)
# --------------------------------------------------------------------------------

REGISTRY_HOST="localhost:5000"
API_BASE_URL="http://$REGISTRY_HOST/v2"

echo "=== Docker Registry 基础功能测试 ==="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 1. 测试基础 API
echo -e "\n${YELLOW}1. 测试基础 API...${NC}"
response=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE_URL/")
if [ "$response" = "200" ]; then
    echo -e "${GREEN}✅ 基础 API 正常${NC}"
else
    echo -e "${RED}❌ Registry 未运行，请先启动应用程序${NC}"
    echo -e "${YELLOW}运行: mvn spring-boot:run${NC}"
    exit 1
fi

# 2. 测试开始上传
echo -e "\n${YELLOW}2. 测试开始上传...${NC}"
upload_response=$(curl -s -X POST "$API_BASE_URL/test-repo/blobs/uploads/" -D -)
upload_status=$(echo "$upload_response" | head -n1 | cut -d' ' -f2)
if [ "$upload_status" = "202" ]; then
    echo -e "${GREEN}✅ 开始上传成功${NC}"
    upload_url=$(echo "$upload_response" | grep -i "location:" | cut -d' ' -f2- | tr -d '\r')
    echo -e "上传 URL: $upload_url"
else
    echo -e "${RED}❌ 开始上传失败${NC}"
    exit 1
fi

# 3. 测试上传数据
echo -e "\n${YELLOW}3. 测试上传数据...${NC}"
test_data="Hello World!"
patch_response=$(curl -s -X PATCH "$upload_url" \
    -H "Content-Type: application/octet-stream" \
    -d "$test_data" \
    -o /dev/null -w "%{http_code}")
if [ "$patch_response" = "202" ]; then
    echo -e "${GREEN}✅ 上传数据成功${NC}"
else
    echo -e "${RED}❌ 上传数据失败${NC}"
    exit 1
fi

# 4. 测试完成上传
echo -e "\n${YELLOW}4. 测试完成上传...${NC}"
digest="sha256:$(echo -n "$test_data" | sha256sum | cut -d' ' -f1)"
commit_url="${upload_url}?digest=$digest"
commit_response=$(curl -s -X PUT "$commit_url" -o /dev/null -w "%{http_code}")
if [ "$commit_response" = "201" ]; then
    echo -e "${GREEN}✅ 完成上传成功${NC}"
    echo -e "Blob digest: $digest"
else
    echo -e "${RED}❌ 完成上传失败${NC}"
    exit 1
fi

# 5. 测试获取 Blob
echo -e "\n${YELLOW}5. 测试获取 Blob...${NC}"
blob_url="$API_BASE_URL/test-repo/blobs/$digest"
downloaded_data=$(curl -s "$blob_url")
get_status=$(curl -s -o /dev/null -w "%{http_code}" "$blob_url")
if [ "$get_status" = "200" ] && [ "$downloaded_data" = "$test_data" ]; then
    echo -e "${GREEN}✅ 获取 Blob 成功${NC}"
else
    echo -e "${RED}❌ 获取 Blob 失败或数据不匹配${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉 所有基础测试通过！Docker Registry 运行正常！${NC}"