#!/usr/bin/env python3
"""
addr-server.py — optional address-discovery service.

Serves the CURRENT tunnel/API URL (the contents of URL_FILE) as plain
text over HTTP. Bind it to a PERMANENT address the phone can always reach
(e.g. a Tailscale IP), and set ADDR_DISCOVERY_URL in config.sh to
http://<that-address>:<PORT>. The app reads it on launch so a CHANGING
tunnel URL self-heals without rebuilding the APK.

Why this exists: a free Cloudflare quick tunnel gets a RANDOM URL that
changes on every restart. Reading a few dozen bytes over a permanent
(even if slow) channel to learn the current fast URL combines the best of
both. See docs/REMOTE-ACCESS.md.

Run:  PORT=8749 URL_FILE=~/.hermes-tunnel-url.txt ./addr-server.py
"""
import http.server, socketserver, os

URL_FILE = os.path.expanduser(os.environ.get("URL_FILE", "~/.hermes-tunnel-url.txt"))
PORT = int(os.environ.get("PORT", "8749"))

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            url = open(URL_FILE).read().strip()
        except Exception:
            url = ""
        body = url.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass  # quiet

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        httpd.serve_forever()
