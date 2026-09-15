#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ROOT}/.tools/go/bin:${PATH}"

echo "==> rebuild Docker mailbox"
cd "$ROOT/deploy"
docker compose up --build -d

echo "==> wait for health"
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/v1/health >/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8080/v1/info
echo

echo "==> open create-account page"
open "http://127.0.0.1:8080/" || true

echo "==> build t9dev (device stand-in — no iPhone required)"
cd "$ROOT/server"
go build -o "$ROOT/t9dev" ./cmd/t9dev
echo "binary: $ROOT/t9dev"

cat <<'TXT'

Next (local loop, no phone):
  1. In the browser: create username + password, scan TOTP QR, confirm.
  2. Bind a fake device:
       export T9_URL=http://127.0.0.1:8080 T9_USER=yourhandle
       ./t9dev login
  3. Browser: Release page → Approve with TOTP.
  4. Then:
       ./t9dev send -to yourhandle -text "hello from t9dev"
       ./t9dev fetch

To run the real iOS app you still need full Xcode from the App Store
(this Mac only has Command Line Tools). After it installs:
  open ios/T9.xcodeproj
  pick a Simulator, set Signing Team, Run.
  Server URL in the app: http://127.0.0.1:8080

TXT
