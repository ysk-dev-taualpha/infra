# Decisions

## 2026-08-09: infraリポジトリ新設と段階移行

- infraリポジトリを新設し、Lubuntu運用基盤をcomposeで管理する
- 一括移行せずPhase 1〜5で段階移行する
- 各Phaseは `docs/plans/*.md` で設計書駆動、Issue化してから実装

## 2026-08-09: Phase 1はOTel最小構成

- Phase 1ではhostmetricsのみ、GPUはPhase 2へ分離
- otelcolはprometheus exporterで:8889公開、Prometheusがscrapeするシンプル方式
- OTLP receiverも有効化しておき将来の拡張に備える

## 2026-08-09: Phase 2はGPUコンテナ基盤

- nvidia-container-toolkitでDockerからGPUを利用可能に（ECSのGPUタスク相当）
- dcgm-exporterは privileged + root + --gpus all が必要（DCGM host engineがnon-rootでは動作しないため）
- イメージは nvcr.io/nvidia/k8s/dcgm-exporter:latest（タグ付きはnot found、latestのみ取得可能）
- V100 16GB + GTX1060 6GB ともにDCGMで取得可能（温度/利用率/メモリ/電力/クロック）
- Prometheusの追加jobとして統合、GrafanaでGPUパネル5枚追加

## 2026-08-09: Phase 3はRuntimeコンテナ化（Go+Python同居 + Whisper分離）

- Go Runtime + Python VADは同一コンテナに同居（python_service.commandのsh -c機構をそのまま再利用、変更量最小化）
- Whisperのみ独立コンテナ（nvidia/cuda runtime、GPUパススルー、V100 small/cuda/float16）
- ビルドコンテキストはlocal-ai-companion、Dockerfileは.infra_runtime/に配置（gitignore）、infra側にも同一ファイルを保持
- 設定はconfig.docker.jsonでhost.docker.internal経由でOllama/VOICEVOX、whisperサービス名でSTT連携
- ヘルスチェック: runtime /healthz、whisper /health、depends_onで順序制御
- ホストsystemdはdisable、再起動テスト通過

## 2026-08-09: Phase 4はPortalのみ移行

- Portalはstatelessで移行コスト最小、HubをLubuntu :8080に集約
- Viewers/comfyui-console/genimg-apiはDesktop 83G等のデータ紐付けや利用頻度からPhase 4では見送り、需要に応じてPhase 4bで検討
- PortalはThinkPad上のViewersをIP直指定で参照（HERMES_API_URL=192.168.12.112:8642同様）、Viewers移行後にURL切替予定
- ビルドコンテキストはportal、Dockerfileは.infra_portal/に配置（gitignore）、infra側にも保持
