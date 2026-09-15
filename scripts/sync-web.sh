#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/server/internal/webembed/static"
mkdir -p "$DEST/css" "$DEST/js" "$DEST/fonts" "$DEST/img"
cp "$ROOT/web/index.html" "$ROOT/web/release.html" "$ROOT/web/status.html" "$ROOT/web/setup.html" "$DEST/"
cp "$ROOT/web/css/aesms.css" "$DEST/css/"
cp "$ROOT/web/js/"*.js "$DEST/js/"
cp "$ROOT/web/fonts/"* "$DEST/fonts/" 2>/dev/null || true
cp "$ROOT/web/img/"* "$DEST/img/" 2>/dev/null || true
rm -f "$DEST/css/t9.css" "$DEST/js/t9.js" "$DEST/img/t9-mark.png" "$DEST/img/t9-512.png"
echo "synced web/ -> server/internal/webembed/static/"
