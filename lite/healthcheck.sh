#!/bin/bash
# healthcheck.sh — 防竊前置健檢：Find My / FileVault / iCloud / Telegram 連通
# 缺項 → 回報缺項 + 一鍵跳轉引導（不能代開，Apple 需使用者+iCloud 密碼）
# 來源: source healthcheck.sh（需先 source log.sh）

HC_DIR="/tmp"   # placeholder
HC_RESULT="/tmp/anticheck-$$.out"

# 1. Find My 是否啟用（實測：未開時 ~/Library/Caches/com.apple.findmy.fmipcore/ 不存在）
hc_findmy() {
  if [ -d "${HOME}/Library/Caches/com.apple.findmy.fmipcore" ]; then
    echo "ok"
  else
    echo "MISSING"
  fi
}

# 2. FileVault
hc_filevault() {
  local s; s="$(fdesetup status 2>/dev/null)"
  case "$s" in
    *"FileVault is On."*) echo "ok" ;;
    *) echo "MISSING ($s)" ;;
  esac
}

# 3. iCloud 登入
hc_icloud() {
  local a; a="$(defaults read MobileMeAccounts Accounts 2>/dev/null)"
  if printf '%s' "$a" | grep -q "AccountID"; then echo "ok"; else echo "MISSING"; fi
}

# 4. Telegram 連通（公司防火牆可能封 api.telegram.org）
hc_tg() {
  if curl -m5 -s -o /dev/null -w '%{http_code}' "https://api.telegram.org/" 2>/dev/null | grep -qE '^(200|301|302|403)$'; then
    echo "ok"
  else
    echo "MISSING"
  fi
}

# 統一健檢：寫 log + stdout 逐行狀態
hc_run() {
  local fm fv ic tg
  fm="$(hc_findmy)"; fv="$(hc_filevault)"; ic="$(hc_icloud)"; tg="$(hc_tg)"
  : > "$HC_RESULT"
  printf 'FindMy=%s\nFileVault=%s\niCloud=%s\nTelegram=%s\n' "$fm" "$fv" "$ic" "$tg" | tee -a "$HC_RESULT"
  la_log_to healthcheck INFO healthcheck "FindMy=$fm FileVault=$fv iCloud=$ic Telegram=$tg"
}

# 缺項計數（供 GUI 判斷是否打擾使用者）
hc_missing_count() {
  grep -c '=' "$HC_RESULT" | :
  grep 'MISSING' "$HC_RESULT" | wc -l
}

# 缺項一鍵跳轉
hc_fix_guidance() {
  local r; r="$(cat "$HC_RESULT" 2>/dev/null)"
  if echo "$r" | grep -q 'FindMy=MISSING'; then
    echo "→ 開啟 Find My: 系統設定 > Apple ID > 尋找"
  fi
  if echo "$r" | grep -q 'FileVault=MISSING'; then
    echo "→ 開啟 FileVault: 系統設定 > 隱私與安全性 > FileVault"
  fi
  if echo "$r" | grep -q 'iCloud=MISSING'; then
    echo "→ 登入 iCloud: 系統設定 > Apple ID"
  fi
  if echo "$r" | grep -q 'Telegram=MISSING'; then
    echo "→ Telegram 連不通（可能被公司防火牆封），推播管制"

  fi
}