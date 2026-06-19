# ============================================================
# config.sh — edit these for your environment, then run build.sh
# ============================================================
# This file is the ONLY place you should need to change.
# Copy config.example.sh -> config.sh and fill in your values.
# ------------------------------------------------------------

# --- Where the Hermes Studio web frontend (dist) lives ---
# The thin client bundles this frontend INTO the APK (loads from
# https://localhost), so the first screen opens instantly with no
# network download. Point this at the built client assets.
#
#   macOS desktop app:
#     /Applications/Hermes Studio.app/Contents/Resources/webui/dist/client
#   npm hermes-web-ui global install (example):
#     $(npm root -g)/hermes-web-ui/dist/client
#   from source checkout:
#     /path/to/hermes-studio/packages/web-ui/dist/client
STUDIO_DIST="/Applications/Hermes Studio.app/Contents/Resources/webui/dist/client"

# --- Remote API address the app talks to at runtime ---
# The bundled frontend is static; live API calls (switch chat, history,
# sync, websocket) still go to your running Hermes server. Set this to
# however the PHONE reaches that server. Pick ONE:
#
#   LAN (same WiFi):        http://192.168.1.50:8748
#   Tailscale (any net):    http://100.x.y.z:8748
#   Cloudflare Tunnel:      https://<name>.trycloudflare.com
#   your own domain:        https://hermes.example.com
#
# See docs/REMOTE-ACCESS.md for the trade-offs. If you run the optional
# tunnel helper, this can be auto-filled from TUNNEL_URL_FILE below.
REMOTE_API="http://192.168.1.50:8748"

# --- (Optional) Cloudflare quick-tunnel URL file ---
# If you use scripts/tunnel/, it publishes the current tunnel URL here.
# When this file exists and is non-empty, build.sh uses it as REMOTE_API.
# Leave as-is if you don't use the tunnel helper.
TUNNEL_URL_FILE="$HOME/.hermes-tunnel-url.txt"

# --- (Optional) Address auto-discovery endpoint ---
# A tiny HTTP service on a PERMANENT address (e.g. a Tailscale IP) that
# returns the CURRENT REMOTE_API as plain text. The app reads it on
# launch so a CHANGING tunnel URL self-heals without rebuilding.
# Empty string = feature disabled (the app just uses the baked-in URL).
# See docs/REMOTE-ACCESS.md "Address auto-discovery".
ADDR_DISCOVERY_URL=""

# --- Android app identity ---
APP_ID="com.example.hermesclient"
APP_NAME="Hermes"
APP_PKG_PATH="com/example/hermesclient"   # must match APP_ID with / instead of .

# --- CORS the Hermes server must allow ---
# A local-load app ALWAYS sends Origin: https://localhost, regardless of
# which REMOTE_API it calls — so this list never changes when the tunnel
# URL rotates. Set CORS_ORIGINS on the server side to this value.
CORS_ORIGINS_VAL="https://localhost,capacitor://localhost,http://localhost"

# --- Capacitor project location (created by `npx cap` once) ---
# Where the Android/Capacitor project lives. build.sh syncs the dist
# into it and runs gradle. See README "One-time setup".
CAP_PROJECT="$HOME/hermes-android"

# --- Output APK path ---
APK_OUT="$HOME/Downloads/HermesClient.apk"

# --- (Optional) adb serial to auto-install onto. Empty = skip install ---
ADB_SERIAL=""

# --- Android build toolchain (only needed if not on PATH) ---
# Leave empty to use whatever `java`/`gradle` are already configured.
JAVA_HOME_OVERRIDE=""
ANDROID_HOME_OVERRIDE=""
