# Phase 1 詳細設計: OTelスタック構築（otelcol + Prometheus + Grafana）

- 親計画: `2026-08-09-migration-to-lubuntu.md`
- ステータス: Draft
- 担当: yplic + Muse Spark
- 予定Issue: `infra: Phase 1 — OTelスタック構築`

## 目的

Lubuntu (192.168.12.123) 上にOpenTelemetry Collector + Prometheus + Grafanaの最小構成を構築し、ホストメトリクス（CPU/メモリ/ディスク/ネットワーク）をGrafanaで可視化する。学習目的を兼ねつつ、将来のGPU/全サービス監視の基盤とする。

## スコープ

- 対象: Lubuntu単体（ThinkPad/WinPCはPhase 5で追加検討）
- 対象メトリクス: hostmetrics（CPU, memory, disk, filesystem, network, load）
- 対象外: GPUメトリクス（Phase 2でdcgm-exporter追加）、ログ/トレース（将来検討）

## 構成図

```
[Host: Lubuntu]
  otelcol-contrib :4317(OTLP gRPC) :4318(OTLP HTTP) :8889(metrics) :13133(health)
       │ hostmetrics receiver
       │   → batch → prometheusremotewrite or prometheus exporter
       ▼
  Prometheus :9090  ← scrape otelcol :8889  または remote write 受信 :9090/api/v1/write
       ▼
  Grafana :3000  ← Prometheus datasource
       ▼
  Browser (http://192.168.12.123:3000)
```

シンプルさを優先し、Phase 1では **otelcolが自身のメトリクスを:8889でPrometheus exposition形式で公開し、Prometheusがそれをscrapeする** 方式を採用する。OTLP → Prometheus remote writeはPhase 1では必須としない（学習コストを抑える）。

将来的にOTLP remote writeへ移行する道も残すため、otelcol configはOTLP receiverも有効化しておく。

## コンポーネント

### otelcol-contrib

- イメージ: `otel/opentelemetry-collector-contrib:0.128.0`（時点のstable）
- config: `compose/otel/otelcol-config.yml`
- receivers: `hostmetrics` (collection_interval: 10s), `otlp` (grpc/http)
- processors: `batch`, `resourcedetection` (system)
- exporters: `prometheus` (endpoint 0.0.0.0:8889), `debug` (verbosity basic、開発時のみ)
- service pipelines: `metrics/hostmetrics → batch → prometheus`

### Prometheus

- イメージ: `prom/prometheus:v3.5.0`
- config: `compose/otel/prometheus.yml`
- scrape_configs:
  - `otelcol` → `otelcol:8889`
  - `prometheus` → `localhost:9090`（self）
- storage: volume `prom_data` (retention 15d)
- flags: `--enable-feature=otlp-write-receiver` はPhase 1では不要だが将来のためにコメントで残す

### Grafana

- イメージ: `grafana/grafana:12.1.0`
- provisioning: `compose/otel/grafana/provisioning/datasources/datasource.yml` (Prometheus)
- 初期ダッシュボード: `compose/otel/grafana/dashboards/host-metrics.json`（簡易: CPU, Memory, Disk, Load）
- 認証: 初期はadmin/admin、環境変数で変更可能
- volume: `grafana_data`

## ファイル構成

```
compose/otel/
├── docker-compose.yml
├── otelcol-config.yml
├── prometheus.yml
└── grafana/
    ├── provisioning/
    │   ├── datasources/datasource.yml
    │   └── dashboards/dashboard.yml
    └── dashboards/host-metrics.json
```

## docker-compose.yml 概要

- network: `infra` (他stackと共有可能な外部network、なければ作成)
- volumes: `prom_data`, `grafana_data`
- otelcol: `pid: host` は不要、hostmetricsは `/hostfs` をro mountして `root_path: /hostfs` で取得する方式を検討（コンテナ内の/procではなくホストの/procを見るため）。Phase 1ではホストの/procを直接読むため `volumes: - /proc:/hostfs/proc:ro` 等を設定。
- ポート公開: 9090, 3000, 8889, 13133 は `0.0.0.0` で公開（LAN内アクセス用）

## 検証手順

1. `cd ~/workspace/infra/compose/otel && docker compose up -d`
2. `curl http://localhost:13133` → otelcol health 200
3. `curl http://localhost:8889/metrics | head` → otelcol prometheus metrics確認
4. `curl http://localhost:9090/api/v1/targets | jq .data.activeTargets[].health` → "up"
5. `curl http://localhost:3000/api/health` → Grafana health
6. ブラウザで http://192.168.12.123:3000 にアクセス、Prometheus datasource確認、ダッシュボード表示
7. ThinkPadから `curl http://192.168.12.123:9090/-/healthy` と `curl http://192.168.12.123:3000/api/health` で疎通確認

## 非機能要件

- リソース: 3コンテナ合計でメモリ ~500MB以内を目安
- 永続化: prom_data, grafana_dataはvolumeで永続化、削除しても再作成可能
- 再起動: `restart: unless-stopped`

## 将来拡張

- Phase 2: dcgm-exporter追加、GPUメトリクスを同一Prometheusへ
- 将来: otelcolのOTLP receiverにLubuntu上の他サービス（Go Runtime等）からOTLPでメトリクス/ログを送信
- 将来: Loki追加でログ収集

## 受け入れ条件

- [ ] `docker compose up -d` で3コンテナが起動する
- [ ] Prometheus Targetsで otelcol が up
- [ ] Grafanaで hostmetrics（CPU/メモリ等）がグラフ表示される
- [ ] ThinkPadからLubuntuのGrafana/Prometheusにアクセスできる
- [ ] `docker compose down` / `up -d` で再現する
