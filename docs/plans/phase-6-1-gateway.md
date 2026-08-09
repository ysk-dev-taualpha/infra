# Phase 6-1 詳細設計: Gateway移行（Hermes Gateway → Lubuntu）

- 親計画: `2026-08-09-migration-to-lubuntu.md`, `phase-5-operations.md`
- ステータス: Draft
- Issue: #9

## 目的

ThinkPad上のHermes Gateway（Discord Bot + API Server :8642）をLubuntuへ移行し、単一運用基盤を完成させる。

## 現状

- ThinkPad: `~/.hermes/.env` に `DISCORD_BOT_TOKEN`, `API_SERVER_KEY` 等、`.hermes/config.yaml`, `sessions`, `memories` が存在。`hermes-gateway.service` が稼働中
- Lubuntu: `~/.hermes/` は存在するが `hermes` CLIのvenvなし。`DISCORD_BOT_TOKEN` 未設定

## 方針

- Lubuntuにhermes-agentをインストール（`install.sh` + `hermes setup`相当）
- `~/.hermes/` 配下の必要な設定・Secretsを選択的に移行（丸ごとコピーは避け、マージする）
- 移行時は並走を避ける（Discord Botは同一トークンで二重起動すると競合するため、ThinkPad側を停止してからLubuntu側を起動）
- Portal/他クライアントの `HERMES_API_URL` を `192.168.12.112:8642` → `192.168.12.123:8642` へ切替
- 移行後はThinkPad側gatewayはdisable

## 手順

1. Lubuntuにhermes-agentをインストール
2. ThinkPadから `~/.hermes/.env`（DISCORD_BOT_TOKEN等）と `~/.hermes/config.yaml` の差分をLubuntuへ反映（API_SERVER_KEYは既にローテーション済みの新キーを使用）
3. Lubuntuで `hermes gateway status` で疎通確認（Discord未接続でもAPI ServerがupすればOK）
4. ThinkPad gatewayを停止 → Lubuntu gatewayを起動
5. Portal（Lubuntu :8080）の `HERMES_API_URL` をLubuntu自身へ切替（`host.docker.internal:8642` or `192.168.12.123:8642`）
6. ブラウザでPortalのチャット、DiscordでのBot応答を確認
7. 問題なければThinkPad側gatewayをdisable

## 非スコープ

- Viewers/comfyui等の移行（別Issue #10-11）

## リスク

- Discord Botの二重起動は避ける（停止→起動の順序厳守）
- Secretsの漏洩（.envはgitignore、移行はscpで直接）

## 受け入れ条件

- [ ] LubuntuのGatewayが `systemctl --user status hermes-gateway` でactive
- [ ] `curl http://192.168.12.123:8642/v1/models` が新キーで200
- [ ] Portalのチャット（/api/chat）がLubuntu Gateway経由で応答する
- [ ] Discord BotがLubuntu Gatewayで応答する
- [ ] ThinkPad側gatewayは停止・disable
