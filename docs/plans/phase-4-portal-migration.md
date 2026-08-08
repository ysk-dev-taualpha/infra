# Phase 4 詳細設計: Portal移行（+ 残サービスの方針整理）

- 親計画: `2026-08-09-migration-to-lubuntu.md`
- ステータス: Draft
- 担当: yplic + Muse Spark

## 目的

ThinkPad上のHermes Hub Portal（:8080）をLubuntuのDocker Composeへ移行し、ダッシュボードの単一運用基盤を完成させる。残サービス（Viewers / comfyui-console / genimg-api）は移行コストに見合うか整理し、必要なもののみ段階移行する。

## 現状棚卸し（ThinkPad残留）

| サービス | 形態 | ポート | データ | 移行判断 |
|---------|------|--------|--------|---------|
| Portal | Go + systemd | 8080 | なし（stateless、web/* embed） | **Phase 4で移行** |
| image-gallery (xp3viewer) | Go + systemd | 8765 | Desktop 83G（comfyui_* png）、gallery_library.sqlite3 | 見送り（データがThinkPad Desktopに紐付く。Lubuntuへ83Gをrsyncするコストが高い。必要になればPhase 4b） |
| asmr-viewer | Go dashboard + scraper.py | 8787 | asmr.db 184K | 低優先（dbは小さいが単体で移行してもPortalからのリンク切れ対応が必要） |
| missav-viewer | Go dashboard + scraper.py | 8788 | missav.db 32K | 同上 |
| comfyui-console | Python FastAPI | 8100 | なし | 低優先（ComfyUI本体はWinPC 192.168.12.107にあり、ThinkPadはプロキシ役。Lubuntuに移しても本質変わらず） |
| genimg-api | Go | 8091 | fanbox-gen/outputs | 低優先（WinPC ComfyUIへのプロキシ、利用頻度低） |
| hermes-gateway | Python | 8642 | conversation等 | 対象外（Discord連携等の要再設定、ThinkPad維持） |

### 判断理由

- Portalはstatelessで最も移行コストが低く、移行効果が高い（HubダッシュボードをLubuntuに集約）
- Viewers/comfyui-console/genimg-apiは「軽いがデータがThinkPadに紐付く」か「利用頻度が低く緊急性なし」
- Desktop 83Gの全同期はネットワーク・時間コストが高く、Phase 4のスコープを膨らませるため見送り
- Portal移行だけでも「Lubuntuをメイン運用基盤にする」というPhase 4の主目的は達成できる

## 目標アーキテクチャ（Phase 4完了後）

```
[ThinkPad 192.168.12.112] — Viewers等は当面維持、Portalのみ停止
  xp3viewer :8765, asmrviewer :8787, missavviewer :8788, comfyui-console :8100, genimg-api :8091
  hermes-gateway :8642

[Lubuntu 192.168.12.123]
  compose/otel/    → otelcol + Prometheus + Grafana + dcgm-exporter (Phase 1-2済)
  compose/runtime/ → Go Runtime + Whisper (Phase 3済)
  compose/portal/  → Portal :8080 (本Phase) — 参照先URLは192.168.12.112のViewersを指すまま（LAN内疎通）
  VOICEVOX :50021, Ollama :11434 (host systemd/docker)
```

Portalのヘルスチェック先（services()内のURL）はThinkPadのIPのまま。Phase 4ではPortal自体だけをLubuntuへ移し、監視対象はThinkPad上のViewersを継続して見に行く形にする。将来Viewersを移行した際にURLを192.168.12.123へ切り替える。

## Portal移行詳細

### コード

- 変更なし（現行のportal/main.go + web/* をそのままビルド）
- 環境変数: `HERMES_API_URL=http://host.docker.internal:8642`（ThinkPadのgatewayを参照し続けるか、将来Lubuntu gatewayへ切替）
  - Phase 4では `HERMES_API_URL=http://192.168.12.112:8642` とし、明示的にThinkPadを指す（host.docker.internalはLubuntuホスト自身を指すため）
  - `CODEX_API_URL` は既に `http://192.168.12.107:8092` でWinPCを指しており変更なし

### Dockerfile

- `compose/portal/Dockerfile`
  - builder: `golang:1.26-bookworm` で `go build -o /app/portal .`
  - runner: `golang:1.26-bookworm` または `debian:bookworm-slim` + `ca-certificates`（ヘルスチェック先へのHTTPS疎通のため）
  - `web/` は `//go:embed web/*` でバイナリに内包されるため別途COPY不要だが、念のため含める
  - `EXPOSE 8080`

### docker-compose.yml

- `compose/portal/docker-compose.yml`
  - service `portal`: build from `compose/portal/Dockerfile`, `ports: ["8080:8080"]`, `restart: unless-stopped`
  - 環境変数: `HERMES_API_URL`, `HERMES_API_KEY`, `CODEX_API_URL`
  - `extra_hosts: ["host.docker.internal:host-gateway"]` は不要（ThinkPadをIPで直指定するため）
  - healthcheck: `curl -f http://localhost:8080/api/health` or `curl -f http://localhost:8080/`

### 検証手順

1. `cd ~/workspace/infra/compose/portal && docker compose build`
2. ThinkPadのPortalを一時停止せず、Lubuntu側を別ポート（8081）で起動して疎通確認（ポート競合回避の並走）
   - または一時停止して:8080で起動（ダウンタイム数十秒許容済み）
3. `curl http://192.168.12.123:8080/api/health` で全サービスのup/downが正しく表示されること
4. ブラウザで http://192.168.12.123:8080 にアクセス、ダッシュボードが表示されること
5. 問題なければThinkPadのportal.serviceを停止・disable
6. `docker compose down && docker compose up -d` で再現確認
7. OTel/runtime/hermes-gateway等への影響なしを確認

### ファイル構成

```
compose/portal/
├── docker-compose.yml
└── Dockerfile
```

Portal自体のソースは `~/workspace/portal` にあり、Lubuntuの `~/workspace/portal` へgit cloneまたはrsyncで同期してビルドコンテキストとする。composeのbuild contextを `~/workspace/portal` にする。

## 受け入れ条件

- [ ] `docker compose build` が成功する
- [ ] `curl http://192.168.12.123:8080/api/health` が200で各サービスの死活を返す
- [ ] ブラウザで http://192.168.12.123:8080 のHermes Hubが表示される
- [ ] OTel/runtime等の既存スタックに影響なし
- [ ] `docker compose down && docker compose up -d` で再現する

## 将来拡張（Phase 4b以降）

- Viewers移行時はDesktop 83Gの扱いを決める（rsync全量 or NFSマウント or 移行しない）
- comfyui-console/genimg-apiは需要に応じて移行（いずれもstatelessで容易）
- Portalのヘルスチェック先URLをLubuntuへ切替（Viewers移行後）
