# Phase 5 — 運用整備・残タスク細分化

- 親計画: `2026-08-09-migration-to-lubuntu.md`
- ステータス: Draft
- 担当: yplic + Muse Spark

## 目的

Lubuntu集約後の運用品質を上げるquick winsと、未移行の重いタスクを整理する。重いタスクは子課題に分解して順次対応する。

## 子課題一覧

### 5-1: Quick wins (本Phaseで即対応)

| # | 項目 | 内容 | 工数 |
|---|------|------|------|
| 5-1a | ログローテーション | 全composeサービスに `logging: {driver: json-file, options: {max-size: "10m", max-file: "3"}}` を追加 | 小 |
| 5-1b | Portal healthcheck修正 | 既に対応済み（healthy復帰、ログ確認） | 済 |
| 5-1c | CPU温度Grafana対応 | 済（node-exporter追加） | 済 |
| 5-1d | Secrets .env化 | 済（HERMES_API_KEY / GRAFANA_ADMIN_PASSWORD） | 済 |
| 5-1e | デプロイ手順ドキュメント | `infra/README.md` に全スタックの起動・更新・トラブルシュート手順を追記 | 小 |

### 5-2: 中課題（Phase 5内で対応、またはPhase 6へ繰越）

| # | 項目 | 内容 | 工数 |
|---|------|------|------|
| 5-2a | バックアップ方針 | Prom/Grafana volumes, Portal/runtime設定のバックアップ（cron + rsync or restic） | 中 |
| 5-2b | アラート整備 | Prometheus Alertmanager or Grafanaアラートで温度・ディスク・GPU閾値通知 | 中 |
| 5-2c | UFW/Firewall整理 | Lubuntuのufwルール整備（内部LANのみ許可、外部遮断） | 小 |

### 5-3: 重課題（Phase 6として分離、別計画書で詳細化）

| # | 項目 | 内容 | 工数 |
|---|------|------|------|
| 6-1 | Gateway移行 | Hermes Gateway（Discord Bot + API Server）をLubuntuへ移行。venvインストール、Discordトークン移行、PortalのHERMES_API_URL切替。ThinkPad側は停止 | 大 |
| 6-2 | Viewers移行 | image-gallery（Desktop 83G含む）/ asmr-viewer / missav-viewer をLubuntuへ。データ同期戦略（rsync/NFS）が必要 | 大 |
| 6-3 | comfyui-console / genimg-api移行 | WinPC連携部分の疎通維持、LubuntuからのLAN疎通確認 | 中 |

## 進め方

- 5-1e, 5-1a を本Phaseで即実施
- 5-2は優先度に応じてIssue化（本PhaseでやるものとPhase 6へ回すものを振り分け）
- 6-1〜6-3は `docs/plans/phase-6-*.md` として別途計画書を作成し、Phase 5完了後に着手

## 受け入れ条件（Phase 5）

- [ ] 5-1a: 全composeでログローテーションが設定され、`docker compose config` で確認できる
- [ ] 5-1e: READMEにデプロイ手順が記載され、第三者が`git pull && docker compose up -d` で再現できる
- [ ] 5-2/5-3: Issue化され、優先度が整理されている
