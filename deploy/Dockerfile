# syntax=docker/dockerfile:1
# Build from repo root: docker compose -f deploy/docker-compose.yml build

FROM golang:1.24-alpine AS build
WORKDIR /src
ENV GOTOOLCHAIN=auto
RUN apk add --no-cache ca-certificates git
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
COPY web/index.html web/release.html web/status.html web/setup.html ./internal/webembed/static/
COPY web/css/ ./internal/webembed/static/css/
COPY web/js/ ./internal/webembed/static/js/
COPY web/fonts/ ./internal/webembed/static/fonts/
COPY web/img/ ./internal/webembed/static/img/
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/t9d ./cmd/t9d

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata \
  && adduser -D -H -u 10001 t9
USER t9
WORKDIR /data
COPY --from=build /out/t9d /usr/local/bin/t9d
ENV T9_LISTEN=:8080 \
    T9_DATA=/data \
    T9_BASE_URL=http://127.0.0.1:8080
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/usr/local/bin/t9d"]
