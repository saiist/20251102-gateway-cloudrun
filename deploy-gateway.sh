#!/bin/bash

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 設定変数
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
REGION="${GCP_REGION:-asia-northeast1}"
SERVICE_NAME="api-server"
GATEWAY_NAME="api-gateway"
API_ID="api-server-api"
API_CONFIG_ID="api-config"

echo -e "${YELLOW}Starting API Gateway deployment...${NC}"

# プロジェクトIDの確認
if [ "$PROJECT_ID" = "your-project-id" ]; then
    echo -e "${RED}Error: Please set GCP_PROJECT_ID environment variable${NC}"
    echo "Example: export GCP_PROJECT_ID=your-actual-project-id"
    exit 1
fi

# プロジェクトの設定
echo -e "${YELLOW}Setting project to ${PROJECT_ID}...${NC}"
gcloud config set project ${PROJECT_ID}

# Cloud RunのURLを取得
echo -e "${YELLOW}Getting Cloud Run service URL...${NC}"
CLOUD_RUN_URL=$(gcloud run services describe ${SERVICE_NAME} \
    --platform managed \
    --region ${REGION} \
    --format 'value(status.url)')

if [ -z "$CLOUD_RUN_URL" ]; then
    echo -e "${RED}Error: Could not get Cloud Run service URL${NC}"
    echo "Please deploy the Cloud Run service first using ./deploy.sh"
    exit 1
fi

echo -e "${GREEN}Cloud Run URL: ${CLOUD_RUN_URL}${NC}"

# OpenAPI仕様の更新
echo -e "${YELLOW}Updating OpenAPI specification...${NC}"
sed "s|YOUR_CLOUD_RUN_URL|${CLOUD_RUN_URL}|g" openapi.yaml > openapi-temp.yaml

# API の作成または更新
echo -e "${YELLOW}Creating/Updating API...${NC}"
gcloud api-gateway apis describe ${API_ID} 2>/dev/null || \
    gcloud api-gateway apis create ${API_ID} --project=${PROJECT_ID}

# サービスアカウントの確認/作成
SA_NAME="api-gateway-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${YELLOW}Checking service account...${NC}"
if ! gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} 2>/dev/null; then
    echo -e "${YELLOW}Creating service account...${NC}"
    gcloud iam service-accounts create ${SA_NAME} \
        --display-name="API Gateway Service Account" \
        --project=${PROJECT_ID}

    # Cloud Runを呼び出す権限を付与
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/run.invoker"
fi

# API設定の作成
echo -e "${YELLOW}Creating API config...${NC}"
API_CONFIG_ID="api-config-$(date +%Y%m%d%H%M%S)"
gcloud api-gateway api-configs create ${API_CONFIG_ID} \
    --api=${API_ID} \
    --openapi-spec=openapi-temp.yaml \
    --project=${PROJECT_ID} \
    --backend-auth-service-account=${SA_EMAIL}

# API Gatewayの作成または更新
echo -e "${YELLOW}Deploying API Gateway...${NC}"
if gcloud api-gateway gateways describe ${GATEWAY_NAME} --location=${REGION} 2>/dev/null; then
    echo -e "${YELLOW}Updating existing gateway...${NC}"
    gcloud api-gateway gateways update ${GATEWAY_NAME} \
        --api=${API_ID} \
        --api-config=${API_CONFIG_ID} \
        --location=${REGION} \
        --project=${PROJECT_ID}
else
    echo -e "${YELLOW}Creating new gateway...${NC}"
    gcloud api-gateway gateways create ${GATEWAY_NAME} \
        --api=${API_ID} \
        --api-config=${API_CONFIG_ID} \
        --location=${REGION} \
        --project=${PROJECT_ID}
fi

# 一時ファイルの削除
rm -f openapi-temp.yaml

# Gateway URLの取得
echo -e "${YELLOW}Waiting for gateway to be ready...${NC}"
sleep 10

GATEWAY_URL=$(gcloud api-gateway gateways describe ${GATEWAY_NAME} \
    --location=${REGION} \
    --format 'value(defaultHostname)')

echo -e "${GREEN}API Gateway deployment completed successfully!${NC}"
echo -e "${GREEN}Gateway URL: https://${GATEWAY_URL}${NC}"
echo -e "${GREEN}Health check: https://${GATEWAY_URL}/health${NC}"
echo -e "${GREEN}API endpoints:${NC}"
echo -e "${GREEN}  - GET https://${GATEWAY_URL}/api/hello${NC}"
echo -e "${GREEN}  - GET https://${GATEWAY_URL}/api/items${NC}"
