#!/bin/bash
# notify.sh — 三管道推播（Telegram 主 / iMessage 備援 / webhook 兜底）+ 檔案重試佇列
# 來源: source notify.sh（需先 source log.sh）
# 佇列: ${EGUARD_DIR}/queue/notify.queue（未送出訊息逐行暫存，恢復連線時 flush）

NOTIFY_QUEUE="${EGUARD_DIR}/queue/notify.queue"
NOTIFY_TG_BIN="@NOTIFY_TG_BIN@"   # 安裝時填 curl
NOTIFY_IP_LOCATE_CB=""

# 讀 Telegram 憑證：專屬 token / 固定 chat 優先；舊機制僅作相容 fallback
_tg_token() {
  local f="${HOME}/.hermes/.env" key="${EGUARD_BOT_TOKEN_KEY:-EGUARD_BOT_TOKEN}" token=""
  [ -n "${EGUARD_BOT_TOKEN:-}" ] && { printf '%s\n' "$EGUARD_BOT_TOKEN"; return 0; }
  if [ -f "$f" ]; then
    token="$(awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$f")"
    [ -n "$token" ] && { printf '%s\n' "$token"; return 0; }
    token="$(awk -F= '$1=="TELEGRAM_BOT_TOKEN" || $1=="TG_BOT_TOKEN"{sub(/^[^=]*=/,""); print; exit}' "$f")"
  fi
  if [ -n "$token" ]; then
    command -v la_log >/dev/null 2>&1 && la_log WARN notify "token fallback: 未設專屬 key，身分不保證"
    printf '%s\n' "$token"
  fi
}

_tg_chat_id() {
  local cf="${EGUARD_DIR}/chat_id"
  [ -n "${EGUARD_CHAT_ID:-}" ] && { printf '%s\n' "$EGUARD_CHAT_ID"; return 0; }
  [ -f "$cf" ] && { cat "$cf" 2>/dev/null; return; }
  local token; token="$(_tg_token)"; [ -z "$token" ] && return
  # 第一次：getUpdates 抓最近一則訊息的 chat_id 存檔（bind 流程用）
  local up; up="$(curl -m8 -s "https://api.telegram.org/bot${token}/getUpdates?limit=1&timeout=2")"
  local cid; cid="$(printf '%s' "$up" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); m=d.get("result") or []
  msg=m[-1].get("message") if m else None
  print(msg.get("chat",{}).get("id","") if msg else "")' 2>/dev/null)"
  [ -n "$cid" ] && {
    mkdir -p "$(dirname "$cf")"
    printf '%s' "$cid" > "$cf"
    command -v la_log >/dev/null 2>&1 && la_log WARN notify "chat fallback: getUpdates 自動綁定，請將 chat_id 寫入 EGUARD_CHAT_ID"
    echo "$cid"
  }
}

# 啟動自檢：確認 Telegram token 對應的 bot username。
notify_selftest() {
  local token body username expected
  token="$(_tg_token)"
  [ -n "$token" ] || { la_log_to notify ERROR notify "selftest: TG token missing"; return 2; }
  body="$(curl -m8 -s "https://api.telegram.org/bot${token}/getMe")"
  username="$(printf '%s' "$body" | python3 -c 'import sys,json
try:
 d=json.load(sys.stdin); print(d.get("result",{}).get("username","") if d.get("ok") else "")
except Exception: print("")' 2>/dev/null)"
  [ -n "$username" ] || { la_log_to notify ERROR notify "selftest: getMe failed"; return 1; }
  la_log_to notify INFO notify "selftest: bot username=${username}"
  printf '%s\n' "$username"
  expected="${EGUARD_EXPECT_BOT#@}"
  if [ -n "$expected" ] && [ "$username" != "$expected" ]; then
    la_log_to notify ERROR notify "selftest: bot mismatch expected=${expected} actual=${username}"
    return 3
  fi
  [ -n "$expected" ] || la_log_to notify WARN notify "selftest: EGUARD_EXPECT_BOT 未設定"
  return 0
}

# 送 Telegram 文字
notify_telegram() {
  local text="$1" token cid
  token="$(_tg_token)"; [ -z "$token" ] && { la_log_to notify WARN notify "TG token missing"; return 2; }
  cid="$(_tg_chat_id)";  [ -z "$cid" ] && { la_log_to notify WARN notify "TG no chat_id"; return 2; }
  local r; r="$(curl -m8 -s "https://api.telegram.org/bot${token}/sendMessage" \
      --data-urlencode "chat_id=$cid" --data-urlencode "text=$text")"
  if printf '%s' "$r" | grep -q '"ok":true'; then
    la_log_to notify INFO notify "TG ok"
    return 0
  fi
  la_log_to notify WARN notify "TG send fail: $r"
  return 1
}

# 送 iMessage（需 Messages 登入；Automation TCC 需使用者授權）
notify_imessage() {
  local text="$1" phone="${IMESSAGE_TO:-}"
  [ -z "$phone" ] && { la_log_to notify WARN notify "iMessage target unset"; return 2; }
  osascript -e "tell application \"Messages\" to send \"$text\" to buddy \"$phone\"" 2>/dev/null && {
    la_log_to notify INFO notify "iMessage ok"; return 0; }
  la_log_to notify WARN notify "iMessage fail"
  return 1
}

# webhook 兜底
notify_webhook() {
  local text="$1" url="${WEBHOOK_URL:-}"
  [ -z "$url" ] && { la_log_to notify WARN notify "webhook unset"; return 2; }
  local r; r="$(curl -m8 -s -X POST "$url" --data-urlencode "text=$text")"
  la_log_to notify INFO notify "webhook rc=$? body=$r"
  return 0
}

# 統一入口：依 config 啟用管道依序嘗試，全失敗則落盤列隊
# 用法: notify_send "⚠️ 安全警告：..."
notify_send() {
  local text="$1" ok=0
  # 優先序：telegram -> iMessage -> webhook
  if [ "${NOTIFY_TELEGRAM:-1}" = "1" ]; then notify_telegram "$text" && ok=1; fi
  if [ "$ok" = "0" ] && [ "${NOTIFY_IMESSAGE:-0}" = "1" ]; then notify_imessage "$text" && ok=1; fi
  if [ "$ok" = "0" ] && [ -n "$WEBHOOK_URL" ]; then notify_webhook "$text" && ok=1; fi
  if [ "$ok" = "0" ]; then
    mkdir -p "$(dirname "$NOTIFY_QUEUE")"
    printf '%s\n' "$text" >> "$NOTIFY_QUEUE"
    la_log_to notify WARN notify "queue add (${EGUARD_DIR}/queue)"
    return 1
  fi
  return 0
}

# 沖佇列：重試每行，成功移除
notify_flush() {
  [ -f "$NOTIFY_QUEUE" ] || return 0
  local tmp; tmp="$(mktemp)"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if notify_telegram "$line"; then
      la_log_to notify INFO notify "flush ok"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$NOTIFY_QUEUE"
  mv "$tmp" "$NOTIFY_QUEUE" 2>/dev/null || rm -f "$tmp"
}