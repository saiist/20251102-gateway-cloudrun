# API Server (Go)

Cloud RunとAPI Gatewayで動作するGoベースのAPIサーバー

## プロジェクト構造

```
.
├── cmd/
│   └── api/
│       └── main.go          # エントリーポイント
├── handlers/
│   ├── health.go            # ヘルスチェックハンドラー
│   └── api.go               # APIハンドラー
├── middleware/
│   └── logger.go            # ロギングミドルウェア
├── config/
│   └── config.go            # 設定管理
├── Dockerfile               # Cloud Run用Dockerfile
├── cloudbuild.yaml          # Cloud Build設定
├── openapi.yaml             # API Gateway用OpenAPI仕様
├── deploy.sh                # Cloud Runデプロイスクリプト
└── deploy-gateway.sh        # API Gatewayデプロイスクリプト
```

## 必要な環境

- Go 1.23以上
- Docker
- Google Cloud SDK (gcloud)

## ローカルでの実行

```bash
# 依存関係のダウンロード
go mod download

# サーバーの起動
go run cmd/api/main.go
```

サーバーは `http://localhost:8080` で起動します。

### エンドポイント

- `GET /health` - ヘルスチェック
- `GET /api/hello` - Hello メッセージ
- `GET /api/items` - アイテム一覧

## Cloud Runへのデプロイ

### 前提条件

1. GCPプロジェクトの作成

2. gcloud CLIの認証：
```bash
# Google Cloudへのログイン
gcloud auth login

# アプリケーションのデフォルト認証情報の設定（Dockerイメージのpush等に必要）
gcloud auth configure-docker

# プロジェクトの設定
gcloud config set project your-project-id
```

3. 必要なAPIの有効化：
```bash
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

### デプロイ手順

1. 環境変数の設定：
```bash
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=asia-northeast1
```

2. デプロイスクリプトの実行：
```bash
./deploy.sh
```

または、Cloud Buildを使用：
```bash
gcloud builds submit --config cloudbuild.yaml
```

## API Gatewayのセットアップ

### 前提条件

1. Cloud Runサービスのデプロイが完了していること
2. 必要なAPIの有効化：
```bash
gcloud services enable apigateway.googleapis.com
gcloud services enable servicemanagement.googleapis.com
gcloud services enable servicecontrol.googleapis.com
```

### デプロイ手順

1. 環境変数の設定（Cloud Runと同じ）：
```bash
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=asia-northeast1
```

2. API Gatewayのデプロイ：
```bash
chmod +x deploy-gateway.sh
./deploy-gateway.sh
```

このスクリプトは以下を実行します：
- Cloud RunサービスのURLを自動取得
- OpenAPI仕様ファイルの更新
- API Gatewayの作成/更新

### API Keyの設定（オプション）

API Keyを使用してアクセスを制限する場合：

1. API Keyの作成：
```bash
gcloud alpha services api-keys create \
  --display-name="API Server Key" \
  --api-target=service=api-server-api.apigateway.your-project-id.cloud.goog
```

2. `openapi.yaml`のsecurityセクションのコメントを解除

3. API Gatewayを再デプロイ

## reCAPTCHA v3の設定

Bot攻撃を防ぐため、reCAPTCHA v3を実装しています。

### 設定済みの内容

このプロジェクトには既にreCAPTCHA v3が実装されており、以下が設定されています：

- **Site Key（公開鍵）**: `6LdjF_8rAAAAAB8GOKLPslNY6xVyPiqjdk6kY2sg`
- **Secret Key**: Cloud Runの環境変数 `RECAPTCHA_SECRET_KEY` に設定済み
- **検証閾値**: スコア0.5以上を人間と判定
- **アクション**: `api_call`

### reCAPTCHAの動作

1. **フロントエンド（test.html）**
   - ボタンクリック時に自動的にreCAPTCHAトークンを取得
   - `x-recaptcha-token`ヘッダーでトークンを送信

2. **バックエンド（Go）**
   - `middleware/recaptcha.go`でトークンを検証
   - Googleに問い合わせてスコアを取得
   - スコア0.5未満または無効なトークン → 403 Forbidden
   - トークンなし → 403 Forbidden

3. **ブロック条件**
   - reCAPTCHAトークンがない
   - トークンが無効
   - スコアが0.5未満（Bot判定）
   - アクションが`api_call`でない

### Botシミュレーションテスト

test.htmlには、reCAPTCHA検証をテストするための機能があります：

- **🚫 無効なトークンで送信** - わざと間違ったトークンを送信してブロックされることを確認
- **⛔ トークンなしで送信** - トークンなしでブロックされることを確認

### ログの確認

reCAPTCHA検証のログを確認：

```bash
gcloud run services logs read api-server --region=asia-northeast1 --limit=50
```

ログには以下の情報が含まれます：
- reCAPTCHAスコア
- アクション名
- 検証結果

### 新しいreCAPTCHAキーを作成する場合

1. [Google reCAPTCHA管理画面](https://www.google.com/recaptcha/admin)にアクセス
2. 新しいサイトを登録（reCAPTCHA v3を選択）
3. ドメインを追加（localhost、本番ドメインなど）
4. Site KeyとSecret Keyを取得
5. `test.html`のSite Keyを更新
6. `deploy.sh`と`cloudbuild.yaml`のSecret Keyを更新
7. 再デプロイ

## デプロイ後のテスト

### Cloud Runサービスのテスト

デプロイが完了すると、スクリプトがサービスURLを表示します。

```bash
# サービスURLの取得
export SERVICE_URL=$(gcloud run services describe api-server \
    --platform managed \
    --region asia-northeast1 \
    --format 'value(status.url)')

echo $SERVICE_URL
```

各エンドポイントのテスト：

```bash
# ヘルスチェック
curl ${SERVICE_URL}/health

# Hello エンドポイント
curl ${SERVICE_URL}/api/hello

# Items エンドポイント
curl ${SERVICE_URL}/api/items
```

JSONをきれいに表示する場合：

```bash
curl -s ${SERVICE_URL}/health | jq
curl -s ${SERVICE_URL}/api/hello | jq
curl -s ${SERVICE_URL}/api/items | jq
```

### API Gateway経由のテスト

API Gatewayのデプロイ後：

```bash
# Gateway URLの取得
export GATEWAY_URL=$(gcloud api-gateway gateways describe api-gateway \
    --location asia-northeast1 \
    --format 'value(defaultHostname)')

echo "https://${GATEWAY_URL}"
```

API Gateway経由でエンドポイントをテスト：

```bash
# ヘルスチェック
curl https://${GATEWAY_URL}/health

# Hello エンドポイント
curl https://${GATEWAY_URL}/api/hello

# Items エンドポイント
curl https://${GATEWAY_URL}/api/items
```

### 負荷テスト（オプション）

簡易的な負荷テスト：

```bash
# apacheベンチ（100リクエスト、同時接続10）
ab -n 100 -c 10 ${SERVICE_URL}/health

# または hey を使用
hey -n 100 -c 10 ${SERVICE_URL}/health
```

### 期待されるレスポンス

**GET /health**
```json
{
  "status": "healthy",
  "message": "API server is running"
}
```

**GET /api/hello**
```json
{
  "message": "Hello from API Server",
  "data": {
    "version": "1.0.0"
  }
}
```

**GET /api/items**
```json
{
  "message": "Items retrieved successfully",
  "data": [
    {
      "id": 1,
      "name": "Item 1",
      "description": "Description for item 1"
    },
    {
      "id": 2,
      "name": "Item 2",
      "description": "Description for item 2"
    },
    {
      "id": 3,
      "name": "Item 3",
      "description": "Description for item 3"
    }
  ]
}
```

## 環境変数

- `PORT`: サーバーのポート番号（デフォルト: 8080）
- `ENV`: 環境名（development/production）

## 開発

### テストの実行

```bash
go test ./...
```

### ローカルでのDockerビルド

```bash
docker build -t api-server .
docker run -p 8080:8080 api-server
```

## トラブルシューティング

### Cloud Runのログ確認

```bash
gcloud run services logs read api-server --region=asia-northeast1
```

### API Gatewayのログ確認

```bash
gcloud logging read "resource.type=api AND resource.labels.service=api-server-api" --limit 50
```

## ライセンス

MIT
