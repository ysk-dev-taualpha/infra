FROM golang:1.26-bookworm AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
COPY web/ ./web/
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/portal .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/portal /app/portal
EXPOSE 8080
CMD ["/app/portal"]
