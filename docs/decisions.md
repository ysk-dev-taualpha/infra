# Decisions

## 2026-08-09: infraリポジトリ新設と段階移行

- infraリポジトリを新設し、Lubuntu運用基盤をcomposeで管理する
- 一括移行せずPhase 1〜5で段階移行する
- 各Phaseは `docs/plans/*.md` で設計書駆動、Issue化してから実装

## 2026-08-09: Phase 1はOTel最小構成

- Phase 1ではhostmetricsのみ、GPUはPhase 2へ分離
- otelcolはprometheus exporterで:8889公開、Prometheusがscrapeするシンプル方式
- OTLP receiverも有効化しておき将来の拡張に備える
