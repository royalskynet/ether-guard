# M2 部署 checklist — 公司管控機實機驗證

> 本檔為「在真實目標機實跑才算數」的清單。本機 mini 已證明各無權限能力可用，但 MDM 情境不可靠猜測，須逐項在目標機確認。
> 背景：公司 MDM 管控 M2 Mac、無 admin、最高限制（TCC 全鎖 / Gatekeeper / 可能封 Telegram）。

## 法務前置（先於一切）
- [ ] 已告知公司 IT 想在管控機安裝「自行離開偵測＋警報」腳本，IT 同意／或確認此為使用者層不違反政策（見 SUPPLEMENT 職涯風險段）。IT 明確禁止則**本專案在此機終止**。

## S1 環境診斷（唯讀，不改系統）
```bash
profiles status -type enrollment          # 有無 MDM 管控
profiles list                             # 有無 PPPC/Gatekeeper/防火牆 profile
sw_vers
ping -c2 api.telegram.org               # 或 curl -m5 https://api.telegram.org/  → Telegram 是否被封
networksetup -listallhardwareports       # 找出真實 Wi-Fi 介面（非一律 en0）
system_profiler SPBluetoothDataType       # 確認藍牙已配對 AW/手機，看 RSSI 是否會輸出
fdesetup status                           # FileVault
defaults read MobileMeAccounts Accounts   # iCloud 登入
ls ~/Library/Caches/com.apple.findmy.fmipcore   # Find My 是否開啟
```

## S2 逐指令實跑（各能力是否真可用）
| 能力 | 驗證 |
|------|------|
| `pmset -g batt` | 回 AC Power / Battery Power |
| `ioreg -c IOHIDSystem | grep HIDIdleTime` | 回數值 |
| 鎖屏偵測 | `~/.eguard/bin/lockcheck` 輸出 0/1（鎖屏→1）；不可用時嘗試 Quartz，兩者皆不可用則記 unknown，不假定未鎖。|
| 音量強制 | `osascript -e 'set volume output volume 100' -e 'set volume without output muted'` 後 get volume settings 見 muted:false |
| afplay 警笛 | afplay 系統音檔實響 |
| 藍牙 RSSI 閾值 | system_profiler 讀 AW 真實 RSSI，校準 PRESENT/AWAY（預設 -60/-75）；RSSI `-999` 為 unknown；安全預設 `BT_UNKNOWN_IS_AWAY=0` 時不得自動武裝，只有管理者明確設為 `1` 才視為離開。|
| launchd 不被擋 | 跑 install.sh 註冊 LaunchAgent 後 `launchctl print gui/$UID/com.user.eguard` 顯示 state 非 blocked |

## S3 推播管道驗證
- Telegram 身分固定：在 `~/.hermes/.env` 新增專屬 `EGUARD_BOT_TOKEN`（可與既有 bot token 同值，但不得刪改其他 key）。
- 在 `~/.eguard/config.sh` 設 `EGUARD_BOT_TOKEN_KEY="EGUARD_BOT_TOKEN"`、固定 `EGUARD_CHAT_ID`、`EGUARD_EXPECT_BOT`。
- 執行 `source ~/.eguard/log.sh; source ~/.eguard/config.sh; source ~/.eguard/notify.sh; notify_selftest`，輸出的 username 必須等於 `EGUARD_EXPECT_BOT`。
- 刪除舊 `~/.eguard/chat_id` 後執行 `eguard test`：仍須送到同一 chat，且 log 不得出現 getUpdates fallback。
- Telegram 不通 → 改 iMessage（Automation TCC 可能鎖）或 webhook 兜底。

## S3.1 Wi-Fi 判定
- `WIFI_IF=""` 代表自動偵測；`g_wifi_if` 必須等於 `networksetup -listallhardwareports` 中 Wi-Fi 的 Device。
- Wi-Fi 是否連線只看 `ifconfig <介面>` 的 `status: active`，SSID 僅供 log 附註，不作觸發依據。
- `WIFI_CHECK_INTERVAL` 與 `WIFI_FAIL_STREAK` 必須同時生效；介面偵測不到為 unknown，只記 WARN、不觸發。

## S4 端到端劇本（裝好後）
1. 手錶戴著在桌前 → `eguard status` = DISARMED
2. 摘下 AW 離開 → 過 ARM_DELAY → ARMED（events.log 有 state->ARMED）
3. 賊動滑鼠 → TRIGGERED（螢幕警告＋say＋推播）
4. grace 過 → ALARMING（警笛循環＋音量拉滿＋推播＋鎖屏）
5. 走回坐定（手錶回）→ 自動 DISARMED，警報停

## S5 闔蓋最惡場景（誠實極限）
- 闔蓋瞬間：guard 睡眠前推送「⚠️ 闔蓋」+IP 定位（找得到毫秒縫先送）
- 之後硬極限：無 admin 擋不住 clamshell 睡眠 → 腳本凍結 → 依賴 FileVault + Find My 補位
- 文件誠實標示，不誇大

## 停損
- launchd 被 MDM 擋 → 降級純前景 `guard.sh`（cafesentry 模式，使用者 login item）
- Telegram 被封 → 純本機巨響＋鎖屏（推播退 iMessage/webhook）
- BSSID 遮罩 → IP 城市級定位（已知，不糾纏破解）
- 任何需 admin/TCC/繞 MDM → 停，不越合規紅線
