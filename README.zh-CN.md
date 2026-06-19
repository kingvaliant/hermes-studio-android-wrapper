[English](README.md) | **中文**

# Hermes Studio → 安卓（瘦客户端封装）

把 [Hermes Studio](https://github.com/EKKOLearnAI/hermes-studio) 的 Web 界面
封装成一个点开即用的**安卓 App**——一个基于 [Capacitor](https://capacitorjs.com/)
的轻量 WebView 壳，**把前端打进 APK**（首屏秒开），同时连接你的**远程 Hermes
服务器**取实时数据。

你得到的是：一个 App 图标、长期保持登录、移动端排版、无需开浏览器、无需反复
认证——而且手机上不用跑任何服务器。

> 本项目封装的是上游桌面/Web 项目
> [`EKKOLearnAI/hermes-studio`](https://github.com/EKKOLearnAI/hermes-studio)
> 的 **Web 界面**。它不 fork、不修改上游，只是把已构建好的前端重新打包。

---

## 为什么要"把前端打进 APK"，而不是让 WebView 直接指向服务器？

一个朴素的 WebView 直接加载 `https://你的服务器/`，每次冷启动都要下载约
1.5 MB 的 JS。在又慢又抖的远程链路上，首屏可能要等好几秒。

本封装改为**把构建好的前端拷进 APK**，从 `https://localhost` 本地加载。首屏
即本地 = 秒开。只有实时 API 调用（切换会话、历史、同步、websocket）才走远程
服务器。前端本身支持通过 `localStorage` 的 `hermes_server_url` 键配置 API 地址，
因此前后端是干净解耦的。

```
┌─────────────────────────── 安卓手机 ───────────────────────────┐
│  APK                                                          │
│   • 前端打进 APK，从 https://localhost 本地加载（秒开）          │
│   • localStorage.hermes_server_url ──► REMOTE_API（你的服务器） │
└───────────────────────────────┬───────────────────────────────┘
                                 │  实时 API / websocket
                                 ▼
                    你运行中的 Hermes 服务器（:8748）
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（英文）。

---

## 快速开始

### 一次性设置
1. **安装构建工具**（本机）：Node.js + npm、JDK 21、Android SDK，以及
   `adb`（可选，用于安装）。macOS：`brew install node openjdk@21`，SDK 用
   Android Studio 安装。
2. **创建一次 Capacitor 工程**（它承载安卓 Gradle 工程）：
   ```bash
   mkdir hermes-android && cd hermes-android
   npm init -y
   npm install @capacitor/core @capacitor/cli @capacitor/android
   npx cap init "Hermes" "com.example.hermesclient" --web-dir=www
   mkdir www && echo "placeholder" > www/index.html
   npx cap add android
   ```
   然后用本仓库的 `android/capacitor.config.json` 覆盖生成的那个
   （把 `appId`/`appName` 改成与 `config.sh` 一致）。
3. **配置**：
   ```bash
   cp config.example.sh config.sh
   $EDITOR config.sh        # 设置 STUDIO_DIST、REMOTE_API、CAP_PROJECT、APP_ID...
   ```

### 构建（每次 Hermes Studio 升级后重跑）
```bash
./build.sh
```
脚本会：拷取最新前端 → 注入你的 API 地址 → 修补两处写死的 auth 请求（本地加载
必需）→ 同步进 Capacitor 工程 → 跑 `gradle assembleDebug` →（可选）adb 安装。

### 服务器端（一次）
在 Hermes 服务器上设置 CORS，放行本地加载的 App：
```
CORS_ORIGINS=https://localhost,capacitor://localhost,http://localhost
```
由于 App 页面来源**永远**是 `https://localhost`，**即使你的远程 API 地址变化，
这个列表也不用改**。改完重启服务器。

---

## 让手机够到服务器

`REMOTE_API` 就是"手机如何访问你的 Hermes 服务器"。从简到繁的选项，完整权衡见
[docs/REMOTE-ACCESS.md](docs/REMOTE-ACCESS.md)（英文）：

| 方式 | 手机需同 WiFi？ | 需公网 IP？ | 说明 |
|---|---|---|---|
| **局域网 IP** | 是 | 否 | 最简单；仅同网络可用 |
| **Cloudflare 快速隧道** | 否 | **否** | 免费、可穿透 NAT、**地址会变**（隧道脚本 + 地址自动发现解决） |
| **Tailscale / mesh VPN** | 否 | 否 | 稳定的虚拟内网 IP；中继可能绕境外、增加延迟 |
| **命名隧道 / 自有域名** | 否 | 否 | 稳定公网地址；需要一个（便宜的）域名 |

对于**蜂窝流量 / 异地网络**且**零成本、无公网 IP**的场景，推荐用内置的
Cloudflare 隧道脚本（`scripts/tunnel/`）。它唯一的小毛病——地址重启会变——由可选的
**地址自动发现**功能解决（见 REMOTE-ACCESS）。

---

## 仓库结构
```
build.sh                     一条命令重新打包（幂等）
config.example.sh            拷成 config.sh 后编辑
android/
  MainActivity.java          瘦客户端壳（工具栏、地址切换、自动发现）
  capacitor.config.json      Capacitor 配置模板
scripts/tunnel/
  tunnel-start.sh            Cloudflare 快速隧道 + 把地址写入文件
  addr-server.py             可选：返回当前地址，供自动发现
  launchd/                   macOS LaunchAgent + Linux systemd 单元
docs/
  ARCHITECTURE.md            本地加载拆分的原理（英文）
  REMOTE-ACCESS.md           LAN / 隧道 / VPN / 域名 权衡 + 自动发现（英文）
  TROUBLESHOOTING.md         常见故障与修复（英文）
```

---

## 致谢与许可
- 上游 Web 界面：[`EKKOLearnAI/hermes-studio`](https://github.com/EKKOLearnAI/hermes-studio)。
- 本封装按 MIT 许可提供（见 `LICENSE`）。它不重新分发 Hermes Studio 前端——
  APK 由你从自己安装的副本构建。
