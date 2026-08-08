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
