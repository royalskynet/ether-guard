#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EGUARD_DIR="$TMP/eguard"
mkdir -p "$HOME/.hermes" "$EGUARD_DIR" "$TMP/bin"
LOG="$TMP/log"
: > "$LOG"

la_log() { printf '%s\n' "$*" >> "$LOG"; }
la_log_to() { printf '%s\n' "$*" >> "$LOG"; }

# Fake curl: records URL and returns Telegram getMe success.
cat > "$TMP/bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '%s' '{"ok":true,"result":{"username":"Amy_test_bot"}}'
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export CURL_LOG="$TMP/curl.log"
: > "$CURL_LOG"

# shellcheck source=../notify.sh
source "$ROOT/notify.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got=$1 want=$2)"; }

# 1. Explicit env token wins.
export EGUARD_BOT_TOKEN="env-token"
printf 'EGUARD_BOT_TOKEN=file-token\nTELEGRAM_BOT_TOKEN=legacy-token\n' > "$HOME/.hermes/.env"
assert_eq "$(_tg_token)" "env-token" "EGUARD_BOT_TOKEN env must win"

# 2. Configured dedicated key is read exactly.
unset EGUARD_BOT_TOKEN
export EGUARD_BOT_TOKEN_KEY="CUSTOM_EGUARD_TOKEN"
printf 'CUSTOM_EGUARD_TOKEN=custom-token\nTELEGRAM_BOT_TOKEN=legacy-token\n' > "$HOME/.hermes/.env"
assert_eq "$(_tg_token)" "custom-token" "dedicated token key must win"

# 3. Explicit chat ID bypasses cache and getUpdates.
export EGUARD_CHAT_ID="424242"
: > "$CURL_LOG"
assert_eq "$(_tg_chat_id)" "424242" "explicit chat id must win"
[ ! -s "$CURL_LOG" ] || fail "explicit chat id must not call curl/getUpdates"
[ ! -e "$EGUARD_DIR/chat_id" ] || fail "explicit chat id must not create cache"

# 4. Self-test validates bot username.
export EGUARD_BOT_TOKEN="env-token"
export EGUARD_EXPECT_BOT="Amy_test_bot"
notify_selftest >/dev/null || fail "matching bot username must pass"
export EGUARD_EXPECT_BOT="Wrong_bot"
set +e
notify_selftest >/dev/null 2>&1
MISMATCH_RC=$?
set -e
if [ "$MISMATCH_RC" = "0" ]; then
  fail "mismatched bot username must fail"
fi
assert_eq "$MISMATCH_RC" "3" "mismatched bot username must return identity error"

printf 'PASS: notify identity binding\n'
