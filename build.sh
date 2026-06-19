#!/usr/bin/env bash
# ============================================================
# build.sh — repackage the Hermes Studio web frontend into a thin
# Android APK (frontend bundled, loads from https://localhost, API
# pointed at your remote server). Idempotent: re-run after every
# Hermes Studio upgrade to refresh the bundled frontend.
#
# Usage:   cp config.example.sh config.sh && edit config.sh
#          ./build.sh
#
# Requirements (all LOCAL — builds on this machine):
#   - bash, python3, perl, tar  (standard on macOS/Linux)
#   - Node.js + npm (for `npx cap sync`)
#   - JDK 21 + Android SDK (for gradle assembleDebug)
#   - adb (optional, only to auto-install)
#   - A Capacitor Android project already created (see README setup)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

[ -f config.sh ] || { echo "!! config.sh not found. Run: cp config.example.sh config.sh  then edit it."; exit 1; }
# shellcheck disable=SC1091
source config.sh

WORK="$(mktemp -d)/dist-build"; mkdir -p "$WORK"
trap 'rm -rf "$(dirname "$WORK")"' EXIT

# ---- Resolve the runtime API address ----
if [ -n "${TUNNEL_URL_FILE:-}" ] && [ -f "$TUNNEL_URL_FILE" ] && [ -s "$TUNNEL_URL_FILE" ]; then
  REMOTE_API="$(cat "$TUNNEL_URL_FILE")"
  echo "    [api] using tunnel URL from $TUNNEL_URL_FILE -> $REMOTE_API"
else
  echo "    [api] using REMOTE_API from config -> $REMOTE_API"
fi

echo "==> [1/6] Copy latest frontend dist from Hermes Studio"
[ -d "$STUDIO_DIST" ] || { echo "!! STUDIO_DIST not found: $STUDIO_DIST  (fix it in config.sh)"; exit 1; }
cp -R "$STUDIO_DIST"/. "$WORK"/
echo "    files: $(find "$WORK" -type f | wc -l | tr -d ' ')"

echo "==> [2/6] Inject default API address into index.html (localStorage.hermes_server_url)"
INDEX="$WORK/index.html"
if ! grep -q "hermes_server_url" "$INDEX"; then
  python3 - "$INDEX" "$REMOTE_API" "$ADDR_DISCOVERY_URL" <<'PY'
import sys
path, api, disc = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()
inject = (
    '\n  <!-- [thin-client] frontend loads locally; API points at remote server -->\n'
    '  <script>\n'
    '    (function(){try{\n'
    '      var DEFAULT_REMOTE = "%s";\n'
    '      var cur = localStorage.getItem("hermes_server_url");\n'
    '      if (cur === null || cur === "") localStorage.setItem("hermes_server_url", DEFAULT_REMOTE);\n'
    '    }catch(e){console.warn("set remote url failed:",e);}})();\n'
    '  </script>\n' % api
)
i = s.lower().find('<head>')
if i == -1:
    raise SystemExit('!! no <head> in index.html')
i += len('<head>')
open(path, 'w', encoding='utf-8').write(s[:i] + inject + s[i:])
print("    injected (default API = %s)" % api)
PY
else
  echo "    index.html already has injection, skipping"
fi

echo "==> [3/6] Patch hard-coded relative auth fetches (needed for local-load)"
# Some builds call fetch("/api/auth/status") and fetch("/api/auth/login",...)
# with a RELATIVE path that does NOT go through the base-url wrapper. Under
# local-load that hits https://localhost and fails ("Unexpected token '<'").
# Rewrite them to prepend the base function. The base function name is
# minified; we detect it with three fallbacks.
MAINJS=$(grep -rl 'fetch("/api/auth/login"' "$WORK"/assets/js/*.js 2>/dev/null | head -1 || true)
if [ -n "$MAINJS" ]; then
  # (1) ${XX()}/api   (2) ${e}/api with const e=XX()   (3) helper alias "X as <Base>"
  BASEFN=$(grep -oE '\$\{[A-Za-z]{1,4}\(\)\}/api' "$MAINJS" | head -1 | grep -oE '[A-Za-z]{1,4}\(\)' | sed 's/()//' || true)
  if [ -z "$BASEFN" ]; then
    VAR=$(grep -oE '\$\{[A-Za-z]{1,3}\}/api' "$MAINJS" | head -1 | grep -oE '[A-Za-z]{1,3}' | head -1 || true)
    [ -n "$VAR" ] && BASEFN=$(grep -oE "const ${VAR}=[A-Za-z]{1,4}\\(\\)" "$MAINJS" | head -1 | grep -oE '=[A-Za-z]{1,4}\(' | tr -d '=(' || true)
  fi
  if [ -z "$BASEFN" ]; then
    BASEFN=$(grep -oE '[A-Za-z]+ as Et' "$MAINJS" | head -1 | sed -E 's/ as Et//' || true)
  fi
  if [ -z "$BASEFN" ]; then
    echo "!! could not detect base-url function name in $(basename "$MAINJS")."
    echo "   Inspect manually: grep -oE '\\\$\\{[A-Za-z]+\\(\\)\\}/api' $MAINJS"
    echo "   Then patch the two fetch(\"/api/auth/...\") calls to fetch(\`\${BASE()}/api/auth/...\`)."
    exit 1
  fi
  echo "    base fn = ${BASEFN}()  bundle=$(basename "$MAINJS")"
  perl -i -pe "s{fetch\\(\"/api/auth/status\"\\)}{fetch(\`\\\${${BASEFN}()}/api/auth/status\`)}g" "$MAINJS"
  perl -i -pe "s{fetch\\(\"/api/auth/login\",}{fetch(\`\\\${${BASEFN}()}/api/auth/login\`,}g" "$MAINJS"
  LEFT=$(grep -c 'fetch("/api/auth' "$MAINJS" || true)
  echo "    remaining bare auth paths: $LEFT (want 0)"
  [ "$LEFT" = "0" ] || { echo "!! auth paths not fully patched; inspect $MAINJS"; exit 1; }
else
  echo "    no hard-coded auth/login fetch found (newer build may already be fixed), skipping"
fi

echo "==> [4/6] Sync MainActivity from template (keeps the toolbar + auto-discovery logic)"
MAIN_SRC="android/MainActivity.java"
MAIN_DST="$CAP_PROJECT/android/app/src/main/java/$APP_PKG_PATH/MainActivity.java"
if [ -f "$MAIN_SRC" ] && [ -d "$(dirname "$MAIN_DST")" ]; then
  # Fill template placeholders with config values, then copy in.
  sed -e "s|__APP_ID__|$APP_ID|g" \
      -e "s|__REMOTE_API__|$REMOTE_API|g" \
      -e "s|__ADDR_DISCOVERY_URL__|$ADDR_DISCOVERY_URL|g" \
      "$MAIN_SRC" > "$MAIN_DST"
  echo "    MainActivity synced -> $MAIN_DST"
else
  echo "    (MainActivity template or target dir missing; using project's existing MainActivity)"
fi

echo "==> [5/6] cap sync + gradle assembleDebug"
( cd "$CAP_PROJECT"
  rm -rf www && mkdir www && cp -R "$WORK"/. www/
  find www -name '._*' -delete; find www -name '.DS_Store' -delete || true
  npx cap sync android >/dev/null 2>&1
  cd android
  [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
  [ -n "${ANDROID_HOME_OVERRIDE:-}" ] && export ANDROID_HOME="$ANDROID_HOME_OVERRIDE"
  ./gradlew assembleDebug --no-daemon 2>&1 | tail -3
)

echo "==> [6/6] Collect APK"
mkdir -p "$(dirname "$APK_OUT")"
cp "$CAP_PROJECT/android/app/build/outputs/apk/debug/app-debug.apk" "$APK_OUT"
echo "    APK: $APK_OUT ($(du -h "$APK_OUT" | cut -f1))"

if [ -n "${ADB_SERIAL:-}" ] && command -v adb >/dev/null 2>&1; then
  echo "    Installing via adb -s $ADB_SERIAL (some phones need an on-screen confirm)..."
  adb -s "$ADB_SERIAL" install -r "$APK_OUT" || echo "    install rejected/failed; confirm on phone and retry."
else
  echo "    Install manually:  adb install -r $APK_OUT"
fi

echo ""
echo "Done. Reminder: set CORS_ORIGINS=$CORS_ORIGINS_VAL on the Hermes server and restart it."
