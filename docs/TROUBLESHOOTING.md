# Troubleshooting

### Login page shows, but logging in fails with `Unexpected token '<', "<!doctype"...`
The frontend's `/api/auth/status` and `/api/auth/login` are called with a bare
relative path that isn't routed through the base-url wrapper, so under
local-load they hit `https://localhost` and get the HTML shell back. `build.sh`
step 3 patches these. If it printed *"could not detect base-url function name"*,
the frontend was minified differently than the three detection patterns expect:
```bash
# find the bundle and the base-url call shape:
grep -rl 'fetch("/api/auth/login"' /path/to/dist/assets/js/*.js
grep -oE '\$\{[A-Za-z]+\(\)\}/api' <that-bundle>.js   # find the BASE() function
```
Then patch the two `fetch("/api/auth/...")` calls to
`fetch(\`\${BASE()}/api/auth/...\`)` and re-run, or update the detection
patterns in `build.sh`.

### API calls fail with a CORS error
Set on the **server**:
```
CORS_ORIGINS=https://localhost,capacitor://localhost,http://localhost
```
and restart it. The app's origin is always `https://localhost`, so this is all
you need regardless of the API URL. Verify through your endpoint:
```bash
curl -s -X OPTIONS "<REMOTE_API>/api/auth/status" \
  -H "Origin: https://localhost" -H "Access-Control-Request-Method: GET" \
  -D - -o /dev/null   # expect 204 + Access-Control-Allow-Origin: https://localhost
```

### The toolbar buttons are invisible / tiny / pushed into a second row
These are the layout pitfalls handled in `MainActivity.java`:
- add the bar **after** layout via `root.post(...)` + `bringToFront()` + high
  `elevation`, or the WebView covers it;
- size in **dp**, not raw px, or it's microscopic on high-DPI screens;
- use `topMargin = dp(2)` and **no** status-bar offset, or it drops to a
  "second row".

### `adb install` fails with `INSTALL_FAILED_*` / `User rejected permissions`
Some OEM ROMs require an **on-screen confirmation** for `adb install`. Watch the
phone and approve, then re-run. Installing over a slow remote `adb` (e.g. over a
VPN) can also time out — prefer USB for the install step.

### App opens but is slow to switch chats / load history
That's the **transport**, not the app (the first screen is local and instant).
Measure the round-trip (see REMOTE-ACCESS.md "Measuring") and switch to a faster
path. Rebuilding won't help a transport problem.

### Cloudflare tunnel URL changed and the app can't connect
Quick-tunnel URLs rotate on restart. Either:
- open the gear → "Auto-discover" (if you set up address auto-discovery), or
- read the new URL (`cat ~/.hermes-tunnel-url.txt`) and set it via gear →
  "Custom URL", or
- re-run `build.sh` (it reads the current URL from the file) and reinstall.

### `cloudflared` connectivity pre-checks fail
Run `cloudflared tunnel --url http://127.0.0.1:8748 --no-autoupdate` directly and
read the CONNECTIVITY PRE-CHECKS table. If QUIC/UDP is blocked it falls back to
HTTP2/443 automatically; if even 443 to the edge is blocked, the network is
restricting outbound — try from a different network to confirm.

### Build can't find Java / Android SDK
Set `JAVA_HOME_OVERRIDE` and `ANDROID_HOME_OVERRIDE` in `config.sh`, or put
`java` (JDK 21) and the Android `sdkmanager`/`platform-tools` on your PATH.
