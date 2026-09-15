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
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/aesmsd ./cmd/aesmsd

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata wget \
  && adduser -D -H -u 10001 aesms
USER aesms
WORKDIR /data
COPY --from=build /out/aesmsd /usr/local/bin/aesmsd
ENV AESMS_LISTEN=:8080 \
    AESMS_DATA=/data \
    AESMS_BASE_URL=http://127.0.0.1:8080
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/usr/local/bin/aesmsd"]
