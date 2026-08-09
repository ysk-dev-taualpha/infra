FROM golang:1.26-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/gallery .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/gallery /app/gallery
COPY data/ /app/data/
COPY internal/handler/web/ /app/internal/handler/web/
WORKDIR /app
# Symlink for /home/yplic/Desktop -> /mnt/data so DB paths resolve
RUN mkdir -p /home/yplic && ln -sf /mnt/data /home/yplic/Desktop
EXPOSE 8765
CMD ["/app/gallery", "-addr", "0.0.0.0:8765"]
