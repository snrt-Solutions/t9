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

echo "==> build aesmsdev (device stand-in — no iPhone required)"
cd "$ROOT/server"
go build -o "$ROOT/aesmsdev" ./cmd/aesmsdev
echo "binary: $ROOT/aesmsdev"

cat <<'TXT'

Next (local loop, no phone):
  1. In the browser: create username + password, scan TOTP QR, confirm.
  2. Bind a fake device:
       export AESMS_URL=http://127.0.0.1:8080 AESMS_USER=yourhandle
       ./aesmsdev login
  3. Browser: Release page → Approve with TOTP.
  4. Then:
       ./aesmsdev send -to yourhandle -text "hello from aesmsdev"
       ./aesmsdev fetch

To run the real iOS app you still need full Xcode from the App Store
(this Mac only has Command Line Tools). After it installs:
  open ios/AeSMS.xcodeproj
  pick a Simulator, set Signing Team, Run.
  Server URL in the app: http://127.0.0.1:8080

TXT
