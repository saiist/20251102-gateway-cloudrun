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
API_ID="api-server-api"
API_KEY_NAME="api-server-key"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Key Setup with Referrer Restrictions${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# プロジェクトIDの確認
if [ "$PROJECT_ID" = "your-project-id" ]; then
    echo -e "${RED}Error: Please set GCP_PROJECT_ID environment variable${NC}"
    echo "Example: export GCP_PROJECT_ID=your-actual-project-id"
    exit 1
fi

# プロジェクトの設定
echo -e "${YELLOW}Setting project to ${PROJECT_ID}...${NC}"
gcloud config set project ${PROJECT_ID}

# デフォルトのリファラー（ローカルホスト）
DEFAULT_REFERRERS=(
    "http://localhost:*"
    "http://127.0.0.1:*"
    "file://*"
)

echo -e "${YELLOW}デフォルトのリファラー制限（ローカルホスト用）:${NC}"
for ref in "${DEFAULT_REFERRERS[@]}"; do
    echo "  - $ref"
done
echo ""

read -p "デフォルト設定を使用しますか？ (y/n): " use_default

if [[ "$use_default" =~ ^[Yy]$ ]]; then
    referrers=("${DEFAULT_REFERRERS[@]}")
else
    echo -e "${YELLOW}カスタムリファラーを入力してください (1行に1つ、空行でEnterで終了):${NC}"
    echo "例:"
    echo "  http://localhost:*"
    echo "  https://yourdomain.com/*"
    echo ""

    referrers=()
    while true; do
        read -p "Referrer: " line
        if [ -z "$line" ]; then
            break
        fi
        referrers+=("$line")
    done

    if [ ${#referrers[@]} -eq 0 ]; then
        echo -e "${RED}Error: At least one referrer must be specified${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}以下のリファラー制限でAPIキーを作成します:${NC}"
for ref in "${referrers[@]}"; do
    echo "  - $ref"
done
echo ""

# 既存のAPIキーをチェック
existing_key=$(gcloud services api-keys list \
    --filter="displayName:${API_KEY_NAME}" \
    --format="value(name)" 2>/dev/null | head -n 1)

if [ -n "$existing_key" ]; then
    echo -e "${YELLOW}既存のAPIキーが見つかりました: ${API_KEY_NAME}${NC}"
    read -p "削除して再作成しますか？ (y/n): " recreate

    if [[ "$recreate" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}既存のAPIキーを削除中...${NC}"
        gcloud services api-keys delete $existing_key --quiet
        echo -e "${GREEN}削除完了${NC}"
    else
        echo -e "${YELLOW}処理を中止しました${NC}"
        exit 0
    fi
fi

echo -e "${YELLOW}APIキーを作成中...${NC}"

# リファラー制限をカンマ区切りに変換
referrers_str=$(IFS=,; echo "${referrers[*]}")

# API Keyの作成
gcloud services api-keys create \
    --display-name="${API_KEY_NAME}" \
    --allowed-referrers="${referrers_str}" \
    --api-target=service=${API_ID}.apigateway.${PROJECT_ID}.cloud.goog

# 少し待機（APIキーの作成完了を待つ）
echo -e "${YELLOW}APIキーの作成を待機中...${NC}"
sleep 5

# API Keyの取得
API_KEY_ID=$(gcloud services api-keys list \
    --filter="displayName:${API_KEY_NAME}" \
    --format="value(name)" \
    --limit=1)

if [ -z "$API_KEY_ID" ]; then
    echo -e "${RED}Error: Could not retrieve API Key${NC}"
    exit 1
fi

# API Key文字列の取得
KEY_STRING=$(gcloud services api-keys get-key-string $API_KEY_ID \
    --format="value(keyString)")

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ APIキーの作成が完了しました！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}API Key:${NC}"
echo -e "${GREEN}${KEY_STRING}${NC}"
echo ""
echo -e "${YELLOW}許可されたリファラー:${NC}"
for ref in "${referrers[@]}"; do
    echo "  - $ref"
done
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}次のステップ:${NC}"
echo ""
echo "1. openapi.yamlのsecurityセクションのコメントを解除:"
echo "   ${BLUE}security:${NC}"
echo "   ${BLUE}  - api_key: []${NC}"
echo ""
echo "2. API Gatewayを再デプロイ:"
echo "   ${BLUE}./deploy-gateway.sh${NC}"
echo ""
echo "3. test.htmlを開いて、以下を設定:"
echo "   - API Gateway URL"
echo "   - API Key: ${GREEN}${KEY_STRING}${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
