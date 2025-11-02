#!/bin/bash

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 設定変数
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
REGION="${GCP_REGION:-asia-northeast1}"
SERVICE_NAME="api-server"
GATEWAY_NAME="api-gateway"

# テストタイプ（cloud-run または gateway）
TEST_TYPE="${1:-cloud-run}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Server Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# URLの取得
if [ "$TEST_TYPE" = "gateway" ]; then
    echo -e "${YELLOW}Testing via API Gateway...${NC}"
    GATEWAY_HOST=$(gcloud api-gateway gateways describe ${GATEWAY_NAME} \
        --location=${REGION} \
        --format 'value(defaultHostname)' 2>/dev/null)

    if [ -z "$GATEWAY_HOST" ]; then
        echo -e "${RED}Error: API Gateway not found${NC}"
        exit 1
    fi

    BASE_URL="https://${GATEWAY_HOST}"
else
    echo -e "${YELLOW}Testing Cloud Run service directly...${NC}"
    BASE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --platform managed \
        --region ${REGION} \
        --format 'value(status.url)' 2>/dev/null)

    if [ -z "$BASE_URL" ]; then
        echo -e "${RED}Error: Cloud Run service not found${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Base URL: ${BASE_URL}${NC}"
echo ""

# テスト関数
test_endpoint() {
    local endpoint=$1
    local expected_status=$2
    local description=$3

    echo -e "${YELLOW}Testing: ${description}${NC}"
    echo -e "Endpoint: ${endpoint}"

    response=$(curl -s -w "\n%{http_code}" "${BASE_URL}${endpoint}")
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ Status: ${http_code}${NC}"
        if command -v jq &> /dev/null; then
            echo "$body" | jq .
        else
            echo "$body"
        fi
        echo ""
        return 0
    else
        echo -e "${RED}✗ Expected: ${expected_status}, Got: ${http_code}${NC}"
        echo "$body"
        echo ""
        return 1
    fi
}

# テストの実行
failed=0

test_endpoint "/health" "200" "Health Check" || ((failed++))
test_endpoint "/api/hello" "200" "Hello Endpoint" || ((failed++))
test_endpoint "/api/items" "200" "Items Endpoint" || ((failed++))

# 結果サマリー
echo -e "${BLUE}========================================${NC}"
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}${failed} test(s) failed ✗${NC}"
    exit 1
fi
