# Shell-capable runner that reuses the official cloudflared binary.
# Official image is distroless (no /bin/sh), so we cannot wait on /data/cloudflare.token there.
FROM cloudflare/cloudflared:latest AS upstream
FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=upstream /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY deploy/cloudflared-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/cloudflared
ENTRYPOINT ["/entrypoint.sh"]
