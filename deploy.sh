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
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo -e "${YELLOW}Starting deployment...${NC}"

# プロジェクトIDの確認
if [ "$PROJECT_ID" = "your-project-id" ]; then
    echo -e "${RED}Error: Please set GCP_PROJECT_ID environment variable${NC}"
    echo "Example: export GCP_PROJECT_ID=your-actual-project-id"
    exit 1
fi

# プロジェクトの設定
echo -e "${YELLOW}Setting project to ${PROJECT_ID}...${NC}"
gcloud config set project ${PROJECT_ID}

# Dockerイメージのビルド
echo -e "${YELLOW}Building Docker image...${NC}"
docker build --platform linux/amd64 -t ${IMAGE_NAME}:latest .

# コンテナレジストリへのプッシュ
echo -e "${YELLOW}Pushing image to Container Registry...${NC}"
docker push ${IMAGE_NAME}:latest

# Cloud Runへのデプロイ
echo -e "${YELLOW}Deploying to Cloud Run...${NC}"
gcloud run deploy ${SERVICE_NAME} \
    --image ${IMAGE_NAME}:latest \
    --platform managed \
    --region ${REGION} \
    --allow-unauthenticated \
    --max-instances 10 \
    --memory 512Mi \
    --cpu 1 \
    --port 8080 \
    --set-env-vars RECAPTCHA_SECRET_KEY=6LdjF_8rAAAAAP_GNaooFnMWdvpCkdyIcTtnNfv7

# サービスURLの取得
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
    --platform managed \
    --region ${REGION} \
    --format 'value(status.url)')

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
echo -e "${GREEN}Health check: ${SERVICE_URL}/health${NC}"
