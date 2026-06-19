# Hermes Studio → Android (thin-client wrapper)

Wrap the [Hermes Studio](https://github.com/EKKOLearnAI/hermes-studio) web
UI into a tap-to-open **Android app** — a thin [Capacitor](https://capacitorjs.com/)
WebView shell that **bundles the frontend into the APK** (so the first screen
opens instantly) while talking to your **remote Hermes server** for live data.

You get: an app icon, persistent login, mobile layout, no browser, no
re-authentication — without running any server on the phone.

> This project wraps the **web UI** of the upstream desktop/web project
> [`EKKOLearnAI/hermes-studio`](https://github.com/EKKOLearnAI/hermes-studio).
> It does not fork or modify it; it repackages the already-built frontend.

---

## Why "bundle the frontend", not just point a WebView at the server?

A naïve WebView that loads `https://your-server/` downloads ~1.5 MB of JS on
every cold start. Over a slow/!jittery remote link that can take many seconds.

This wrapper instead **copies the built frontend into the APK** and loads it
from `https://localhost`. The first screen is then **local = instant**. Only
live API calls (switch chat, history, sync, websocket) go to the remote server.
The frontend already supports a configurable API base via the `localStorage`
key `hermes_server_url`, so front-end and back-end are cleanly decoupled.

```
┌─────────────────────────── Android phone ───────────────────────────┐
│  APK                                                                 │
│   • frontend bundled, loads from  https://localhost   (instant)      │
│   • localStorage.hermes_server_url ──► REMOTE_API (your server)      │
└───────────────────────────────┬──────────────────────────────────────┘
                                 │  live API / websocket
                                 ▼
                    your running Hermes server  (:8748)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

---

## Quick start

### One-time setup
1. **Install build tools** (local machine): Node.js + npm, JDK 21, Android SDK,
   and `adb` (optional, for install). On macOS: `brew install node openjdk@21`
   and Android Studio for the SDK.
2. **Create the Capacitor project once** (this holds the Android Gradle project):
   ```bash
   mkdir hermes-android && cd hermes-android
   npm init -y
   npm install @capacitor/core @capacitor/cli @capacitor/android
   npx cap init "Hermes" "com.example.hermesclient" --web-dir=www
   mkdir www && echo "placeholder" > www/index.html
   npx cap add android
   ```
   Then copy this repo's `android/capacitor.config.json` over the generated one
   (adjust `appId`/`appName` to match your `config.sh`).
3. **Configure**:
   ```bash
   cp config.example.sh config.sh
   $EDITOR config.sh        # set STUDIO_DIST, REMOTE_API, CAP_PROJECT, APP_ID...
   ```

### Build (repeat after every Hermes Studio upgrade)
```bash
./build.sh
```
This copies the latest frontend, injects your API URL, patches the two
hard-coded auth fetches (needed for local-load), syncs into the Capacitor
project, runs `gradle assembleDebug`, and (optionally) installs via `adb`.

### Server side (once)
Set CORS on your Hermes server so the local-load app is allowed:
```
CORS_ORIGINS=https://localhost,capacitor://localhost,http://localhost
```
Because the app's page origin is **always** `https://localhost`, this list
**never changes** even if your remote API URL changes. Restart the server.

---

## Reaching the server from the phone

`REMOTE_API` is just "how the phone reaches your Hermes server". Options, from
simplest to most capable — full trade-offs in
[docs/REMOTE-ACCESS.md](docs/REMOTE-ACCESS.md):

| Path | Phone on same WiFi? | Public IP needed? | Notes |
|---|---|---|---|
| **LAN IP** | yes | no | simplest; only works on the same network |
| **Cloudflare quick tunnel** | no | **no** | free, works behind NAT, **URL rotates** (helper + auto-discovery solve this) |
| **Tailscale / mesh VPN** | no | no | stable private IP; relay may route abroad and add latency |
| **Named tunnel / own domain** | no | no | stable public URL; needs a (cheap) domain |

For the **cellular / different-network** case with **zero cost and no public
IP**, the included Cloudflare-tunnel helper (`scripts/tunnel/`) is the
recommended path. Its one rough edge — the URL changes on restart — is handled
by the optional **address auto-discovery** feature (see REMOTE-ACCESS).

---

## Repo layout
```
build.sh                     one-command repackage (idempotent)
config.example.sh            copy to config.sh and edit
android/
  MainActivity.java          thin-client shell (toolbar, url switcher, auto-discovery)
  capacitor.config.json      Capacitor config template
scripts/tunnel/
  tunnel-start.sh            Cloudflare quick tunnel + publish URL to a file
  addr-server.py             optional: serve current URL for auto-discovery
  launchd/                   macOS LaunchAgents + Linux systemd units
docs/
  ARCHITECTURE.md            how/why the local-load split works
  REMOTE-ACCESS.md           LAN / tunnel / VPN / domain trade-offs + auto-discovery
  TROUBLESHOOTING.md         common failures and fixes
```

---

## Credits & license
- Upstream web UI: [`EKKOLearnAI/hermes-studio`](https://github.com/EKKOLearnAI/hermes-studio).
- This wrapper is provided as-is under the MIT license (see `LICENSE`). It does
  not redistribute the Hermes Studio frontend — you build the APK from your own
  installed copy.
