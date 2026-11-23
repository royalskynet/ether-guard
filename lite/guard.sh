#!/bin/bash
# guard.sh — 狀態機主迴圈：藍牙主導武裝 → 觸發源輪詢 → 分級升溫 → 解除
# 狀態: DISARMED → ARMED → TRIGGERED → ALARMING → (DISARMED)
# 來源: source 共用模組後呼叫 start_guard_loop

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${EGUARD_DIR:="${HOME}/.eguard"}"
STATE_FILE="${EGUARD_DIR}/state"
CONFIG_FILE="${EGUARD_DIR}/config.sh"
BI_BIN="${EGUARD_DIR}/bin/lockcheck"

[ -f "$SCRIPT_DIR/log.sh" ] && source "$SCRIPT_DIR/log.sh"
[ -f "$SCRIPT_DIR/gui.sh" ] && source "$SCRIPT_DIR/gui.sh"
[ -f "$SCRIPT_DIR/notify.sh" ] && source "$SCRIPT_DIR/notify.sh"
[ -f "$SCRIPT_DIR/locate.sh" ] && source "$SCRIPT_DIR/locate.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# ===== 偵測原語 =====

# 藍牙 RSSI 表：system_profiler 解析 MAC→RSSI；輸出 "MAC RSSI" 逐行
g_bt_rssi_map() {
  system_profiler SPBluetoothDataType 2>/dev/null | awk '
    /Address:/ { mac=$2 }
    /RSSI:/ { if (mac != "") { print mac, $2; mac="" } }
  '
}

# 指定 MAC 的 RSSI（回整數 dBm；找不到回 -999）
g_bt_rssi_of() {
  local mac="$1"
  local r; r="$(g_bt_rssi_map | awk -v m="$mac" '$1==m{print $2; exit}')"
  echo "${r:--999}"
}

# 是否在場（三態）：0=在場、1=已知不在場、2=RSSI 全部讀不到
g_bt_present() {
  local mac r known=0 all_away=1
  for mac in $TRUSTED_MAC; do
    r="$(g_bt_rssi_of "$mac")"
    if [ "$r" = "-999" ]; then all_away=0; continue; fi
    known=1
    if [ "$r" -ge "$RSSI_PRESENT_THRESH" ]; then return 0; fi
    [ "$r" -gt "$RSSI_AWAY_THRESH" ] && all_away=0
  done
  [ "$known" = "0" ] && return 2
  [ "$all_away" = "1" ] && return 1
  return 2
}

# 是否離開：所有信任 MAC 都 <= away 門檻
g_bt_away() {
  local mac r cnt=0 any=0
  for mac in $TRUSTED_MAC; do
    any=1
    r="$(g_bt_rssi_of "$mac")"
    if [ "$r" -le "$RSSI_AWAY_THRESH" ]; then cnt=$((cnt+1)); fi
  done
  [ "$any" = "1" ] && [ "$cnt" -ge 1 ]
}

# HIDIdleTime 秒數（距離上次鍵鼠/輸入事件）
g_hid_idle_sec() {
  ioreg -c IOHIDSystem -r -d 1 2>/dev/null | awk -F= '/HIDIdleTime/{gsub(/[^0-9]/,"",$2); print int($2/1000000000); exit}'
}

# Wi-Fi 介面：明確設定優先，否則自動偵測並快取。
g_wifi_if() {
  local cache="${EGUARD_DIR}/wifi_if" ifc=""
  [ -n "${WIFI_IF:-}" ] && { printf '%s\n' "$WIFI_IF"; return 0; }
  if [ -s "$cache" ]; then
    cat "$cache" 2>/dev/null
    return 0
  fi
  ifc="$(networksetup -listallhardwareports 2>/dev/null \
    | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}')"
  if [ -n "$ifc" ]; then
    mkdir -p "$(dirname "$cache")"
    printf '%s\n' "$ifc" > "$cache"
    printf '%s\n' "$ifc"
  fi
}

# Wi-Fi link（三態）：0=active、1=inactive、2=介面未知。
g_wifi_up() {
  local ifc output
  ifc="$(g_wifi_if)"
  [ -n "$ifc" ] || return 2
  output="$(ifconfig "$ifc" 2>/dev/null)" || return 2
  case "$output" in
    *'status: active'*) return 0 ;;
    *'status: inactive'*) return 1 ;;
    *) return 2 ;;
  esac
}

# Wi-Fi 去抖。0=達觸發門檻、1=未觸發/未到檢查時間、2=unknown。
g_wifi_poll() {
  local now="${1:-$(date +%s)}" interval="${WIFI_CHECK_INTERVAL:-15}" threshold="${WIFI_FAIL_STREAK:-3}" rc
  : "${wifi_last_check:=0}" "${wifi_fail_count:=0}" "${wifi_down_since:=0}"
  if [ "$wifi_last_check" -gt 0 ] && [ $((now - wifi_last_check)) -lt "$interval" ]; then return 1; fi
  wifi_last_check="$now"
  g_wifi_up; rc=$?
  case "$rc" in
    0) wifi_fail_count=0; wifi_down_since=0; return 1 ;;
    1)
      [ "$wifi_down_since" -eq 0 ] && wifi_down_since="$now"
      wifi_fail_count=$((wifi_fail_count+1))
      [ "$wifi_fail_count" -ge "$threshold" ] && [ $((now - wifi_down_since)) -ge $((interval * threshold)) ] && return 0
      return 1
      ;;
    *) wifi_fail_count=0; wifi_down_since=0; return 2 ;;
  esac
}

# 同一原因通知冷卻。逐原因記錄，避免 A→B→A 繞過冷卻。
g_notify_allowed() {
  local reason="$1" now="${2:-$(date +%s)}" min="${NOTIFY_MIN_INTERVAL:-300}"
  local file="${EGUARD_DIR}/notify_cooldown" last="" tmp
  if [ -f "$file" ]; then
    last="$(awk -F '\t' -v r="$reason" '$2==r{v=$1} END{print v}' "$file")"
  fi
  [ -n "$last" ] && [ $((now - last)) -lt "$min" ] && return 1
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if [ -f "$file" ]; then awk -F '\t' -v r="$reason" '$2!=r' "$file" > "$tmp"; fi
  printf '%s\t%s\n' "$now" "$reason" >> "$tmp"
  mv "$tmp" "$file"
  return 0
}

# 啟動檢查不阻斷本機防護；bot 身分不符時只停用 Telegram，避免錯送。
g_startup_checks() {
  local notify_rc lock_rc
  if command -v notify_selftest >/dev/null 2>&1; then
    notify_selftest >/dev/null; notify_rc=$?
    case "$notify_rc" in
      0) : ;;
      3) NOTIFY_TELEGRAM=0; la_log ERROR guard "通知身分不符：已停用 Telegram，主迴圈繼續" ;;
      *) la_log WARN guard "通知身分自檢失敗，主迴圈繼續" ;;
    esac
  fi
  g_locked >/dev/null 2>&1; lock_rc=$?
  [ "$lock_rc" = "2" ] && la_log WARN guard "解除條件降級：僅藍牙可解除"
  return 0
}

# 鎖定狀態（三態）：lockcheck → Quartz；0=已鎖、1=未鎖、2=unknown。
g_locked() {
  local out=""
  if [ -x "$BI_BIN" ]; then
    out="$("$BI_BIN" 2>/dev/null)"
    [ "$out" = "1" ] && return 0
    [ "$out" = "0" ] && return 1
  fi
  command -v python3 >/dev/null 2>&1 || return 2
  out="$(python3 -c 'import Quartz
d=Quartz.CGSessionCopyCurrentDictionary() or {}
print(1 if d.get("CGSSessionScreenIsLocked", 0) else 0)' 2>/dev/null)" || return 2
  [ "$out" = "1" ] && return 0
  [ "$out" = "0" ] && return 1
  return 2
}

# 明確解鎖：只有 g_locked 的「未鎖」(rc=1) 才成立；unknown 不解除。
g_unlocked() {
  local rc=0
  g_locked || rc=$?
  [ "$rc" = "1" ]
}

# 解除條件：信任藍牙回歸，或螢幕明確解鎖。
g_should_disarm() {
  [ "${1:-0}" = "1" ] || g_unlocked
}

# 秒數門檻使用實際 elapsed time，不依賴主迴圈執行次數。
g_duration_reached() {
  local since="$1" duration="$2" now="${3:-$(date +%s)}"
  [ "$since" -gt 0 ] && [ $((now - since)) -ge "$duration" ]
}

# 供電來源
g_power_src() { pmset -g batt 2>/dev/null | head -1; }

# 警報音產生：afplay 循環（背景）
_ensure_siren() {
  local s="$SIREN_SOUND"
  if [ -z "$s" ]; then
    # 無音檔時用 say 合成 + afplay 內建提示音告警
    :
  fi
}

# ===== 分支動作 =====

_state_log() { la_log_to events INFO guard "state -> $1"; printf '%s\n' "$1" > "$STATE_FILE"; }

_alarm_stage0() {  # TRIGGERED：軟警告
  local reason="${1:-unknown}"
  la_log WARN guard "TRIGGERED"
  _fullscr "$(date +%H:%M:%S) 偵測到未授權動作，請解除" &
  say "偵測到未授權，請解鎖" &
  if g_notify_allowed "$reason"; then
    _notify_trigger "⚠️ 疑似觸發：${reason}"
  else
    la_log INFO guard "notify throttled: ${reason}"
  fi
}

_fullscr() { gui_warning "防竊警報" "$1" 2>/dev/null; }

_alarm_stage1() {  # ALARMING：巨響
  la_log ERROR guard "ALARMING 分級升溫"
  # 強制音量 100% + unmute
  osascript -e "set volume output volume 100" -e "set volume without output muted" 2>/dev/null &
  local vol; vol="$(osascript -e 'get volume settings' 2>/dev/null)"
  la_log WARN guard "volume forced (was: $vol)"
  # 警笛循環（背景）
  _siren_loop &
  say "警 報！設備疑似被攜離" &
  if g_notify_allowed "${active_trig:-ALARMING}"; then
    _notify_siren "🚨 警報中：設備恐被偷" &
  else
    la_log INFO guard "notify throttled: ${active_trig:-ALARMING}"
  fi
  # ALARMING 鎖屏
  if [ "${LOCK_ON_ALARM:-1}" = "1" ]; then
    osascript -e 'tell application "System Events" to key code 12 using {control down, command down}' 2>/dev/null &
  fi
}

_siren_loop() {
  local n=0
  local snd="${SIREN_SOUND}"
  while :; do
    if [ -n "$snd" ] && [ -f "$snd" ]; then
      afplay "$snd" 2>/dev/null
    else
      say "設 備可能被偷，請立刻處理" 2>/dev/null
    fi
    osascript -e "set volume output volume 100" -e "set volume without output muted" 2>/dev/null
    n=$((n+1)); [ $n -gt 200 ] && break
    sleep 0.5
  done
}

_notify_trigger() { notify_send "$1" >/dev/null 2>&1; }
_notify_siren() { notify_send "$1" >/dev/null 2>&1; }

# ===== 主迴圈 =====
start_guard_loop() {
  local state="DISARMED" arm_since=0 trigger_since=0 bt_absent=0 last_power prev_wifi
  local bt_state=2 bt_unknown_count=0 bt_unknown_warned=0
  local wifi_last_check=0 wifi_fail_count=0 wifi_down_since=0
  local last_alarm_notice_at=0 active_trig=""
  _state_log "$state"
  last_power="$(g_power_src)"
  prev_wifi=""
  g_startup_checks

  while :; do
    local bt_present=0
    g_bt_present; bt_state=$?
    case "$bt_state" in
      0) bt_present=1; bt_unknown_count=0; bt_unknown_warned=0 ;;
      1) bt_present=0; bt_unknown_count=0; bt_unknown_warned=0 ;;
      2)
        [ "${BT_UNKNOWN_IS_AWAY:-0}" = "1" ] && bt_present=0 || bt_present=2
        bt_unknown_count=$((bt_unknown_count+1))
        if [ "$bt_unknown_count" -ge "${BT_UNKNOWN_WARN:-60}" ] && [ "$bt_unknown_warned" = "0" ]; then
          bt_unknown_warned=1
          la_log WARN guard "藍牙偵測降級：RSSI 讀不到"
          notify_send "⚠️ EGuard 偵測降級：藍牙 RSSI 持續讀不到，未自動武裝。" >/dev/null 2>&1
        fi
        ;;
    esac

    case "$state" in
      DISARMED)
        if [ "$bt_present" = "0" ] && [ -n "$TRUSTED_MAC" ]; then
          local arm_now; arm_now="$(date +%s)"
          [ "$arm_since" -eq 0 ] && arm_since="$arm_now"
          if [ "$ARMED_MODE" = "conservative" ]; then
            if g_locked && g_duration_reached "$arm_since" "$ARM_DELAY" "$arm_now"; then
              state="ARMED"; _state_log "$state"; arm_since=0
            fi
          else
            # 積極：藍牙離開監測
            if g_duration_reached "$arm_since" "$ARM_DELAY" "$arm_now"; then
              state="ARMED"; _state_log "$state"; arm_since=0
            fi
          fi
        else
          arm_since=0
        fi
        ;;
      ARMED)
        # 藍牙回歸 → 日常返座自動解除
        if [ "$bt_present" = "1" ]; then state="DISARMED"; _state_log "$state"; continue; fi
        # 觸發源偵測
        local trig=""
        [ "${TRIGGER_HID:-1}" = "1" ] && {
          local idle; idle="$(g_hid_idle_sec 2>/dev/null)"
          [ -n "$idle" ] && [ "$idle" -lt "${HID_IDLE_TRIGGER_SEC:-1}" ] && trig="HIDIdleTime突降(有人動)"
        }
        [ "${TRIGGER_POWER:-1}" = "1" ] && {
          local p; p="$(g_power_src)"
          case "$p" in *Battery*) [ "$last_power" != "$p" ] && trig="${trig:+$trig,}拔電" ;; esac
          last_power="$p"
        }
        [ "${TRIGGER_WIFI:-1}" = "1" ] && {
          local wifi_rc
          g_wifi_poll "$(date +%s)"; wifi_rc=$?
          case "$wifi_rc" in
            0) trig="${trig:+$trig,}Wi-Fi斷" ;;
            2) la_log WARN guard "Wi-Fi 狀態 unknown，不觸發" ;;
          esac
        }
        if [ -n "$trig" ]; then
          active_trig="$trig"; state="TRIGGERED"; trigger_since="$(date +%s)"
          _state_log "$state"; _alarm_stage0 "$trig"
        fi
        ;;
      TRIGGERED)
        # 解除條件：藍牙回歸 或 解鎖
        if g_should_disarm "$bt_present"; then state="DISARMED"; _state_log "$state"; continue; fi
        local trigger_now; trigger_now="$(date +%s)"
        if g_duration_reached "$trigger_since" "$GRACE_SECONDS" "$trigger_now"; then
          state="ALARMING"; last_alarm_notice_at="$trigger_now"; _state_log "$state"; _alarm_stage1
        fi
        ;;
      ALARMING)
        if g_should_disarm "$bt_present"; then state="DISARMED"; _state_log "$state"; else
          # 持續警報：每 60 秒嘗試，仍受同原因最小通知間隔節流。
          local alarm_now; alarm_now="$(date +%s)"
          if [ $((alarm_now - last_alarm_notice_at)) -ge 60 ]; then
            last_alarm_notice_at="$alarm_now"
            if g_notify_allowed "${active_trig:-ALARMING}" "$alarm_now"; then
              notify_send "🚨 警報持續：$(date +%H:%M:%S)" >/dev/null 2>&1
            else
              la_log INFO guard "notify throttled: ${active_trig:-ALARMING}"
            fi
          fi
          osascript -e "set volume output volume 100" -e "set volume without output muted" 2>/dev/null
        fi
        ;;
    esac

    sleep "${POLL_INTERVAL:-2}"
  done
}

# 若直接執行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  [ -n "$TRUSTED_MAC" ] || { echo "沒有信任裝置（TRUSTED_MAC 未設），先跑 install.sh 配對"; exit 1; }
  start_guard_loop
fi