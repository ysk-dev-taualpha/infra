# infra — Lubuntu運用基盤（ECSライク）

Lubuntu (192.168.12.123, V100+GTX1060) をメイン運用基盤とするためのインフラ定義リポジトリ。

## 方針

- **ECSライク**: `compose/` 配下のcomposeファイルがECSのタスク定義に相当。`docker compose up -d` がデプロイ。
- **設計書駆動**: `docs/plans/*.md` に計画書を置き、Issue化してから実装する（local-ai-companionと同様のワークフロー）。
- **段階移行**: ThinkPad上のサービスを順にLubuntuへ移行する。One-shotで全移行しない。

## ホスト構成

| ホスト | IP | 役割（最終） |
|--------|----|-------------|
| ThinkPad X1C6 | 192.168.12.112 | 引退予定（移行完了まで維持） |
| Lubuntu Inspiron | 192.168.12.123 | メイン運用基盤（本リポジトリのデプロイ先） |
| WinPC | 192.168.12.107 | ComfyUI + Minecraft（当面維持） |

## ディレクトリ構成

```
infra/
├── docs/
│   ├── plans/          # 移行計画書・設計書
│   └── decisions.md    # アーキテクチャ決定記録
├── compose/            # composeファイル群（stack単位）
│   ├── otel/           # OTel + Prometheus + Grafana
│   ├── runtime/        # Go Runtime + Python Service + Whisper
│   ├── portal/         # Portal
│   └── hermes-viewer/  # React Native Web + Nginx proxy
└── scripts/            # 運用スクリプト（将来）
```

## デプロイ

### 初回セットアップ（Lubuntu）

```bash
git clone https://github.com/ysk-dev-taualpha/infra.git ~/workspace/infra

# Secretsを配置（.envはgitignore、.env.exampleを参照）
cp ~/workspace/infra/.env.example ~/workspace/infra/.env
# 編集: HERMES_API_KEY 等
cp ~/workspace/infra/compose/portal/.env.example ~/workspace/infra/compose/portal/.env
# 編集: HERMES_API_KEY
cp ~/workspace/infra/compose/otel/.env.example ~/workspace/infra/compose/otel/.env
# 編集: GRAFANA_ADMIN_PASSWORD

# Hermesの.env（Gateway用）は別途 ~/.hermes/.env で管理

# ビルド用Dockerfileをコンテキストに配置
mkdir -p ~/workspace/portal/.infra_portal
cp ~/workspace/infra/compose/portal/Dockerfile ~/workspace/portal/.infra_portal/Dockerfile
mkdir -p ~/workspace/local-ai-companion/.infra_runtime
cp ~/workspace/infra/compose/runtime/Dockerfile ~/workspace/local-ai-companion/.infra_runtime/Dockerfile
cp ~/workspace/infra/compose/runtime/Dockerfile.whisper ~/workspace/local-ai-companion/.infra_runtime/Dockerfile.whisper
mkdir -p ~/workspace/hermes-viewer/.infra_web
cp ~/workspace/infra/compose/hermes-viewer/Dockerfile ~/workspace/hermes-viewer/.infra_web/Dockerfile
cp ~/workspace/infra/compose/hermes-viewer/nginx.conf ~/workspace/hermes-viewer/.infra_web/nginx.conf
cp ~/workspace/infra/compose/hermes-viewer/dockerignore ~/workspace/hermes-viewer/.dockerignore
```

### 起動

```bash
# OTelスタック
cd ~/workspace/infra/compose/otel && docker compose up -d
# Runtime
cd ~/workspace/infra/compose/runtime && docker compose up -d
# Portal
cd ~/workspace/infra/compose/portal && docker compose up -d
# Hermes Viewer Web
cd ~/workspace/infra/compose/hermes-viewer && docker compose up -d --build
```

### 更新

```bash
cd ~/workspace/infra && git pull

# Dockerfile更新があれば再コピー
cp ~/workspace/infra/compose/portal/Dockerfile ~/workspace/portal/.infra_portal/Dockerfile
cp ~/workspace/infra/compose/runtime/Dockerfile ~/workspace/local-ai-companion/.infra_runtime/Dockerfile
cp ~/workspace/infra/compose/runtime/Dockerfile.whisper ~/workspace/local-ai-companion/.infra_runtime/Dockerfile.whisper
cp ~/workspace/infra/compose/hermes-viewer/Dockerfile ~/workspace/hermes-viewer/.infra_web/Dockerfile
cp ~/workspace/infra/compose/hermes-viewer/nginx.conf ~/workspace/hermes-viewer/.infra_web/nginx.conf
cp ~/workspace/infra/compose/hermes-viewer/dockerignore ~/workspace/hermes-viewer/.dockerignore

# 各スタックで再ビルド＆再起動
cd ~/workspace/infra/compose/otel && docker compose up -d
cd ~/workspace/infra/compose/runtime && docker compose up -d --build
cd ~/workspace/infra/compose/portal && docker compose up -d
cd ~/workspace/infra/compose/hermes-viewer && docker compose up -d --build
```

### ログ・ヘルス

```bash
docker ps --format "{{.Names}} {{.Status}}"
docker compose logs -f
curl http://localhost:3000/api/health  # Grafana
curl http://localhost:9090/-/healthy   # Prometheus
curl http://localhost:8090/healthz     # Runtime
curl http://localhost:8093/health      # Whisper
curl http://localhost:8080/api/health  # Portal
curl http://localhost:8790/healthz     # Hermes Viewer Web
```

### トラブルシュート

| 症状 | 対処 |
|------|------|
| `docker compose config` で環境変数が空 | `.env` が正しいディレクトリにあるか確認（composeファイルと同階層） |
| Portalが502 | ThinkPadのGateway（192.168.12.112:8642）が起動しているか、HERMES_API_KEYが一致しているか確認 |
| Whisperが unhealthy | GPUドライバ・`nvidia-container-toolkit` の状態を `nvidia-smi` / `docker info \| grep nvidia` で確認 |
| Grafanaにデータが無い | Prometheus Targets（http://192.168.12.123:9090/targets）で各jobがupか確認 |

## アクセス先

| サービス | URL | 認証 |
|---------|-----|------|
| Portal | http://192.168.12.123:8080 | なし |
| Grafana | http://192.168.12.123:3000 | GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD |
| Prometheus | http://192.168.12.123:9090 | なし（LAN内のみ） |
| Runtime | http://192.168.12.123:8090 | なし |
| Whisper | http://192.168.12.123:8093 | なし |
| Hermes Viewer Web | http://192.168.12.123:8790 | なし（LAN内のみ） |

## 関連Issue

- infraリポジトリのIssues: https://github.com/ysk-dev-taualpha/infra/issues
