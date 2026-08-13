# Hermes Viewer Web コンテナ配備

- Status: Implemented
- Date: 2026-08-13
- App repository: https://github.com/ysk-ai-companion/hermes-viewer
- App specification: `specs/003-web-container-deployment/spec.md`

## 目的

Expo Web版Hermes ViewerをLubuntu `192.168.12.123`上でDocker管理し、LAN内の`http://192.168.12.123:8790`から利用可能にする。

## 構成

```text
Browser :8790
  └─ hermes-viewer-web (Nginx :80)
       ├─ /          Expo static export
       ├─ /healthz   Docker healthcheck
       └─ /gallery/  host.docker.internal:8765
```

- DockerfileはNode 22 builderとNginx runtimeのmulti-stage build。
- Web build時の`EXPO_PUBLIC_GALLERY_URL`は`/gallery`。
- APIはNginxを経由するためブラウザから見て同一オリジンとなる。
- `/gallery/`は`^~` prefix locationとし、`.png`などのローカル画像URLも静的ファイル用regex locationより優先してGalleryへ転送する。
- Gallery停止時はproxyだけが502となり、Webコンテナのhealthは維持する。
- secretは現時点で使用しない。将来必要な場合は`.env`で管理する。

## 初回セットアップ

```bash
git clone https://github.com/ysk-ai-companion/hermes-viewer.git ~/workspace/hermes-viewer
cd ~/workspace/hermes-viewer
git switch main

mkdir -p ~/workspace/hermes-viewer/.infra_web
cp ~/workspace/infra/compose/hermes-viewer/Dockerfile ~/workspace/hermes-viewer/.infra_web/Dockerfile
cp ~/workspace/infra/compose/hermes-viewer/nginx.conf ~/workspace/hermes-viewer/.infra_web/nginx.conf
cp ~/workspace/infra/compose/hermes-viewer/dockerignore ~/workspace/hermes-viewer/.dockerignore

cd ~/workspace/infra/compose/hermes-viewer
docker compose up -d --build
```

## 更新

```bash
cd ~/workspace/infra && git pull
cd ~/workspace/hermes-viewer && git pull

mkdir -p ~/workspace/hermes-viewer/.infra_web
cp ~/workspace/infra/compose/hermes-viewer/Dockerfile ~/workspace/hermes-viewer/.infra_web/Dockerfile
cp ~/workspace/infra/compose/hermes-viewer/nginx.conf ~/workspace/hermes-viewer/.infra_web/nginx.conf
cp ~/workspace/infra/compose/hermes-viewer/dockerignore ~/workspace/hermes-viewer/.dockerignore

cd ~/workspace/infra/compose/hermes-viewer
docker compose up -d --build
```

## 検証

```bash
docker compose config
docker compose ps
curl -f http://localhost:8790/healthz
curl -f http://localhost:8790/gallery/api/works
# ローカル作品の実在するwork IDと相対パスに置き換え、拡張子付き画像も確認する
curl -f -o /dev/null http://localhost:8790/gallery/image/<work-id>/<relative-image-path.png>
```

LAN内ブラウザで`http://192.168.12.123:8790`を開き、作品一覧、画像グリッド、全画面ビューアを確認する。

### 2026-08-13 ローカル画像404の修正

- 症状: Hitomi作品は表示できるが、ローカル作品の`.png`画像がWeb版だけHTTP 404になる。
- 原因: Nginxの静的ファイル用regex locationが通常の`/gallery/` prefix locationより優先され、GalleryへproxyせずWebコンテナ内のファイルを探索していた。
- 修正: Gallery locationを`location ^~ /gallery/`とし、拡張子付きURLを含む全Galleryリクエストをbackendへ転送する。
- 影響範囲: WebコンテナのNginx設定のみ。React NativeアプリとGallery backendの変更は不要。
- 検証: 修正前の本番proxyは同一PNGにHTTP 404、Gallery直通はHTTP 200。修正設定をNginx 1.28の一時コンテナで検証し、proxy経由でもHTTP 200かつ`image/png`になることを確認した。

### 2026-08-13 ローカル検証結果

- `docker compose config`: 成功
- `hermes-viewer-web:latest` image build: 成功
- 一時コンテナの`/`、`/healthz`: HTTP 200
- `/gallery/api/works`: HTTP 200、Gallery API直アクセスとresponse一致
- アプリのunit test 15件、TypeScript、ESLint、Expo Web export: 成功
- Lubuntu上のLANアクセスと自動復帰: 本番配備後に確認

## ロールバック

新imageのbuildが失敗した場合、既存コンテナは置換されない。既知の正常なGit commitへアプリとinfraを戻し、同じコピー・`docker compose up -d --build`手順で再配備する。
