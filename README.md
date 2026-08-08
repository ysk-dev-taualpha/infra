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
│   ├── voicevox/       # VOICEVOX
│   └── portal/         # Portal / Viewers
└── scripts/            # 運用スクリプト
```

## 運用

```bash
# デプロイ（Lubuntu上で）
cd ~/workspace/infra/compose/<stack>
docker compose up -d

# ログ
docker compose logs -f

# 更新
git pull && docker compose up -d --build
```

## 関連Issue

- local-ai-companion側のIssueで管理（ラベル: infra）
