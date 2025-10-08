#!/bin/bash
set -e

# ================================================================================
# Linux 下的 Bash 脚本 - Blob 上传接口测试
# 描述: 针对 Blob 上传接口的独立、精细化测试脚本。
#       验证分块上传、状态查询、范围校验、取消和完成逻辑。
# ================================================================================

REGISTRY_HOST="localhost:5000"
API_BASE_URL="http://$REGISTRY_HOST/v2"
REPO_NAME="blob-advanced-test"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 辅助函数 ---
assert_status() {
    local test_name="$1"
    local actual_status="$2"
    local expected_status="$3"
    
    if [ "$actual_status" != "$expected_status" ]; then
        echo -e "${RED}--- ❌ TEST FAILED: $test_name ---${NC}"
        echo -e "${RED}预期状态码: $expected_status, 实际: $actual_status${NC}"
        exit 1
    fi
    echo -e "${GREEN}--- ✅ TEST PASSED: $test_name (状态码: $expected_status) ---${NC}"
}

get_header() {
    local headers="$1"
    local header_name="$2"
    echo "$headers" | grep -i "^$header_name:" | cut -d' ' -f2- | tr -d '\r\n'
}

calculate_sha256() {
    local content="$1"
    echo -n "$content" | sha256sum | awk '{print $1}'
}

# ================================================================================
# --- 脚本开始 ---
# ================================================================================
echo -e "${YELLOW}--- 🧹 清理环境... ---${NC}"
STORAGE_PATH="${REGISTRY_STORAGE_ROOT:-$HOME/.local/share/docker-registry}/v2"
if [ -d "$STORAGE_PATH" ]; then
    rm -rf "$STORAGE_PATH"
fi
echo -e "${YELLOW}--- 清理完成。---\n${NC}"

# --- TEST 1: 启动上传 & 查询空状态 ---
echo -e "${CYAN}--- TEST 1: 启动上传 (POST) & 查询空状态 (GET) ---${NC}"
START_UPLOAD_URL="$API_BASE_URL/$REPO_NAME/blobs/uploads/"

# 启动上传
RESPONSE=$(curl -i -s -X POST "$START_UPLOAD_URL")
STATUS=$(echo "$RESPONSE" | grep "HTTP/" | awk '{print $2}')
assert_status "1.1 启动上传" "$STATUS" "202"

UPLOAD_URL=$(get_header "$RESPONSE" "Location")
UUID=$(get_header "$RESPONSE" "Docker-Upload-UUID")

if [ -z "$UPLOAD_URL" ] || [ -z "$UUID" ]; then
    echo -e "${RED}--- ❌ TEST FAILED: 1.1 Location 或 UUID 头缺失 ---${NC}"
    exit 1
fi

# 查询空状态
STATUS_RESPONSE=$(curl -i -s -X GET "$UPLOAD_URL")
STATUS=$(echo "$STATUS_RESPONSE" | grep "HTTP/" | awk '{print $2}')
assert_status "1.2 查询空状态" "$STATUS" "204"

RANGE_HEADER=$(get_header "$STATUS_RESPONSE" "Range")
if [ "$RANGE_HEADER" != "0-0" ]; then
    echo -e "${RED}--- ❌ TEST FAILED: 1.2 空状态 Range 头不是 '0-0'，实际: $RANGE_HEADER ---${NC}"
    exit 1
fi
echo -e "\n"

# --- TEST 2: 上传数据块 & 范围校验 ---
echo -e "${CYAN}--- TEST 2: 上传数据块 (PATCH) & 范围校验 ---${NC}"
CHUNK1="first_chunk_of_data"
CHUNK1_LEN=${#CHUNK1}

# 上传第一个块
PATCH_RESPONSE1=$(curl -i -s -X PATCH "$UPLOAD_URL" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "$CHUNK1")
STATUS=$(echo "$PATCH_RESPONSE1" | grep "HTTP/" | awk '{print $2}')
assert_status "2.1 上传第一个块" "$STATUS" "202"

EXPECTED_RANGE1="0-$((CHUNK1_LEN - 1))"
ACTUAL_RANGE1=$(get_header "$PATCH_RESPONSE1" "Range")
if [ "$ACTUAL_RANGE1" != "$EXPECTED_RANGE1" ]; then
    echo -e "${RED}--- ❌ TEST FAILED: 2.1 Range 头不匹配, 预期: $EXPECTED_RANGE1, 实际: $ACTUAL_RANGE1 ---${NC}"
    exit 1
fi

# 上传第二个块（连续）
CHUNK2="_second_chunk"
CHUNK2_LEN=${#CHUNK2}
CONTENT_RANGE="$CHUNK1_LEN-$((CHUNK1_LEN + CHUNK2_LEN - 1))"

PATCH_RESPONSE2=$(curl -i -s -X PATCH "$UPLOAD_URL" \
    -H "Content-Type: application/octet-stream" \
    -H "Content-Range: $CONTENT_RANGE" \
    --data-binary "$CHUNK2")
STATUS=$(echo "$PATCH_RESPONSE2" | grep "HTTP/" | awk '{print $2}')
assert_status "2.2 上传连续的第二个块 (带 Content-Range)" "$STATUS" "202"

# 测试不连续的范围（应该失败）
PATCH_RESPONSE3=$(curl -i -s -X PATCH "$UPLOAD_URL" \
    -H "Content-Type: application/octet-stream" \
    -H "Content-Range: 0-10" \
    --data-binary "bad_data")
STATUS=$(echo "$PATCH_RESPONSE3" | grep "HTTP/" | awk '{print $2}')
assert_status "2.3 校验不连续的 Content-Range" "$STATUS" "416"
echo -e "\n"

# --- TEST 3: 取消上传 ---
echo -e "${CYAN}--- TEST 3: 取消上传 (DELETE) ---${NC}"

# 取消上传
DELETE_RESPONSE=$(curl -i -s -X DELETE "$UPLOAD_URL")
STATUS=$(echo "$DELETE_RESPONSE" | grep "HTTP/" | awk '{print $2}')
assert_status "3.1 取消上传" "$STATUS" "204"

# 验证上传已取消
GET_RESPONSE=$(curl -i -s -X GET "$UPLOAD_URL")
STATUS=$(echo "$GET_RESPONSE" | grep "HTTP/" | awk '{print $2}')
assert_status "3.2 验证上传已取消" "$STATUS" "404"
echo -e "\n"

# --- TEST 4: 完整上传并验证 ---
echo -e "${CYAN}--- TEST 4: 完整上传 (PUT) 并验证 (HEAD) ---${NC}"
FULL_CONTENT="this_is_the_full_blob_content_for_a_successful_upload"
SHA256=$(calculate_sha256 "$FULL_CONTENT")
CORRECT_DIGEST="sha256:$SHA256"

# 启动新上传
START_RESPONSE4=$(curl -i -s -X POST "$START_UPLOAD_URL")
UPLOAD_URL4=$(get_header "$START_RESPONSE4" "Location")

# 一次性 PUT 完整内容
PUT_URL="$UPLOAD_URL4?digest=$CORRECT_DIGEST"
PUT_RESPONSE=$(curl -i -s -X PUT "$PUT_URL" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "$FULL_CONTENT")
STATUS=$(echo "$PUT_RESPONSE" | grep "HTTP/" | awk '{print $2}')
assert_status "4.1 完成上传 (PUT)" "$STATUS" "201"

FINAL_LOCATION=$(get_header "$PUT_RESPONSE" "Location")

# 验证最终的 Blob
HEAD_RESPONSE4=$(curl -i -s -X HEAD "$FINAL_LOCATION")
STATUS=$(echo "$HEAD_RESPONSE4" | grep "HTTP/" | awk '{print $2}')
assert_status "4.2 验证最终的 Blob (HEAD)" "$STATUS" "200"

CONTENT_LENGTH=$(get_header "$HEAD_RESPONSE4" "Content-Length")
if [ "$CONTENT_LENGTH" != "${#FULL_CONTENT}" ]; then
    echo -e "${RED}--- ❌ TEST FAILED: 4.2 Content-Length 不匹配，预期: ${#FULL_CONTENT}, 实际: $CONTENT_LENGTH ---${NC}"
    exit 1
fi

ACTUAL_DIGEST=$(get_header "$HEAD_RESPONSE4" "Docker-Content-Digest")
if [ "$ACTUAL_DIGEST" != "$CORRECT_DIGEST" ]; then
    echo -e "${RED}--- ❌ TEST FAILED: 4.2 Digest 不匹配，预期: $CORRECT_DIGEST, 实际: $ACTUAL_DIGEST ---${NC}"
    exit 1
fi
echo -e "\n"

# --- TEST 5: 测试 Digest 校验失败 ---
echo -e "${CYAN}--- TEST 5: 测试 Digest 校验失败 (PUT) ---${NC}"

# 启动新上传
START_RESPONSE5=$(curl -i -s -X POST "$START_UPLOAD_URL")
UPLOAD_URL5=$(get_header "$START_RESPONSE5" "Location")

WRONG_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
PUT_URL5="$UPLOAD_URL5?digest=$WRONG_DIGEST"

PUT_RESPONSE5=$(curl -i -s -X PUT "$PUT_URL5" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "some_content")
STATUS=$(echo "$PUT_RESPONSE5" | grep "HTTP/" | awk '{print $2}')
assert_status "5.1 Digest 校验失败" "$STATUS" "400"
echo -e "\n"

# --- 总结 ---
echo -e "${GREEN}==========================================================${NC}"
echo -e "${GREEN}🎉 恭喜！所有高级 Blob 上传接口均已通过严格测试！${NC}"
echo -e "${GREEN}==========================================================${NC}"
