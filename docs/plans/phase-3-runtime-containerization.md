# Phase 3 詳細設計: Runtimeコンテナ化（Go Runtime + Python Service + Whisper）

- 親計画: `2026-08-09-migration-to-lubuntu.md`
- ステータス: Draft
- 担当: yplic + Muse Spark

## 目的

Lubuntu上のlocal-ai-companion（Go Runtime + Python VAD Service + faster-whisper）をDocker Composeでコンテナ化し、ECSライクな運用（compose = タスク定義、git pull + compose up = デプロイ）を確立する。systemd版と並走確認してから切替える。

## スコープ

- Go Runtime: Dockerfile（multi-stage build）→ compose service `runtime`
- Python Service: src/配下のVAD/会話コア（Go Runtimeが子プロセスで起動しているもの）を分離検討。Phase 3では最小変更でGo Runtimeコンテナ内に同居させつつ、将来的に独立コンテナ化できる設計にする
- faster-whisper: `services/whisper-server/` をコンテナ化（GPU対応、V100/cuda float16）
- Ollama / VOICEVOX は対象外（Ollamaはホストsystemd維持、VOICEVOXは既にcompose/otelとは別でdocker単体稼働）

## 非スコープ

- Ollamaのコンテナ化（モデルvolume 7GB超、Phase 4以降で検討）
- VOICEVOXのcompose統合（既に安定稼働中のためPhase 3では触らない）
- Portal/ビューアの移行（Phase 4）

## 現状アーキテクチャ

```
[Host: Lubuntu]
  local-ai-runtime (Go, systemd user) ─┬─ sh -c "PYTHONPATH=./src python3 ..." (Python VAD, :8092)
                                        ├─ http://127.0.0.1:11434 (Ollama, systemd)
                                        ├─ http://127.0.0.1:8093  (whisper-server, systemd user)
                                        └─ http://127.0.0.1:50021 (VOICEVOX, docker)
  config.json, conversation.db は ~/workspace/local-ai-companion/ 配下
```

Go Runtimeは `python_service.command` でPython子プロセスを起動し、BaseURLで通信する。Whisperは独立のsystemdサービス。

## 目標アーキテクチャ

```
[Host: Lubuntu]
  docker compose (compose/runtime/)
    runtime  (Go + Python同居、:8090) ─┬─ localhost:8092 (同コンテナ内Python)
                                        ├─ host.docker.internal:11434 (Ollama host)
                                        ├─ whisper:8093 (compose network)
                                        └─ host.docker.internal:50021 (VOICEVOX host)
    whisper  (faster-whisper, :8093, --gpus all, V100)

  Host services (維持):
    Ollama :11434 (systemd)
    VOICEVOX :50021 (docker)
```

Phase 3ではGoとPythonを同一コンテナに同居させることで、既存の `python_service.command` 機構をそのまま再利用し変更量を最小化する。Whisperのみ独立コンテナとしGPUパススルーを適用する。Python分離はPhase 3.5以降で検討。

ECSでいうと、runtimeコンテナがTask内のメインコンテナ、whisperがサイドカーに相当。

## コンポーネント

### runtime

- Dockerfile: `compose/runtime/Dockerfile`
  - builder: `golang:1.25` で `go build -o /app/local-ai-runtime ./cmd/local-ai-runtime`
  - runner: `python:3.12-slim`
    - `apt-get install -y --no-install-recommends libsndfile1` 等の最小依存
    - `pip install -r src/requirements` 的なPython依存（pyproject.tomlから）
    - `onnxruntime` はCPU版で十分（VADは軽量）
    - builderからバイナリをCOPY
    - `WORKDIR /app` に `src/`, `config.json`, `models/` を配置
  - 環境変数: `PYTHONPATH=/app/src`
  - 起動: `/app/local-ai-runtime --config /app/config.json`
- 重要: ホストのOllama/VOICEVOXへは `host.docker.internal` 経由でアクセス。composeで `extra_hosts: ["host.docker.internal:host-gateway"]` を設定
- config.jsonの差分: コンテナ用に `base_url` を `host.docker.internal` に書き換えた `config.docker.json` を用意するか、環境変数で上書き。Phase 3では `config.docker.json` を同梱

### whisper

- Dockerfile: `compose/runtime/Dockerfile.whisper` または既存のwhisper-serverを流用
  - base: `nvidia/cuda:12.4.0-runtime-ubuntu22.04`（cuda runtime、devel不要）
  - `pip install faster-whisper fastapi uvicorn python-multipart`
  - 環境変数: `WHISPER_MODEL=small`, `WHISPER_DEVICE=cuda`, `WHISPER_COMPUTE_TYPE=float16`
  - 起動: `python -m uvicorn services.whisper-server.server:app --host 0.0.0.0 --port 8093`
  - `runtime: nvidia` + `deploy.resources.reservations.devices: [{capabilities: [gpu]}]`
  - モデルキャッシュ: volume `whisper_cache:/root/.cache/huggingface`

### 共通

- network: `runtime_default`（composeデフォルト、runtime ↔ whisperはサービス名で解決）
- volumes: `whisper_cache`, `runtime_data`（conversation.db永続化）
- ports: `8090:8090` (runtime), `8093:8093` (whisper)
- restart: `unless-stopped`

## ファイル構成

```
compose/runtime/
├── docker-compose.yml
├── Dockerfile              # Go Runtime + Python同居
├── Dockerfile.whisper      # faster-whisper
├── config.docker.json      # コンテナ用config（host.docker.internal参照）
└── .dockerignore
```

## 検証手順

1. `cd ~/workspace/infra/compose/runtime && docker compose build`（またはLubuntuでbuild）
2. ホストのsystemd版を停止せず並走起動: コンテナ側は別ポート（例: 18090）で起動して疎通確認、またはホスト側を一時停止してコンテナを:8090で起動
3. `curl http://localhost:8090/health` or WebSocket疎通確認
4. `curl http://localhost:8093/health` でwhisper疎通
5. UnityまたはWebSocketクライアントからの会話フロー確認（STT → LLM → TTS）
6. 問題なければホストのsystemdを停止: `systemctl --user stop local-ai-runtime whisper-server`
7. `docker compose down && docker compose up -d` で再現確認
8. ThinkPadからの疎通: `curl http://192.168.12.123:8090/...`

## リスク・対策

| 項目 | 対策 |
|------|------|
| whisperのGPUメモリ (~1.5GB) とOllamaの競合 | V100 16GBなので余裕、GTX1060側は使わない |
| Python依存の差異（host vs container） | pyproject.toml/requirementsを忠実に再現、onnxruntimeはCPU版 |
| conversation.dbの永続化漏れ | volume mountで永続化、hostの既存DBを初期コピー |
| ホストのOllama/VOICEVOXへの疎通 | host.docker.internal + extra_hostsで解決 |
| ビルド時間 | Goのlayer cache、Pythonのpip cacheを活用 |

## 受け入れ条件

- [ ] `docker compose build` が成功する
- [ ] `docker compose up -d` でruntime + whisperが起動する
- [ ] `curl http://localhost:8090/health` 相当の疎通確認が取れる
- [ ] `curl http://localhost:8093/health` がokを返す
- [ ] WebSocket経由の会話フロー（STT→LLM→TTS）が動作する
- [ ] ホストのOllama/VOICEVOXと連携できる
- [ ] `docker compose down && docker compose up -d` で再現する

## 将来拡張

- Python Serviceを独立コンテナに分離（Go ↔ PythonをHTTPで分離、ECSのサイドカー完全分離）
- Ollamaを `ollama/ollama` イメージでコンテナ化（Phase 4以降）
- VOICEVOXを同一composeに統合
