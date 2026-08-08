# syntax=docker/dockerfile:1
# Phase 3: Go Runtime + Python Service (VAD) 同居イメージ
FROM golang:1.25-bookworm AS builder
WORKDIR /src
# local-ai-companion のGoモジュールのみをコピーしてビルド
# infra/compose/runtime からビルドする想定: contextはlocal-ai-companionリポジトリ
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ ./cmd/
COPY internal/ ./internal/
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/local-ai-runtime ./cmd/local-ai-runtime

FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# Python依存
COPY pyproject.toml ./
COPY src/ ./src/
# 最小依存のみインストール（onnxruntime等）
RUN pip install --no-cache-dir -e . 2>&1 | tail -5
# prompts等
COPY prompts/ ./prompts/
# Goバイナリ
COPY --from=builder /out/local-ai-runtime /app/local-ai-runtime
# configは外部からvolumeで上書きするが、デフォルトも同梱
COPY config.json ./config.json
# シェルが必要（python_service.commandがsh -cを使うため）
RUN chmod +x /app/local-ai-runtime
EXPOSE 8090 8092
CMD ["/app/local-ai-runtime", "--config", "/app/config.json"]
