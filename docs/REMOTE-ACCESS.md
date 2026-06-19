# Remote access: getting the phone to your server

`REMOTE_API` in `config.sh` is simply **how the phone reaches your running
Hermes server**. The app doesn't care which mechanism you use — it just needs a
URL that resolves and is reachable from wherever the phone is.

This doc frames the options as **one necessary link in the same chain**:
*expose an HTTP(S) endpoint the phone can reach*. Pick the lightest option that
covers your situation; only move down the list if you actually need to.

## Decision order (lightest first)

### 1. Same WiFi → LAN IP
If the phone and the server are on the **same network**, just use the server's
LAN address:
```
REMOTE_API="http://192.168.1.50:8748"
```
Zero dependencies. Stops working the moment the phone leaves that network.

### 2. Different network, no public IP → Cloudflare quick tunnel (recommended free path)
When the phone is on cellular or a different WiFi and the server has **no public
IP** (typical home/office NAT), the simplest free option is an **HTTP reverse
tunnel**. The server dials **outbound** to a public edge, so inbound NAT / port
forwarding / firewall rules don't matter.

```bash
# install cloudflared, then:
LOCAL_PORT=8748 scripts/tunnel/tunnel-start.sh
# prints + writes ~/.hermes-tunnel-url.txt = https://<random>.trycloudflare.com
```
Set `REMOTE_API` to that URL (or let `build.sh` read it from
`TUNNEL_URL_FILE`). Keep it running with the launchd/systemd units in
`scripts/tunnel/launchd/`.

**Capability boundary / cost:**
- ✅ Free, no account, no domain, no public IP, works behind NAT.
- ⚠️ The quick-tunnel URL is **random and changes on every restart**. Solved by
  *address auto-discovery* (below) or by upgrading to a *named tunnel* (step 4).
- ⚠️ No uptime guarantee (it's a free convenience tier).
- ℹ️ The edge node may be in another region, so the server→edge leg can cross a
  border. For a single HTTP service this is usually fine; for a chatty,
  latency-sensitive workload measure it (see "Measuring" below).

### 3. Different network, want a stable private IP → Tailscale / mesh VPN
A mesh VPN (Tailscale, ZeroTier, headscale, EasyTier…) gives every device a
**stable private IP** that works from any network:
```
REMOTE_API="http://100.x.y.z:8748"     # the server's Tailscale IP
```
**Capability boundary / cost:**
- ✅ Stable address, encrypted, works across networks, free tier exists.
- ✅ Gives you a *whole virtual LAN*, not just one port — useful if you also
  want SSH/other services.
- ⚠️ When direct peer-to-peer ("hole punching") fails — common behind
  **symmetric NAT**, which most corporate networks use — traffic falls back to
  a **relay**. The vendor's nearest relay may be in another country, adding
  latency and jitter. You can run your own relay (e.g. a self-hosted DERP, or an
  EasyTier public node) to keep it in-region, but that's extra setup and usually
  needs a host with a public IP.
- ℹ️ Diagnose direct-vs-relay and NAT type with `tailscale netcheck` /
  `tailscale ping <peer>` before assuming the VPN is "the fast path".

> Mesh VPN vs. HTTP tunnel: if all you need is **one HTTP port** on the phone, a
> reverse tunnel (step 2) is usually the faster path to a working result and
> sidesteps NAT entirely. Reach for a mesh VPN when you want a general-purpose
> private network or a stable IP without a domain.

### 4. Want a stable PUBLIC URL → named tunnel / your own domain
Upgrade the quick tunnel to a **named tunnel** for a permanent address:
```
REMOTE_API="https://hermes.example.com"
```
**Capability boundary / cost:**
- ✅ Permanent URL, survives restarts, no auto-discovery needed.
- 💲 Needs a **domain** — a *one-time-per-year* purchase, **not a subscription**
  (it just expires if you don't renew; no silent recurring charge). Cheap TLDs
  are a few currency units/year. A registrar that sells at cost keeps
  registration == renewal (no "cheap first year, expensive renewal" trap).
- ✅ DNS + the tunnel itself are free; no inbound port needed (still outbound).
- ℹ️ Because traffic exits via the tunnel provider's edge, you typically don't
  need to expose or host anything publicly yourself.

---

## Address auto-discovery (make a rotating URL self-heal)

If you stay on the **free quick tunnel** (step 2) and don't want to buy a
domain, the only annoyance is the changing URL. Fix it by combining a
**permanent-but-maybe-slow** channel with the **changing-but-fast** tunnel:

1. Run `scripts/tunnel/tunnel-start.sh` — it writes the current URL to
   `~/.hermes-tunnel-url.txt`.
2. Run `scripts/tunnel/addr-server.py` bound to a **permanent address the phone
   can always reach** (e.g. a Tailscale IP). It serves the file's contents as
   plain text:
   ```bash
   PORT=8749 URL_FILE=~/.hermes-tunnel-url.txt scripts/tunnel/addr-server.py
   ```
3. Set `ADDR_DISCOVERY_URL` in `config.sh` to `http://<permanent-addr>:8749`
   and rebuild. On launch the app reads the current URL from there and updates
   itself — so a rotated tunnel URL **self-heals without a rebuild**.

**Why the native layer does the fetch:** the page is `https://localhost`; a web
`fetch()` to an `http://` discovery endpoint is **mixed-content and blocked** by
the WebView. The Android native layer (`HttpURLConnection`) has no such
restriction, so `MainActivity` performs the discovery.

**Behavior:**
- On launch: silent; only updates if the stored URL is empty or itself a
  previously-discovered URL (won't clobber a manual choice).
- Gear → "Auto-discover": forces a refresh to the latest URL.
- If discovery fails (e.g. the permanent channel is down), it falls back to the
  last known good URL — so an **unchanged** tunnel keeps working even without
  the discovery endpoint reachable.

> Note this still needs *some* permanent reachable endpoint. A mesh-VPN IP is a
> convenient free one. The only fully-self-owned alternative is a home/office
> connection with a public IP. Pick whichever you already have.

---

## Measuring (don't guess)
Before declaring any path "slow", measure the raw round-trip:
```bash
# from the phone (adb shell) or any client on the phone's network:
curl -s -o /dev/null -w "%{time_total}\n" <REMOTE_API>/health
```
Compare paths. If one adds ~0.5–1 s+ per round-trip and jitters, that's your
transport. Rebuilding the app won't change a transport number — only switching
the path will.
