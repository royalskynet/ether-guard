#!/bin/bash
# config.sh — 防竊系統全客製參數（template）
# 安裝時 install.sh 複製為 ~/.eguard/config.sh；secret 不入 repo，一律 runtime 讀外面

# ===== 信任裝置（藍牙）=====
# system_profiler SPBluetoothDataType 列已配對裝置取名稱+MAC
# 建議只註冊「一定隨身」裝置＝Apple Watch（離開即代表人離開）
TRUSTED_MAC="${TRUSTED_MAC:-}"          # 空白分隔多台，例 "7C:..:.. AC:..:.."
TRUSTED_NAMES="${TRUSTED_NAMES:-}"      # 顯示用名稱，與 MAC 同序

# ===== RSSI 雙門檻遲滯（dBm，越接近0越近/越強）=====
RSSI_PRESENT_THRESH="${RSSI_PRESENT_THRESH:--60}"   # 超過(>=)此=在身邊
RSSI_AWAY_THRESH="${RSSI_AWAY_THRESH:--75}"         # 低於(<=)此=已離開

# ===== 時序 =====
POLL_INTERVAL="${POLL_INTERVAL:-2}"     # 主迴圈輪詢秒
ARM_DELAY="${ARM_DELAY:-45}"            # 信任裝置離開持續此秒數 → ARMED
BT_ABSENT_GRACE="${BT_ABSENT_GRACE:-8}"  # RSSI away 判定需連續此秒（濾瞬斷）
GRACE_SECONDS="${GRACE_SECONDS:-12}"    # TRIGGERED → ALARMING 緩衝秒
UNARM_BT_PRESENT_SEC="${UNARM_BT_PRESENT_SEC:-5}" # 藍牙回歸持 續此秒 → DISARM
WIFI_CHECK_INTERVAL="${WIFI_CHECK_INTERVAL:-15}"  # Wi-Fi 斷偵測頻率
WIFI_FAIL_STREAK="${WIFI_FAIL_STREAK:-3}"        # 連續 down 次數達門檻才觸發
WIFI_IF="${WIFI_IF:-}"                           # 空=自動偵測 Wi-Fi 介面

# ===== 武裝模式 =====
# aggressive: 信任裝置離開即 ARM（積極，不要求鎖屏）
# conservative: 鎖屏 AND 藍牙離開才 ARM
ARMED_MODE="${ARMED_MODE:-aggressive}"
BT_UNKNOWN_IS_AWAY="${BT_UNKNOWN_IS_AWAY:-0}" # RSSI unknown 是否視為離開
BT_UNKNOWN_WARN="${BT_UNKNOWN_WARN:-60}"       # 連續 unknown 輪數後健康告警一次

# ===== 觸發源開關 =====
TRIGGER_HID="${TRIGGER_HID:-1}"       # HIDIdleTime 突降(有人動) → 觸發
TRIGGER_POWER="${TRIGGER_POWER:-1}"   # 拔電(AC→電池) → 觸發
TRIGGER_WIFI="${TRIGGER_WIFI:-1}"     # Wi-Fi 斷線 → 觸發
TRIGGER_BT="${TRIGGER_BT:-1}"         # 信任藍牙在 ARMED 後仍持續不在 → 觸發

# ===== 警告形式 =====
# screen | screen+sound | screen+voice | screen+beep
ALARM_STYLE="${ALARM_STYLE:-screen+voice+beep}"
SIREN_SOUND="${SIREN_SOUND:-}"

# ===== 推播管道 =====
NOTIFY_TELEGRAM="${NOTIFY_TELEGRAM:-1}"
NOTIFY_IMESSAGE="${NOTIFY_IMESSAGE:-0}"
IMESSAGE_TO="${IMESSAGE_TO:-}"          # Apple ID/手機號
WEBHOOK_URL="${WEBHOOK_URL:-}"          # 兜底管道，留空=關
EGUARD_BOT_TOKEN_KEY="${EGUARD_BOT_TOKEN_KEY:-EGUARD_BOT_TOKEN}" # ~/.hermes/.env 專屬 token key
EGUARD_CHAT_ID="${EGUARD_CHAT_ID:-}"                             # 固定收件 chat；空才 fallback
EGUARD_EXPECT_BOT="${EGUARD_EXPECT_BOT:-}"                       # 預期 Telegram bot username
NOTIFY_MIN_INTERVAL="${NOTIFY_MIN_INTERVAL:-300}"                 # 同原因通知冷卻秒數

# ===== 定位 =====
LOCATE_WPS_ENABLED="${LOCATE_WPS_ENABLED:-0}" # BSSID→Apple WPS 街廓（多半拿不到BSSID）
LOCATE_CITY_ONLY="${LOCATE_CITY_ONLY:-1}"

# ===== 進階 =====
HID_IDLE_ACTION_SEC="${HID_IDLE_ACTION_SEC:-3}"  # HIDIdleTime 低於此秒視為「最近有人動」
LOCK_ON_ALARM="${LOCK_ON_ALARM:-1}"      # ALARMING 時鎖屏（osascript Ctrl+Cmd+Q fallback）