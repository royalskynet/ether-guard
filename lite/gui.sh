#!/bin/bash
# gui.sh — osascript 系統原生對話框庫（無終端黑框、不需 TCC）
# 相容 macOS 內建 bash 3.2（不用 ${x@Q}）。用法: source gui.sh
#   gui_notify "標題" "訊息"; gui_choose "提示" "一\二\三"; gui_input "prompt" "def"

# AppleScript 字串轉義：\ -> \\  " -> \"  換行 -> \n(AppleScript) 
_gui_esc() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 本機通知（Notification Center，不需 TCC）
gui_notify() {
  local title="$1" msg="${2:-}"
  local t m
  t="$(_gui_esc "$title")"; m="$(_gui_esc "$msg")"
  osascript -e "display notification \"$m\" with title \"$t\"" 2>/dev/null
}

# choose from list：選項以「\」分隔（避免 IFS 換行坑）。回選中值；取消回空
gui_choose() {
  local prompt="$1" items="$2" p esc acc
  p="$(_gui_esc "$prompt")"
  # 組 { "a", "b", "c" }
  acc=""
  while IFS='\' read -r seg; do
    esc="$(_gui_esc "$seg")"
    if [ -z "$acc" ]; then acc="\"$esc\""; else acc="$acc, \"$esc\""; fi
  done <<< "$items"
  osascript -e "choose from list {$acc} with prompt \"$p\"" 2>/dev/null
}

# 逐項填值（回輸入值；取消回空）
gui_input() {
  local prompt="$1" def="${2:-}" p d
  p="$(_gui_esc "$prompt")"; d="$(_gui_esc "$def")"
  osascript -e "text returned of (display dialog \"$p\" default answer \"$d\" buttons {\"取消\",\"確定\"} default button \"確定\")" 2>/dev/null
}

# 布林確認：yes=按確定, no=取消
gui_confirm() {
  local prompt="$1" p
  p="$(_gui_esc "$prompt")"
  local r; r="$(osascript -e "button returned of (display dialog \"$p\" buttons {\"取消\",\"確定\"} default button \"確定\" with icon caution)" 2>/dev/null)"
  [ "$r" = "確定" ] && echo "yes" || echo "no"
}

# 顯示多行內容（status/config/log）
gui_show() {
  local title="$1" body="$2" t b apple
  t="$(_gui_esc "$title")"
  # 換行統一 \r（AppleScript 顯示用），轉義引號
  b="$(printf '%s' "$body" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\r')"
  osascript -e "display dialog \"$b\" with title \"$t\" with icon note buttons {\"確定\"} default button \"確定\"" 2>/dev/null
}

# 全屏警告（警報用）：限時 15s 自動消失，避免卡死狀態機
gui_warning() {
  local title="$1" body="${2:-注意！}" t b
  t="$(_gui_esc "$title")"; b="$(_gui_esc "$body")"
  osascript -e "display dialog \"$b\" with title \"$t\" with icon stop buttons {\"確 定\"} default button \"確 定\" giving up after 15" 2>/dev/null
}

# 跳到系統偏好設定面板
gui_open_pref() {
  local anchor="$1"
  osascript -e "tell application \"System Settings\" to activate" -e "open location \"$anchor\"" 2>/dev/null
}

# 開啟 Console.app
gui_open_console() {
  osascript -e "tell application \"Console\" to activate" 2>/dev/null
}

# 直接執行時無操作（本檔為庫）
[ "$0" = "${BASH_SOURCE[0]}" ] && { echo "gui.sh is a library — source it"; exit 0; }