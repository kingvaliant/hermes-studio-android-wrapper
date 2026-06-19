# Architecture

## The problem
A WebView pointed straight at `https://your-server/` re-downloads the whole
single-page-app bundle (~1.5 MB) on every cold start. Over a remote link that
is slow or jittery, the first paint can take many seconds. Rebuilding or
"warming up" the app does not help — the bytes still have to cross the network.

## The split: local frontend, remote API
The Hermes Studio frontend is a static SPA whose API base URL is configurable
at runtime. It resolves the base in this priority order:

1. a preview/embedded override (not used here)
2. a desktop-shell injection (not present in a plain WebView)
3. **`localStorage.hermes_server_url`** ← this is what we set
4. empty → same-origin

So we:

1. **Bundle the built frontend into the APK** and load it from `https://localhost`
   (Capacitor `webDir: www`, `androidScheme: https`). First screen = local =
   instant, regardless of network.
2. **Set `localStorage.hermes_server_url`** to the remote server. All live API
   calls and the websocket then go to the remote server.

```
APK (https://localhost, instant)
   │  localStorage.hermes_server_url = REMOTE_API
   ▼
remote Hermes server  ── live API + websocket
```

## What `build.sh` does, step by step
1. **Copy** the latest frontend `dist/client` from your installed Hermes Studio
   (so re-running after an upgrade always ships the current UI).
2. **Inject** a tiny script at the top of `index.html` that seeds
   `localStorage.hermes_server_url` with your `REMOTE_API` on first run.
3. **Patch two hard-coded auth fetches.** Most requests go through the
   frontend's base-url wrapper (which prepends the configured base and adds the
   `Authorization: Bearer` header). But `/api/auth/status` and `/api/auth/login`
   are called with a **bare relative path** `fetch("/api/auth/...")` that does
   **not** use the wrapper. Under local-load those hit `https://localhost` and
   return the HTML shell, so the JSON parse fails with
   `Unexpected token '<', "<!doctype"...`. The script rewrites them to prepend
   the detected base function. (The function name is minified; the script tries
   three detection strategies and aborts with guidance if it can't find it — a
   future frontend refactor may need the patterns updated.)
4. **Sync** the dist into the Capacitor project's `www/`, drop macOS
   `._*`/`.DS_Store` cruft, run `npx cap sync android`.
5. **Build** `gradle assembleDebug`.
6. **Collect** (and optionally `adb install -r`) the APK.

## MainActivity responsibilities
- Loads the bundled page (Capacitor default — **no** remote `loadUrl`).
- Persists cookies (long-lived login) and routes downloads to the system
  DownloadManager.
- **Warm-up**: opens a few TCP connections to the API host on launch/resume so
  the first real request is faster.
- **Toolbar**: a small top-center floating bar with refresh + a gear that lets
  you switch the API URL at runtime (no rebuild). Layout pitfalls that took
  iteration to get right:
  - add the bar **after** the WebView lays out (`root.post(...)`) and
    `bringToFront()` + high `elevation`, or the WebView covers it;
  - size everything in **dp** (density-scaled px) or it's invisibly tiny on
    high-DPI screens;
  - sit flush at the top with `topMargin = dp(2)` and **do not** add a
    status-bar-height offset, which pushes it into a visible "second row".
- **Optional address auto-discovery** (see REMOTE-ACCESS.md): on launch, read
  the current API URL from a permanent endpoint and self-heal a rotating URL.

## CORS — why it needs zero maintenance
The page origin is **always** `https://localhost`. So the server's
`CORS_ORIGINS` only ever needs `https://localhost` (+ capacitor/http variants),
**no matter how the remote API URL changes**. A rotating tunnel URL is never the
`Origin`, so it never has to be added to CORS. (This is only true for the
local-load design here; a remote-load app would make the server URL the Origin.)
