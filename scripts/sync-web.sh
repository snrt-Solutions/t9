#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/server/internal/webembed/static"
mkdir -p "$DEST/css" "$DEST/js" "$DEST/fonts"
cp "$ROOT/web/index.html" "$ROOT/web/release.html" "$ROOT/web/status.html" "$DEST/"
cp "$ROOT/web/css/t9.css" "$DEST/css/"
cp "$ROOT/web/js/"*.js "$DEST/js/"
cp "$ROOT/web/fonts/"* "$DEST/fonts/"
echo "synced web/ -> server/internal/webembed/static/"
