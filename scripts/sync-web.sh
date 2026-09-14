#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/server/internal/webembed/static"
mkdir -p "$DEST/css" "$DEST/js"
cp "$ROOT/web/index.html" "$ROOT/web/release.html" "$ROOT/web/status.html" "$DEST/"
cp "$ROOT/web/css/t9.css" "$DEST/css/"
cp "$ROOT/web/js/t9.js" "$DEST/js/"
echo "synced web/ -> server/internal/webembed/static/"
