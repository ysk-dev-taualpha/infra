# Phase 2 詳細設計: GPUコンテナ基盤（nvidia-container-toolkit + dcgm-exporter）

- 親計画: `2026-08-09-migration-to-lubuntu.md`
- ステータス: Draft
- 担当: yplic + Muse Spark

## 目的

Lubuntu (192.168.12.123, V100 16GB + GTX1060 6GB, driver 580) 上でDockerコンテナからGPUを利用可能にし、GPUメトリクスをPrometheus/Grafanaで可視化する。ECSのGPUタスク相当の運用基盤を確立する。

## スコープ

- nvidia-container-toolkit導入（aptリポジトリ追加、daemon.json設定、docker再起動）
- `docker run --gpus all nvidia/cuda:xx nvidia-smi` 疎通確認
- dcgm-exporterをcompose/otelスタックに追加し、Prometheusでscrape
- GrafanaにGPUパネル追加（温度、利用率、メモリ、電力）
- 既存OTelスタック（Phase 1）は維持、GPUはPrometheusの追加jobとして統合

## 非スコープ

- Runtime等のコンテナ化（Phase 3）
- Ollamaのコンテナ化（Phase 3以降で検討）

## 構成図

```
[Host: Lubuntu]
  Docker runtime: nvidia (via nvidia-container-toolkit)
       │
  compose/otel/
    otelcol      :8889  (hostmetrics) ─┐
    dcgm-exporter :9400 (GPU metrics) ─┤→ Prometheus :9090 → Grafana :3000
    prometheus   :9090                 │
    grafana      :3000                 ┘
```

## 手順

### 1. nvidia-container-toolkit導入

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
# 既存コンテナ（otelスタック、voicevox）は自動再起動（unless-stopped / restart always）
```

### 2. GPU疎通確認

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L
# 期待: Tesla V100 + GTX1060 が表示
```

### 3. dcgm-exporter統合

- イメージ: `nvcr.io/nvidia/k8s/dcgm-exporter:4.2.3-4.8.0` または `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.0`（V100対応の安定版）
  - 代替: `nvidia/dcgm-exporter`（Docker Hubミラー、存在すればこちらを優先）
  - いずれも `nvidia-smi` ベースではなくDCGM経由でメトリクスを:9400で公開
  - V100 / GTX1060 ともにDCGM対応（GTXは一部メトリクスがN/Aになる可能性あり、許容）
- compose/otel/docker-compose.yml に `dcgm-exporter` サービス追加:
  - `image: nvcr.io/nvidia/k8s/dcgm-exporter:4.2.3-4.8.0`
  - `runtime: nvidia` または `deploy.resources.reservations.devices` で `capabilities: [gpu]`
  - `ports: ["9400:9400"]`
  - `restart: unless-stopped`
- prometheus.yml に `dcgm-exporter:9400` job追加
- grafana/dashboards/host-metrics.json にGPUパネル追加（dcgmメトリクス）

### 4. 検証

- `curl http://localhost:9400/metrics | grep DCGM` でGPUメトリクス確認
- Prometheus Targetsで dcgm-exporter が up
- GrafanaでGPUパネルに値が表示されること
- ホストの `nvidia-smi` とdcgmメトリクス値の突合せ（温度、利用率、メモリ）
- 再起動耐性: `docker compose down && docker compose up -d` で再現

## ファイル変更

- `compose/otel/docker-compose.yml` — dcgm-exporterサービス追加
- `compose/otel/prometheus.yml` — dcgm-exporter scrape job追加
- `compose/otel/grafana/dashboards/host-metrics.json` — GPUパネル追加

## リスク・対策

| リスク | 対策 |
|--------|------|
| ngcログインが必要なイメージ | Docker Hubミラー `nvidia/dcgm-exporter` を優先、NGCは匿名pull可能か確認 |
| GTX1060で一部DCGMメトリクスがN/A | 許容、V100は全項目取得を期待 |
| docker再起動で既存コンテナが停止 | unless-stopped / restart alwaysで自動復帰、事前に `docker ps` で確認 |

## 受け入れ条件

- [ ] `docker run --gpus all nvidia/cuda:xx nvidia-smi -L` で2GPUが表示される
- [ ] dcgm-exporter :9400 でDCGMメトリクスが取得できる
- [ ] Prometheus Targetsで dcgm-exporter が up
- [ ] GrafanaでGPUメトリクスがグラフ表示される
- [ ] ThinkPadから :9400 / :9090 / :3000 にアクセスできる
- [ ] `docker compose down && docker compose up -d` で再現する
