#!/bin/bash
# install.sh — 一鍵安裝：部署模組 → osascript 配對信任裝置 → 綁定推播 → 健檢 → 註冊 LaunchAgent → 測試推播
# 全程原生視窗，不需 admin / 不需 TCC。相容 macOS bash 3.2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${EGUARD_DIR:="${HOME}/.eguard"}"
BIN_DIR="${EGUARD_DIR}/bin"
LA_DIR="${HOME}/Library/LaunchAgents"
PLIST_LABEL="com.user.eguard"
PLIST_DST="${LA_DIR}/${PLIST_LABEL}.plist"

[ -f "$SCRIPT_DIR/gui.sh" ] && source "$SCRIPT_DIR/gui.sh"

saystep(){ echo; echo ">> $1"; }

# 0. 部署模組到 ~/.eguard
deploy_modules() {
  saystep "0/5 部署模組"
  mkdir -p "$EGUARD_DIR" "$BIN_DIR" "$EGUARD_DIR/logs" "$EGUARD_DIR/queue"
  for f in guard.sh notify.sh locate.sh healthcheck.sh gui.sh log.sh eguard; do
    if [ -f "$SCRIPT_DIR/$f" ]; then cp "$SCRIPT_DIR/$f" "$EGUARD_DIR/$f"; chmod +x "$EGUARD_DIR/$f"; fi
  done
  # config 存在則保留（不覆寫使用者已設值）
  if [ ! -f "$EGUARD_DIR/config.sh" ]; then cp "$SCRIPT_DIR/config.example.sh" "$EGUARD_DIR/config.sh"; fi
  # 編譯 lockcheck
  if [ -f "$SCRIPT_DIR/lock.swift" ]; then swiftc -O "$SCRIPT_DIR/lock.swift" -o "$BIN_DIR/lockcheck"; chmod +x "$BIN_DIR/lockcheck"; fi
  # 替換 plist 內 USER 佔位
  if [ -f "$SCRIPT_DIR/com.user.eguard.plist" ]; then
    sed "s#/Users/USER#$HOME#g" "$SCRIPT_DIR/com.user.eguard.plist" > "$PLIST_DST"
  fi
  saystep "已部署到 $EGUARD_DIR"
}

# 1. osascript 列藍牙選擇信任裝置
pair_device() {
  saystep "1/5 選擇信任裝置（建議 Apple Watch）"
  # 列已配對藍牙裝置（name + RSSI）
  local list
  list="$(system_profiler SPBluetoothDataType 2>/dev/null \
    | awk '/Device Name:/{n=$0; sub(/.*Device Name: /,"",n)} /Address:/{a=$2} /RSSI:/{r=$2; if(n!=""&&a!=""){print n" ("a" rssi "r")"; n=""; a=""}}')"
  [ -z "$list" ] && { list="（找不到已配對藍牙裝置，可在 系統設定 > 藍牙 先配對手表/手機）"; }
  local chosen; chosen="$(gui_choose "選信任裝置（離開=人離開）" "$list")"
  [ -z "$chosen" ] && { echo "未選，跳過（之後可手動改 config.sh 的 TRUSTED_MAC）"; return; }
  local mac; mac="$(printf '%s' "$chosen" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1)"
  if [ -n "$mac" ]; then
    # 寫入 config.sh 的 TRUSTED_MAC（保留其他設定）
    if grep -q '^TRUSTED_MAC=' "$EGUARD_DIR/config.sh"; then
      sed -i '' "s|^TRUSTED_MAC=.*|TRUSTED_MAC=\"$mac $(grep '^TRUSTED_MAC=' "$EGUARD_DIR/config.sh"|cut -d'\"' -f2)\"|" "$EGUARD_DIR/config.sh"
    fi
    saystep "已記住信任裝置 $mac"
  else
    echo "解析 MAC 失敗，請手動編輯 $EGUARD_DIR/config.sh"
  fi
}

# 2. 綁定 Telegram：復用 notify.sh 的專屬 token、固定 chat 與身分自檢。
bind_telegram() {
  saystep "2/5 綁定推播（Telegram）"
  [ -f "$EGUARD_DIR/log.sh" ] && source "$EGUARD_DIR/log.sh"
  [ -f "$EGUARD_DIR/config.sh" ] && source "$EGUARD_DIR/config.sh"
  [ -f "$EGUARD_DIR/notify.sh" ] && source "$EGUARD_DIR/notify.sh"
  command -v _tg_token >/dev/null 2>&1 || { saystep "notify.sh 未部署，跳過 Telegram 綁定"; return; }

  local token cid
  token="$(_tg_token)"
  if [ -z "$token" ]; then
    saystep "未找到 Telegram token；請在 ~/.hermes/.env 設 EGUARD_BOT_TOKEN"
    return
  fi
  if ! notify_selftest >/dev/null; then
    saystep "⚠️ Telegram bot 身分自檢失敗；不送測試訊息"
    return
  fi
  cid="$(_tg_chat_id)"
  if [ -z "$cid" ]; then
    saystep "尚未設定 chat：請在 config.sh 寫入固定 EGUARD_CHAT_ID"
    return
  fi
  if [ -n "${EGUARD_CHAT_ID:-}" ]; then
    saystep "已使用固定 EGUARD_CHAT_ID，發測試推播…"
  else
    saystep "⚠️ 使用 getUpdates fallback；請將 chat_id 寫入 EGUARD_CHAT_ID"
  fi
  notify_telegram "✅ 防竊系統已安裝連線成功" >/dev/null 2>&1 \
    && saystep "推播測試成功" || saystep "推播測試失敗（見 notify log）"
}

# 3. 健檢
run_healthcheck() {
  saystep "3/5 防竊前置健檢"
  [ -f "$SCRIPT_DIR/healthcheck.sh" ] && source "$SCRIPT_DIR/healthcheck.sh"
  local r; r="$(hc_run 2>/dev/null)"
  echo "$r"
  local missing; missing="$(grep -c 'MISSING' "$EGUARD_DIR/logs/healthcheck-$(date +%Y-%m-%d).log" 2>/dev/null || echo 0)"
  gui_notify "防竊健檢" "$(echo "$r" | tr '\n' ' ')"
}

# 4. 註冊 LaunchAgent
register_launchagent() {
  saystep "4/5 註冊開機自啟 LaunchAgent"
  mkdir -p "$LA_DIR"
  launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null && echo "已註冊 (launchctl bootstrap gui/$UID)" || \
    { echo "bootstrap 失敗，嘗試 loginwindow 相容"; launchctl load "$PLIST_DST" 2>/dev/null; }
  launchctl print "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null | head -5
}

# 5. 測試推播（已在上方 bind 送過；此處列總結）
finish() {
  saystep "5/5 安裝完成"
  cat <<EOF
已安裝到 $EGUARD_DIR
常用指令:
  $EGUARD_DIR/eguard status   查狀態+健檢燈號
  $EGUARD_DIR/eguard log     看 log
  $EGUARD_DIR/eguard arm / disarm
若還未配對信任裝置，編輯 $EGUARD_DIR/config.sh 的 TRUSTED_MAC。
EOF
}

deploy_modules
pair_device
bind_telegram
run_healthcheck
register_launchagent
finish