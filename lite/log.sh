#!/bin/bash
# log.sh — 統一 log 函式庫（全模組共用）
# 格式: ISO8601 | LEVEL | module | message
# 分級: DEBUG < INFO < WARN < ERROR，級別可設定關鍵字
# 輪替: 按日期分檔 logs/xxx-YYYY-MM-DD.log + 保留 N 天自動清
# 遮罩: token/chat_id/座標精確值 寫入前遮罩

: "${EGUARD_DIR:=${HOME}/.eguard}"
LA_LOG_DIR="${EGUARD_DIR}/logs"
LA_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
UA_GLOBAL_LOG_LEVEL="${GLOBAL_LOG_LEVEL:-INFO}"   # DEBUG|INFO|WARN|ERROR

# 級別權重
la_level_num() {
  case "${1:-INFO}" in
    DEBUG) echo 10 ;; INFO) echo 20 ;; WARN) echo 30 ;; ERROR) echo 40 ;;
    *)     echo 20 ;;
  esac
}

la_level_ge() { # 回 0 成立
  [ "$(la_level_num "$1")" -ge "$(la_level_num "$2")" ]
}

# 敏感遮罩：token（長字串）-> ***、Telegram_token 開頭、api key 樣式
la_mask() {
  local s="$1"
  s="$(printf '%s' "$s" | sed -E 's/[0-9]{6,}:[A-Za-z0-9_-]{20,}/**TG_TOKEN**/g')"
  s="$(printf '%s' "$s" | sed -E 's/[0-9]{15,}/**TOKEN**/g')"
  s="$(printf '%s' "$s" | sed -E 's/[A-Za-z0-9_-]{32,}/**KEY**/g')"
  printf '%s' "$s"
}

# 寫 log
# 用法: la_log LEVEL module message
la_log() {
  local lvl="$1" module="$2" msg="${3:-}"
  local ts
  ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
  la_level_ge "$lvl" "$UA_GLOBAL_LOG_LEVEL" || return 0
  mkdir -p "$LA_LOG_DIR"
  local masked; masked="$(la_mask "$msg")"
  printf '%s | %-5s | %-12s | %s\n' "$ts" "$lvl" "$module" "$masked" \
    >> "${LA_LOG_DIR}/eguard-$(date +%Y-%m-%d).log"
}

# 專門 log 檔（events/notify/healthcheck/locate）
la_log_to() {
  local file="$1" lvl="$2" module="$3" msg="${4:-}"
  local ts; ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
  mkdir -p "$LA_LOG_DIR"
  local masked; masked="$(la_mask "$msg")"
  printf '%s | %-5s | %-12s | %s\n' "$ts" "$lvl" "$module" "$masked" \
    >> "${LA_LOG_DIR}/${file}-$(date +%Y-%m-%d).log"
}

# 每天清除 N 天前的日期分檔
la_rotate() {
  local days="$LA_RETENTION_DAYS"
  local cutoff; cutoff="$(date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "-${days} days" +%Y-%m-%d)"
  [ -d "$LA_LOG_DIR" ] || return 0
  find "$LA_LOG_DIR" -type f -name '*.log' -print0 | while IFS= read -r -d '' f; do
    local d; d="$(basename "$f" | sed -E 's/.*-([0-9]{4}-[0-9]{2}-[0-9]{2})\.log/\1/')"
    case "$d" in
      20[0-9][0-9]-*) if [[ "$d" < "$cutoff" ]]; then rm -f "$f"; fi ;;
      *) : ;;
    esac
  done
}