#!/usr/bin/env bash
# ============================================================
# tunnel-start.sh — run a free Cloudflare quick tunnel pointing at your
# local Hermes server, and publish the assigned public URL to a file the
# build script can read. Works from behind NAT (no public IP, no domain).
#
# This is the recommended remote-access path when the phone is on a
# different network than the server (cellular / remote WiFi) and you don't
# want to pay for anything. See docs/REMOTE-ACCESS.md for alternatives and
# their capability/cost boundaries (LAN, Tailscale, named tunnel, etc).
#
# Requirements: cloudflared (https://github.com/cloudflare/cloudflared)
# Usage:        ./tunnel-start.sh            (foreground)
#               or install the launchd/systemd unit in ./launchd
# ============================================================
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-8748}"                 # Hermes server port
URL_FILE="${URL_FILE:-$HOME/.hermes-tunnel-url.txt}"
HIST_FILE="${HIST_FILE:-$HOME/.hermes-tunnel-history.log}"
CLOUDFLARED="${CLOUDFLARED:-cloudflared}"
LOG="${LOG:-$HOME/.hermes-tunnel.log}"

command -v "$CLOUDFLARED" >/dev/null 2>&1 || { echo "!! cloudflared not found. Install it first."; exit 1; }
: > "$LOG"

# Background watcher: scrape the assigned URL from the log, publish to file.
(
  prev=$(cat "$URL_FILE" 2>/dev/null || true)
  for _ in $(seq 1 90); do
    url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | head -1 || true)
    if [ -n "$url" ]; then
      echo "$url" > "$URL_FILE"
      echo "$(date '+%Y-%m-%d %H:%M:%S') $url" >> "$HIST_FILE"
      [ "$url" != "$prev" ] && echo "[tunnel] new public URL: $url"
      break
    fi
    sleep 1
  done
) &

exec "$CLOUDFLARED" tunnel --url "http://127.0.0.1:${LOCAL_PORT}" --no-autoupdate --logfile "$LOG"
