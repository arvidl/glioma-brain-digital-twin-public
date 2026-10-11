#!/usr/bin/env bash
# Serve the presentation from this laptop so the talk runs without internet.
#
#   bash presentation/present_offline.sh            # serve (renders first if needed)
#   bash presentation/present_offline.sh --render   # force a fresh render, then serve
#   PORT=8080 bash presentation/present_offline.sh  # use another port
set -euo pipefail

cd "$(dirname "$0")"
PORT="${PORT:-8000}"
URL="http://localhost:${PORT}/"

if [[ "${1:-}" == "--render" || ! -f _site/index.html ]]; then
    command -v quarto >/dev/null || { echo "Quarto is required to render: https://quarto.org" >&2; exit 1; }
    quarto render
fi

# Hyperlinks to papers are fine offline; scripts, styles and media must be local.
external=$(grep -Eoh "(src=|mathjax: )[\"']https?://[^\"']+" _site/index.html _site/assets/interactive/*.html | sort -u || true)
if [[ -n "$external" ]]; then
    echo "WARNING: these resources load from the internet and will fail offline:" >&2
    echo "$external" >&2
fi

if command -v lsof >/dev/null && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use. Try: PORT=8080 bash $0" >&2
    exit 1
fi

(sleep 1; open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null || true) &
echo "Presenting at $URL  (press Ctrl+C to stop)"
exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory _site
