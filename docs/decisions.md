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

## 2026-08-09: CPU温度はnode-exporterで収集

- OTel hostmetricsには温度scraperがない（cpu/load/memory/disk等のみ）
- node-exporter (quay.io/prometheus/node-exporter) をサイドカー追加し hwmon + thermal_zone collectorでCPU温度を取得
- Lubuntuでは k10temp のTctl/Tdie（pci0000:00_0000:00:18_3 temp1/temp2）がPrometheusで取得可能、Grafanaで可視化
- Portal healthcheckは /api/health が外部ヘルスチェックで5s timeoutするため / に変更しtimeout 10sに緩和

## 2026-08-09: Secretsローテーション（HERMES_API_KEY）

- 事象: `compose/portal/docker-compose.yml` にHERMES_API_KEY（= API_SERVER_KEY）が平文で含まれ、publicリポジトリにpushされた
- 対応: キーをローテーション（228f… → f5f1…）、composeからは `${HERMES_API_KEY}` 参照に変更、`.env`（gitignore）で管理、`.env.example` を追加
- 教訓: Secretsは`.env` + `.gitignore`で管理し、composeの環境変数は `${VAR}` 形式で間接参照する。publicリポジトリでは特に注意
- 旧キーはrevoked済みのため、git履歴に残っていても無効。履歴の書き換えは行わずローテーションで対応

## 2026-08-09: Grafanaアラート → Discord通知

- Grafana Contact Point: Discord webhook（`compose/otel/.env` の `DISCORD_WEBHOOK_URL`）
- ルール: GPU temp >80C (2m), CPU temp >75C (2m), Disk >85% (5m) — 全て severity=warning → Discordへ通知
- テスト: vector(1) で発火確認、通知が長文で届くことを確認後テストルールは削除

## 2026-08-10: ComfyUI移行 (V100, Lubuntu)

- WinPC (192.168.12.107:8188) からLubuntu (192.168.12.123:8188) へComfyUI本体を移行、V100 16GBで稼働
- モデル: realismByStableYogi_ponyV65, waiIllustriousSDXL_v170 (13GB) + LoRA 8種 (1.1GB) + controlnet 6.1GB をSamba一時共有でWinPCからNVMe ~/ComfyUI/models/ へ移管、HDD /mnt/data/ComfyUI/output は出力用
- ComfyUIコンテナ: nvidia/cuda:12.4.0-runtime + torch 2.4.1 + comfy-kitchen 0.2.20 (0.2.28はlist[int]型でtorch互換エラー) + ComfyUI 0.31.0、compose/comfyuiでGPUマウント、V100 sm70対応
- comfyui-console/genimgも compose/comfyuiへ集約、COMFY_URL=http://comfyui:8188 でLubuntu内通信、Portalは8188/8100をLubuntu参照に切替、UFW 8188/8100/8091許可
- 生成テスト: 512x512 19.9s, 832x1216 batch2 27.2sで正常、scheduler未指定でComfyUI validationエラーが出たためgenimg serve.goにScheduler追加で解消
- Sambaは移管後に停止・削除、UFW 445/139除去済み

## 2026-08-10: Grafanaアラート (Discord 3ch, 画像付き)

- ハードウェア: GPU temp 80C, CPU temp 75C, CPU usage 90% 5m, GPU util 90% 5m, GPU mem 90% 5m, Disk 85% 5m, HDD 85% 5m → hardware webhook
- コンテナ: cAdvisor/node/dcgmターゲットダウン → containers webhook
- 監視: prometheusダウン → monitoring webhook (流用)
- NoDataはOK扱い、classic条件B1本、値表示B0、Grafana renderer (remote :8082) + host-metrics-otelパネル id付与 + __dashboardUid__/__panelId__で画像添付、4秒グループ待機でテスト発火確認済み
