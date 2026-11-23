# EGuard Light 開發日誌

無權限合規防竊系統（v2 純 shell）的開發進度記錄。

---

## 2026-08-15 — M2 實機驗證（S1 診斷 + S2 能力實跑，初始化產物完成）

在目標機（公司 MDM 管控 M2，macOS 26.2）依 `deploy-checklist.md` 推進。**全程零系統改動、零 TCC 觸發**，未註冊 LaunchAgent、未啟動 guard 主迴圈。

### S1 環境診斷（唯讀）實測

| 檢查項 | 結果 |
|---|---|
| MDM | Jamf 在校（jamf.newecosystem.tech，User Approved），無使用者級 configuration profile |
| macOS / Gatekeeper | 26.2 (25C56) / assessments enabled |
| Telegram | api.telegram.org 通（HTTP 302，未封）|
| FileVault / iCloud | On / skynetwalker@icloud.com 已登入 |
| Find My | fmipcore cache 無 → 可能未開 [待核] |
| 藍牙 | 5 台已配對且 RSSI 可讀（-50~-78）|
| 潛在阻塞① swiftc | CLI 已裝（swift 6.2.4）→ lock.swift 可編譯 |
| 潛在阻塞② Wi-Fi IF | en0 ✓ |

**情境分流：落在「全量部署」技術可行區**——MDM 未鎖使用者層、swiftc/藍牙/Telegram 齊備。

### S2 能力實跑（不碰 TCC）

可用：pmset 電源 ✓、HIDIdleTime ✓、lockcheck 鎖屏偵測 ✓（/tmp 編譯實跑輸出 0）、藍牙 RSSI＋信任裝置 ✓（劉湛的Apple Watch，MAC 已脫敏）、音量強制 ✓（set volume 不需 Automation TCC，已拉滿又還原）、IP 城市級定位 ✓、Telegram 推播 ✓（token 存在，值未讀）。

TCC 受限項（不硬破，安全預設關閉）：`LOCK_ON_ALARM`（System Events 鎖屏）、`NOTIFY_IMESSAGE`（Automation）、`LOCATE_WPS_ENABLED`（Location/BSSID 遮罩）。

### 初始化產物（已部署，未啟動）

模組複製至 `~/.eguard/` 並 chmod +x、`lockcheck` 編譯至 `~/.eguard/bin/`、組裝安全預設 `config.sh`（鎖屏/iMessage/BSSID 關，TRUSTED_MAC=Apple Watch，MAC 已脫敏）。**確認未註冊 LaunchAgent、未建立 state、未啟動**。

### 待辦（未做部分）

S3 真實推播綁定、S4 端到端劇本、S5 闔蓋搶跑、launchd 是否被 MDM 擋 —— 因**法務前置未定**與未獲啟動指示而暫緩，非技術受阻。初始化產物已就位，待 Ether 決定是否實跑。

---

## 2026-08-15 — 品牌統一

全專案更名為 **EGuard Light**：顯示文案（README 標題）+ 技術識別碼徹底改名——指令 `antitheft`→`eguard`、路徑 `~/.anti-theft/`→`~/.eguard/`、LaunchAgent label `com.user.antitheft`→`com.user.eguard`、變數 `ANTITHEFT_DIR`→`EGUARD_DIR`，含檔名 rename。無舊名殘留。已驗收邏輯不變，M2 部署時 plist 以新 label 註冊。

---

## 2026-08-14 — 立項到 v2 發布

### 需求演進

1. 起點：調研「離座防竊嚇阻」方案（巨響警報 + 藍牙感應 + webcam 連拍 + 手機推播）
2. 需求聚焦嚇阻導向（非鎖機導向）：警報 + 藍牙感應 + 連拍 + Telegram/iMessage 推播 + 觸發即上鎖
3. **關鍵轉折**：目標機是公司 MDM 管控 M2 Mac，無 admin。重估後分兩版：
   - **v1**（暫緩）：fork MacGuard 的 Swift native app，適合私人 Mac
   - **v2**（本專案）：純 shell + launchd，零 TCC / 零 admin / 零簽名 app，管控機唯一跑得起來的版本

### 為何是 v2（無權限路線）

假設 MDM 最高限制：TCC 全鎖、Gatekeeper 只允許核准 app、可能封 Telegram。此假設下 native app 啟動不了。改用一組「一般使用者本就開放」的 API：

| 能力 | 技術 | 需 TCC/admin |
|---|---|---|
| 偵測有人動機器 | `HIDIdleTime`（ioreg）| 否（繞過 Input Monitoring TCC 的核心招）|
| 巨響 + 蓋靜音 | `afplay` + `osascript set volume` | 否 |
| 拔電 / Wi-Fi 斷觸發 | `pmset -g batt` / `networksetup` | 否 |
| 藍牙感應（含 RSSI）| `system_profiler SPBluetoothDataType` | 否 |
| 觸發即鎖屏 | `pmset displaysleepnow` | 否 |
| 定位 | IP 城市級（ip-api）| 否 |
| 語音 / 通知 / 推播 | `say` / osascript / curl | 否 |

**合規下唯一做不到**：相機連拍（Camera TCC 鎖死，無合規繞法），以巨響 + 鎖屏 + 推播時間戳補償。

### 核心設計

- **鎖屏即狀態機**：複用系統登入密碼當解除鎖，不自捕捉鍵盤 → 不碰 TCC，行為不像 keylogger
- **武裝邏輯**：藍牙離開主導（信任裝置 away 持續 arm_delay → ARMED），鎖屏降為輔助；堵「人離開沒鎖屏」漏洞
- **分級升溫警告**：TRIGGERED（螢幕警告 + 語音 + 推播 + IP 定位）→ grace（預設 12s）→ ALARMING（警笛循環 + 強制音量 + 鎖屏）
- **解除**：信任藍牙回歸零摩擦，或輸登入密碼兜底
- **定位三層**：IP 城市級（主）+ BSSID→Apple WPS 街廓（條件增強，新版多半遮罩）+ Apple Find My（闔蓋睡後唯一）
- **健檢自動化**：開機查 Find My / FileVault / iCloud / Telegram，缺項一鍵跳轉引導
- **全程 GUI**：osascript 原生對話框，無終端黑框；全模組留 log

### 已查證輪子 / 靈感

cafesentry（Node，觸發/警笛范式）· MacGuard（Swift，RSSI 遲滯/反靜音思路）· corelocationcli（Swift）· apple-corelocation-experiments（Go）/ apple_bssid_locator（Python，BSSID→WPS 街廓）· Apple Find My（闔蓋補位）

### 交付狀態

- 16 檔全數落地，MIT License
- 本機（Mac mini 開發機）驗收 **11/11 PASS**：log 分級/遮罩、gui 對話框、notify 斷網落盤重試、locate IP 定位、config+CLI、guard 完整狀態機、警報強制音量、偵測原語、LaunchAgent、healthcheck、M2 checklist
- 脫敏確認：token / 真實 MAC / IP / 座標 / 本機路徑 0 命中；config.sh / log / 驗收記錄依 .gitignore 未入庫

### 已知硬極限（誠實標示）

闔蓋 + 拔電最惡場景：闔蓋瞬間搶送「闔蓋警報 + IP 定位」後，無 admin 擋不住 clamshell 睡眠 → 腳本凍結 → 依賴 FileVault 保資料 + Apple Find My 補位。這是合規無權限的物理牆，無解。

### 待辦（M2 實機驗證閘門）

開發機無法驗、必須在目標 M2 管控機實跑（見 `deploy-checklist.md` S1→S5）：

- [ ] 法務前置：確認公司 IT 允許裝使用者層防竊腳本
- [ ] S1 環境診斷：MDM / TCC / Gatekeeper 鎖多死、Telegram 是否被封
- [ ] S2 逐能力實跑是否被擋
- [ ] S3 真實 Telegram / iMessage 推播綁定
- [ ] S4 端到端劇本（藍牙武裝 → 觸發 → 警報 → 解除）
- [ ] S5 闔蓋搶跑驗證
- [ ] launchd 是否被 MDM 擋（決定全量 / 子集 / 前景降級）

**潛在阻塞點**：`bin/lockcheck` 靠 `lock.swift` + `swiftc` 編譯，管控機常無 Xcode CLT（裝它可能需 admin / 被 MDM 擋）→ 備 python3 Quartz fallback，再不行降級以藍牙為唯一武裝訊號。真實 Wi-Fi 介面未必 en0，需 `networksetup -listallhardwareports` 確認。
