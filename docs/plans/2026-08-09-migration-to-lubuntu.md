# 移行計画: ThinkPad → Lubuntu 運用集約 + OTel/ECSライク基盤

- 作成日: 2026-08-09
- 作成者: yplic + Muse Spark
- ステータス: Draft → Issue化して着手
- 前提: Lubuntu(192.168.12.123)は推論系（Ollama/whisper/VOICEVOX）は移行済みだが、Portal/ビューア群はThinkPad残留。infraリポジトリを新設し段階移行する。

## 目的

1. Lubuntuを単一の運用基盤に集約し、ThinkPadを引退可能にする
2. サービスをコンテナ化し、ECSライクな運用（compose = タスク定義、git pull + compose up = デプロイ）を確立する
3. OpenTelemetryを学習・導入し、テレメトリを標準化する（将来のGrafana可視化・アラートまで見据える）

## 現状棚卸し

### Lubuntu (移行済み)

| サービス | 形態 | ポート |
|---------|------|--------|
| Ollama (qwen3:14b等) | systemd (ollama.service) | 11434 |
| Go Runtime (local-ai-runtime) | systemd user | 8090 |
| Python VAD Service | Go Runtimeが子プロセス起動 | 8092 |
| faster-whisper | systemd user (whisper-server) | 8093 |
| VOICEVOX | docker (voicevox-engine) | 50021 |
| telemetry-agent | systemd user (本日追加) | 8095 |

### ThinkPad (残留・要移行)

| サービス | 形態 | ポート | 移行優先度 |
|---------|------|--------|-----------|
| Portal (Hermes Hub) | Goバイナリ + systemd user | 8080 | 高 |
| image-gallery (xp3viewer) | Go + systemd | 8765 | 中 |
| asmr-viewer | Go + systemd | 8787 | 中 |
| missav-viewer | Go + systemd | 8788 | 中 |
| comfyui-console | Go + systemd | 8100 | 低 |
| genimg-api | Go + systemd | - | 低 |
| hermes-gateway | systemd | 8642 | 要検討（Lubuntuへ移すか維持か） |

### WinPC (維持)

- ComfyUI :8188, Minecraft :25565 — 当面維持、監視対象には含める

## 全体アーキテクチャ（目標）

```
[Lubuntu 192.168.12.123]
  docker compose stacks:
    runtime/   → Go Runtime + Python Service + Whisper (+ Ollama)
    voicevox/  → VOICEVOX
    portal/    → Portal + Viewers
    otel/      → otelcol-contrib + Prometheus + Grafana (+ dcgm-exporter)

  Host services (当面残す):
    Ollama (systemd)  — コンテナ化はPhase 2で検討（モデルvolume肥大のため慎重に）
    nvidia-container-toolkit — GPUパススルー用（要Docker再起動、Phase 2）

[ThinkPad] — 移行完了まで維持、完了後停止
[WinPC]    — 監視対象（HTTP/TCPヘルスチェックのみ）
```

## フェーズ分割

### Phase 1: 土台 — infraリポジトリとOTelスタック（学習目的）

**目的**: ECSライクな運用の土台とOTelの学習を同時に達成する。GPU非依存でリスク低。

- infraリポジトリ初期化（本ドキュメント含む）
- `compose/otel/` 作成:
  - otelcol-contrib (hostmetrics receiver: CPU/メモリ/ディスク/ネットワーク)
  - Prometheus (otelcol → Prometheus remote write または Prometheusがotelcolをscrape)
  - Grafana (Prometheusデータソース、簡易ダッシュボード)
- 起動確認: Prometheus Targets, Grafanaでホストメトリクス可視化
- Portalの `/api/telemetry` は当面既存のtelemetry-agent(:8095)をpollする方式を維持（OTel移行は後続フェーズで検討）

**成果物**: `compose/otel/docker-compose.yml`, `otelcol-config.yml`, `prometheus.yml`, Grafana provisioning

**Issue化**: `infra: Phase 1 — OTelスタック構築（otelcol + Prometheus + Grafana）`

### Phase 2: GPU基盤 — nvidia-container-toolkit + コンテナGPU対応

**目的**: ECSのGPUタスク相当の運用を可能にする。

- nvidia-container-toolkit導入（aptリポジトリ追加、/etc/docker/daemon.json設定、docker再起動 — 要メンテ時間合意）
- `docker run --gpus all nvidia/cuda:xx nvidia-smi` で疎通確認
- dcgm-exporter導入（compose/otelに追加、GPUメトリクスをPrometheusへ）
- 既存telemetry-agentのGPU項目とdcgm-exporterの突合せ

**成果物**: GPU対応済みDocker基盤、dcgm-exporter統合

**Issue化**: `infra: Phase 2 — GPUコンテナ基盤（nvidia-container-toolkit + dcgm-exporter）`

### Phase 3: Runtime コンテナ化

**目的**: Go Runtime + Python Service + Whisperをcompose化し、ECSのサービスタスク運用を再現する。

- `compose/runtime/` 作成:
  - runtime (Go Runtime用Dockerfile、multi-stage build)
  - python-service (Python VAD用Dockerfile)
  - whisper (faster-whisper用Dockerfile、GPU対応時はcuda base)
  - 間の通信はcompose network内のサービス名解決
  - 設定はconfig.jsonをvolume mount（ECSの環境変数/ Secrets相当）
- systemd版と並走させての動作確認 → 切替 → systemd停止
- Ollamaは当面ホストのまま（モデルvolume 10GB超のためPhase 3では対象外、将来 `ollama/ollama` イメージで検討）

**成果物**: `compose/runtime/docker-compose.yml`, 各Dockerfile

**Issue化**: `infra: Phase 3 — Runtimeコンテナ化（Go + Python + Whisper）`

### Phase 4: Portal/ビューア移行

**目的**: ThinkPad上のメディア系サービスをLubuntuへ移行し、ThinkPad引退を可能にする。

- `compose/portal/` 作成（Portal, image-gallery, asmr-viewer, missav-viewer等）
- データ移行（SQLite DB, 画像パス等）
- 動作確認後、ThinkPad側systemd停止

**Issue化**: `infra: Phase 4 — Portal/ビューア移行`

### Phase 5: 運用整備

- compose全体のgit管理・デプロイ手順ドキュメント化
- Grafanaダッシュボード本格化（3台分テレメトリ、アラート）
- 必要に応じてPortainer導入（ECSコンソール相当）
- ThinkPad停止・引退

## 設計原則

- **段階移行**: 一度に全サービスを移さない。各Phaseで疎通確認してから次へ。
- **並走期間**: 切替時は旧（systemd）と新（compose）を並走させ、問題なければ旧を停止。
- **設計書駆動**: 各Phaseは本計画書を親とし、詳細設計は個別の `docs/plans/phase-N-*.md` に分割してIssue化する。
- **学習優先**: OTelはPhase 1で触り、GPU/ECSライク運用はPhase 2-3で段階的に習得する。

## リスク・懸念

| 項目 | 対策 |
|------|------|
| nvidia-container-toolkit導入でDocker再起動が必要 | Phase 2でメンテ時間を確保、事前に合意 |
| Ollamaモデルvolume肥大 | Phase 3では対象外、将来検討 |
| Portal等のデータ移行漏れ | Phase 4でDB/パスを事前棚卸し |
| OTel学習コスト | Phase 1は最小構成（hostmetricsのみ）で開始 |

## 次のアクション

1. 本計画書をレビュー → 承認
2. Phase 1の詳細設計書 `phase-1-otel-stack.md` 作成 → Issue化
3. Phase 1実装着手
