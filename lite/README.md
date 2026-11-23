# EGuard Light

**Privilege-free, MDM-compliant anti-theft alarm for managed Macs** · 無權限合規防竊系統（v2 純 shell）

[English](#english) · [繁體中文](#繁體中文)

---

## English

A theft-deterrent alarm for Macs under **corporate MDM management, with no admin rights and the strictest lockdown** (TCC fully locked / Gatekeeper / Telegram possibly firewalled). **Zero TCC, zero admin, zero signed app** — it uses only commands and APIs already open to a normal user, pure bash/zsh + launchd.

> ⚠️ **Compliance line**: never crack TCC, never bypass MDM, never install anything needing admin, never fight corporate security. Ask your IT before deploying (see the legal-prerequisite section in `deploy-checklist.md`).

### What it does
- **Bluetooth-driven arm/disarm**: trusted device (Apple Watch recommended) leaves → auto **ARMED**; returns → frictionless auto-disarm.
- **Escalating warning**: someone moves the mouse / unplugs power / Wi-Fi drops / trusted Bluetooth absent → **TRIGGERED** (on-screen warning + voice + push + IP location) → after grace → **ALARMING** (looping siren + forced max volume + screen lock).
- **Disarm**: trusted Bluetooth returns, or unlock the screen — a clueless thief has neither.
- **Three push channels**: Telegram (primary) / iMessage (backup) / webhook (fallback), with offline spooling and retry.
- **Location**: IP city-level (no permission) + BSSID→Apple WPS block-level (conditional, usually masked) + Find My fallback (the only one that still reports after the lid is closed).
- **Health-check automation**: on start, checks Find My / FileVault / iCloud / Telegram reachability, one-tap jump to fix what's missing.
- **All-native UI**: osascript dialogs, no terminal black box; `eguard status/config/log` are all visual.

### Install
```bash
git clone https://github.com/royalskynet/EGuard-Light.git
cd EGuard-Light
./install.sh        # native-window guide: deploy → pair trusted device → bind push → health-check → register LaunchAgent
```

Before enabling the LaunchAgent, pin EGuard to one Telegram identity and recipient:

```bash
# ~/.hermes/.env (value stays local; never commit it)
EGUARD_BOT_TOKEN=<the token for the intended bot>

# ~/.eguard/config.sh
EGUARD_BOT_TOKEN_KEY="EGUARD_BOT_TOKEN"
EGUARD_CHAT_ID="<fixed numeric chat id>"
EGUARD_EXPECT_BOT="<expected bot username, without @>"
WIFI_IF=""                 # empty = auto-detect the Wi-Fi hardware port
WIFI_CHECK_INTERVAL="15"
WIFI_FAIL_STREAK="3"
```

When `EGUARD_CHAT_ID` is set, EGuard never calls `getUpdates` and never uses the `chat_id` cache. SSID text is not used for connectivity detection; link state comes from `ifconfig`, so Location Services permission is not required.

### Common commands
```bash
~/.eguard/eguard status   # state + health-check indicators
~/.eguard/eguard log      # view logs
~/.eguard/eguard arm / disarm
~/.eguard/eguard test     # send a test push
```

### Layout
```
~/.eguard/
  guard.sh       state-machine main loop
  config.sh      all tunables (generated from config.example.sh at install)
  notify.sh      three-channel push + retry queue
  locate.sh      IP location primary + BSSID conditional enhancement
  healthcheck.sh pre-flight health-check + missing-item guidance
  gui.sh         osascript dialog library
  log.sh         unified log fn (levels + masking + daily rotation)
  eguard         user command entry
  logs/          per-module daily files
  bin/lockcheck  lock-screen detector (compiled by swiftc)
```
Secrets (token / chat_id / MAC) are always read from outside at runtime, never committed.

### Honest limits
- **Lid-close + unplug worst case**: at the instant the lid closes, it races to push "lid-close alert + location"; after that, without admin it cannot stop clamshell sleep, the script freezes → relies on **FileVault (protects data) + Apple Find My (the only locator still reporting after sleep)**.

### Verified prior art / inspiration
`cafesentry`(Node) trigger/siren paradigm · `MacGuard`(Swift) RSSI hysteresis / anti-mute idea · `corelocationcli`(Swift) · `apple-corelocation-experiments`(Go)/`apple_bssid_locator`(Python) BSSID→WPS block-level · Apple Find My lid-close fallback.

Local mini acceptance: see `ACCEPTANCE.md`; on-device M2 verification: see `deploy-checklist.md`.

### License
MIT

---

## 繁體中文

針對 **公司 MDM 管控、無 admin、最高權限限制**（TCC 全鎖 / Gatekeeper / 可能封 Telegram）的 Mac 設計的防竊系統。**零 TCC、零 admin、零簽名 app**——只用一般使用者本就開放的命令與 API，純 bash/zsh + launchd。

> ⚠️ 合規紅線：不破解 TCC、不繞 MDM、不裝需 admin 的東西、不對抗公司資安。部署前請先問公司 IT（見 `deploy-checklist.md` 法務前置）。

### 它能做什麼
- **藍牙主導武裝/解除**：信任裝置（建議 Apple Watch）離開 → 自動 ARMED；回來 → 零摩擦自動解除。
- **分級升溫警告**：有人動滑鼠/拔電/Wi-Fi 斷 / 信任藍牙不在 → TRIGGERED（螢幕警告＋語音＋推播＋IP 定位）→ grace 過 → ALARMING（警笛循環＋強制音量拉滿＋鎖屏）。
- **解除**：信任藍牙回歸，或解鎖螢幕（不懂的竊賊兩條都拿不到）。
- **推播三管道**：Telegram（主）/ iMessage（備援）/ webhook（兜底），斷網自動落盤重試。
- **定位**：IP 城市級（不需權限）＋ BSSID→Apple WPS 街廓（條件增強，多半遮罩）+ Find My 補位（闔蓋睡後唯一）。
- **健檢自動化**：開機查 Find My / FileVault / iCloud / Telegram 連通，缺項一鍵跳轉引導。
- **全程原生視窗**：osascript 對話框，無終端黑框；`eguard status/config/log` 都可視化。

### 安裝
```bash
git clone https://github.com/royalskynet/EGuard-Light.git
cd EGuard-Light
./install.sh        # 原生視窗引導：部署→配對信任裝置→綁定推播→健檢→註冊 LaunchAgent
```

啟用 LaunchAgent 前，先把 EGuard 固定綁到單一 Telegram 身分與收件人：

```bash
# ~/.hermes/.env（值只留本機，禁止提交）
EGUARD_BOT_TOKEN=<指定 bot 的 token>

# ~/.eguard/config.sh
EGUARD_BOT_TOKEN_KEY="EGUARD_BOT_TOKEN"
EGUARD_CHAT_ID="<固定數字 chat id>"
EGUARD_EXPECT_BOT="<預期 bot username，不含 @>"
WIFI_IF=""                 # 空值＝自動偵測 Wi-Fi 硬體介面
WIFI_CHECK_INTERVAL="15"
WIFI_FAIL_STREAK="3"
```

設定 `EGUARD_CHAT_ID` 後，EGuard 不會呼叫 `getUpdates`，也不使用 `chat_id` 快取。連線判定改讀 `ifconfig` link state，不依賴 SSID 文字，因此不需要 Location Services 權限。

### 常用指令
```bash
~/.eguard/eguard status   # 查狀態＋健檢燈號
~/.eguard/eguard log      # 看 log
~/.eguard/eguard arm / disarm
~/.eguard/eguard test     # 發測試推播
```

### 結構
```
~/.eguard/
  guard.sh       狀態機主迴圈
  config.sh      全客製參數（安裝時由 config.example.sh 生成）
  notify.sh      三管道推播＋重試佇列
  locate.sh      IP 定位主＋BSSID 條件增強
  healthcheck.sh 前置健檢＋缺項引導
  gui.sh         osascript 對話框庫
  log.sh         統一 log 函式（分級＋遮罩＋日期輪替）
  eguard         使用者指令入口
  logs/          各模組日期分檔
  bin/lockcheck  鎖屏偵測小工具（swiftc 編譯）
```
secret（token/chat_id/MAC）一律 runtime 讀外面，不入 repo。

### 誠實限制
- 闔蓋＋拔電最惡場景：闔蓋瞬間搶送「闔蓋警報＋定位」後，無 admin 擋不住 clamshell 睡眠，腳本凍結 → 依賴 **FileVault 保資料 + Apple Find My 補位**（Find My 是闔蓋睡後唯一仍回報位置的）。

### 已查證輪子／靈感
`cafesentry`(Node) 觸發/警笛范式 · `MacGuard`(Swift) RSSI 遲滯/反靜音思路 · `corelocationcli`(Swift) · `apple-corelocation-experiments`(Go)/`apple_bssid_locator`(Python) BSSID→WPS 街廓 · Apple Find My 闔蓋補位。

本機 mini 驗收：見 `ACCEPTANCE.md`；M2 實機驗證：見 `deploy-checklist.md`。

### 授權
MIT
