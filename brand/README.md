# AeSMS.io brand

**Fetch-once messaging. Pure privacy but feels like SMS.**

| Token | Hex |
|-------|-----|
| Primary | `#0B0B0B` |
| Accent | `#0066FF` |
| Background | `#F4F4F4` |
| Secondary | `#9AA0A6` |

**Type:** IBM Plex Mono — Regular / Medium / Semibold (OFL)

**Mark:** `[/]` — brackets in primary (or white on dark), slash in accent.

| File | Use |
|------|-----|
| `aesms-mark.svg` | Vector mark |
| `aesms-mark.png` | Master mark 1024² (transparent, dark brackets) |
| `app-icon-dark.png` / `app-icon-light.png` | App icon tiles |
| `github-avatar.png` | GitHub avatar upload |
| `ci-board.png` | Full CI style board reference |
| `ci-lockup-dark.png` | Dark lockup + favicon reference |

Web runtime copies: `web/img/`. Regenerate rasters:

```bash
.tools/ci-venv/bin/python scripts/generate-brand-assets.py
./scripts/sync-web.sh
```

## GitHub avatar

Upload `brand/github-avatar.png` (or `app-icon-dark.png`) under profile/org **Settings → Profile picture**.
