package __APP_ID__;

import android.os.Bundle;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.content.Context;
import android.text.InputType;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.webkit.CookieManager;
import android.webkit.WebView;
import android.webkit.WebSettings;
import android.webkit.DownloadListener;
import android.app.DownloadManager;
import android.net.Uri;
import android.os.Environment;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.net.URL;
import java.net.HttpURLConnection;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import com.getcapacitor.BridgeActivity;

/**
 * Thin-client shell for a Hermes Studio web frontend.
 *
 * Strategy: the frontend is bundled INTO the APK and loaded locally
 * (https://localhost), so the first screen opens instantly. Live API
 * calls go to a REMOTE server whose URL is stored in the WebView's
 * localStorage key `hermes_server_url` (the frontend reads it).
 *
 * The placeholders __REMOTE_API__ / __ADDR_DISCOVERY_URL__ are filled
 * by build.sh from config.sh. ADDRESS AUTO-DISCOVERY is optional: if
 * ADDR_DISCOVERY is non-empty, on launch the native layer fetches the
 * CURRENT api url from that permanent endpoint and updates localStorage,
 * so a rotating tunnel URL self-heals. (A web fetch can't do this from an
 * https page to an http endpoint — mixed-content is blocked — so it must
 * happen in the native layer.)
 */
public class MainActivity extends BridgeActivity {

    private static final String PREFS = "hermes_prefs";
    private static final String KEY_API = "api_server_url";
    // Last successfully discovered API url; used as a fallback when discovery
    // fails (e.g. you're not on the VPN) so an unchanged url still works offline-of-VPN.
    private static final String KEY_LAST_DISC = "last_discovered_url";

    // Filled by build.sh from config.sh:
    private static final String API_REMOTE = "__REMOTE_API__";
    // Permanent endpoint returning the current API url as plain text. Empty = disabled.
    private static final String ADDR_DISCOVERY = "__ADDR_DISCOVERY_URL__";

    private SharedPreferences prefs;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE);

        warmUp(); // pre-open the connection so the first API call is faster

        WebView webView = this.bridge.getWebView();

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(webView, true);

        WebSettings s = webView.getSettings();
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setJavaScriptEnabled(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);

        // Hand downloads to the system DownloadManager.
        webView.setDownloadListener(new DownloadListener() {
            @Override
            public void onDownloadStart(String url, String userAgent, String contentDisposition,
                                        String mimetype, long contentLength) {
                try {
                    DownloadManager.Request r = new DownloadManager.Request(Uri.parse(url));
                    r.setMimeType(mimetype);
                    r.addRequestHeader("User-Agent", userAgent);
                    r.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                    String fn = android.webkit.URLUtil.guessFileName(url, contentDisposition, mimetype);
                    r.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fn);
                    DownloadManager dm = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                    if (dm != null) dm.enqueue(r);
                } catch (Exception e) { e.printStackTrace(); }
            }
        });

        // Capacitor auto-loads the bundled www/index.html (do NOT loadUrl a remote page).
        discoverAddress(false); // optional auto-discovery on launch (no-op if disabled)
        addToolbar();
    }

    @Override
    public void onResume() {
        super.onResume();
        warmUp();
    }

    // Open a few TCP connections to the API host:port so the first real request is faster.
    private void warmUp() {
        final String target = prefs.getString(KEY_API, API_REMOTE);
        new Thread(() -> {
            try {
                URI u = URI.create(target);
                final String host = u.getHost();
                int p = u.getPort();
                if (p <= 0) p = "https".equalsIgnoreCase(u.getScheme()) ? 443 : 80;
                final int port = p;
                if (host == null) return;
                for (int i = 0; i < 3; i++) {
                    Socket sock = null;
                    try {
                        sock = new Socket();
                        sock.connect(new InetSocketAddress(host, port), 4000);
                    } catch (Exception ignore) {
                    } finally {
                        if (sock != null) try { sock.close(); } catch (Exception ignore2) {}
                    }
                }
            } catch (Exception e) { e.printStackTrace(); }
        }).start();
    }

    /**
     * Optional address auto-discovery.
     * force=false (on launch): silent; only overwrites if current url is empty
     *   or itself a discovered/tunnel url (won't clobber a manual choice).
     * force=true (user taps "Auto-discover"): always overwrite with latest;
     *   toast on failure / no-change.
     * On failure with force=false, falls back to KEY_LAST_DISC so an unchanged
     *   url keeps working even without the discovery endpoint reachable.
     */
    private void discoverAddress(final boolean force) {
        if (ADDR_DISCOVERY == null || ADDR_DISCOVERY.isEmpty()) return; // feature disabled
        new Thread(() -> {
            String discovered = null;
            try {
                URL u = new URL(ADDR_DISCOVERY);
                HttpURLConnection c = (HttpURLConnection) u.openConnection();
                c.setConnectTimeout(3000);
                c.setReadTimeout(3000);
                c.setRequestMethod("GET");
                if (c.getResponseCode() == 200) {
                    BufferedReader br = new BufferedReader(new InputStreamReader(c.getInputStream()));
                    String line = br.readLine();
                    br.close();
                    if (line != null) line = line.trim();
                    if (line != null && line.startsWith("http")) discovered = line;
                }
                c.disconnect();
            } catch (Exception ignore) {}

            if (discovered == null) {
                if (force) {
                    toast("Auto-discover failed (check VPN / server)");
                } else {
                    // Fall back to last known good url if current is empty/stale.
                    final String last = prefs.getString(KEY_LAST_DISC, "");
                    final String cur = prefs.getString(KEY_API, "");
                    if (!last.isEmpty() && !last.equals(cur) && cur.isEmpty()) {
                        applyUrl(last);
                    }
                }
                return;
            }
            final String url = discovered;
            prefs.edit().putString(KEY_LAST_DISC, url).apply();
            final String old = prefs.getString(KEY_API, "");
            if (url.equals(old)) {
                if (force) toast("Already up to date");
                return;
            }
            // Anti-clobber (launch only): if the user manually picked a different
            // url, don't overwrite. force=true bypasses this.
            if (!force && !old.isEmpty() && !old.equals(prefs.getString(KEY_LAST_DISC, ""))) {
                // old isn't a previously-discovered url -> treat as manual choice
                if (!old.equals(url)) return;
            }
            applyUrl(url);
        }).start();
    }

    private void toast(final String msg) {
        runOnUiThread(() -> android.widget.Toast.makeText(this, msg, android.widget.Toast.LENGTH_SHORT).show());
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    // Top-center floating toolbar: refresh + gear (switch API url).
    private void addToolbar() {
        final FrameLayout root = findViewById(android.R.id.content);

        android.widget.LinearLayout bar = new android.widget.LinearLayout(this);
        bar.setOrientation(android.widget.LinearLayout.HORIZONTAL);
        FrameLayout.LayoutParams barLp = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        barLp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        // Sit flush at the very top. Do NOT add a status-bar offset or the bar
        // gets pushed into a visible "second row".
        barLp.topMargin = dp(2);
        bar.setLayoutParams(barLp);
        bar.setElevation(dp(20));

        Button refresh = makeIconButton("\u21bb");
        refresh.setOnClickListener(v -> {
            warmUp();
            WebView w = this.bridge.getWebView();
            if (w != null) w.reload();
        });
        ((android.widget.LinearLayout.LayoutParams) refresh.getLayoutParams()).rightMargin = dp(6);
        bar.addView(refresh);

        Button gear = makeIconButton("\u2699");
        gear.setOnClickListener(v -> showSwitcher());
        bar.addView(gear);

        final android.widget.LinearLayout fbar = bar;
        // Add AFTER the WebView lays out, then bring to front, so it isn't covered.
        root.post(() -> {
            root.addView(fbar);
            fbar.bringToFront();
            root.invalidate();
        });
    }

    private Button makeIconButton(String glyph) {
        Button b = new Button(this);
        b.setText(glyph);
        b.setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, 18);
        b.setAlpha(0.45f);
        b.setBackgroundColor(0x88000000);
        b.setTextColor(0xFFFFFFFF);
        b.setPadding(0, 0, 0, 0);
        b.setMinHeight(0); b.setMinimumHeight(0);
        b.setMinWidth(0); b.setMinimumWidth(0);
        b.setGravity(Gravity.CENTER);
        b.setIncludeFontPadding(false);
        b.setElevation(dp(20));
        int sz = dp(36);
        android.widget.LinearLayout.LayoutParams lp =
            new android.widget.LinearLayout.LayoutParams(sz, sz);
        b.setLayoutParams(lp);
        return b;
    }

    private void showSwitcher() {
        String cur = prefs.getString(KEY_API, API_REMOTE);
        final boolean hasDisc = ADDR_DISCOVERY != null && !ADDR_DISCOVERY.isEmpty();
        final String[] items = hasDisc
            ? new String[]{ "Auto-discover (recommended)", "Use baked-in: " + API_REMOTE, "Custom URL\u2026" }
            : new String[]{ "Use baked-in: " + API_REMOTE, "Custom URL\u2026" };
        new AlertDialog.Builder(this)
            .setTitle("API server\nCurrent: " + cur)
            .setItems(items, (d, which) -> {
                if (hasDisc) {
                    if (which == 0) discoverAddress(true);
                    else if (which == 1) applyUrl(API_REMOTE);
                    else promptCustom();
                } else {
                    if (which == 0) applyUrl(API_REMOTE);
                    else promptCustom();
                }
            })
            .setNegativeButton("Cancel", null)
            .show();
    }

    private void promptCustom() {
        final EditText et = new EditText(this);
        et.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        et.setText(prefs.getString(KEY_API, API_REMOTE));
        new AlertDialog.Builder(this)
            .setTitle("Custom API URL")
            .setView(et)
            .setPositiveButton("Apply", (d, w) -> {
                String u = et.getText().toString().trim();
                if (!u.isEmpty()) applyUrl(u);
            })
            .setNegativeButton("Cancel", null)
            .show();
    }

    // Switch the API url: persist + write localStorage + reload.
    private void applyUrl(String url) {
        prefs.edit().putString(KEY_API, url).apply();
        warmUp();
        runOnUiThread(() -> {
            WebView w = this.bridge.getWebView();
            if (w != null) {
                String js = "try{localStorage.setItem('hermes_server_url','"
                    + url.replace("'", "\\'") + "');location.reload();}catch(e){location.reload();}";
                w.evaluateJavascript(js, null);
            }
        });
    }

    @Override
    public void onBackPressed() {
        WebView w = this.bridge.getWebView();
        if (w != null && w.canGoBack()) w.goBack();
        else super.onBackPressed();
    }
}
