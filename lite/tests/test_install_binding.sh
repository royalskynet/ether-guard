#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EGUARD_DIR="$TMP/eguard"
mkdir -p "$HOME/.hermes" "$EGUARD_DIR" "$TMP/bin"
printf 'EGUARD_BOT_TOKEN=dedicated-token\nTELEGRAM_BOT_TOKEN=legacy-token\n' > "$HOME/.hermes/.env"
cp "$ROOT/log.sh" "$ROOT/notify.sh" "$EGUARD_DIR/"
cat > "$EGUARD_DIR/config.sh" <<'CFG'
NOTIFY_TELEGRAM="1"
NOTIFY_IMESSAGE="0"
WEBHOOK_URL=""
EGUARD_BOT_TOKEN_KEY="EGUARD_BOT_TOKEN"
EGUARD_CHAT_ID="424242"
EGUARD_EXPECT_BOT="Amy_test_bot"
CFG

cat > "$TMP/bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
case "$*" in
  *getMe*) printf '%s' '{"ok":true,"result":{"username":"Amy_test_bot"}}' ;;
  *getUpdates*) printf '%s' '{"ok":true,"result":[{"message":{"chat":{"id":999999}}}]}' ;;
  *sendMessage*) printf '%s' '{"ok":true,"result":{"message_id":1}}' ;;
  *) printf '%s' '{}' ;;
esac
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export CURL_LOG="$TMP/curl.log"
: > "$CURL_LOG"

# Load function definitions only; never execute installer main in this test.
awk '/^deploy_modules$/{exit} {print}' "$ROOT/install.sh" > "$TMP/install-functions.sh"
source "$TMP/install-functions.sh"
SCRIPT_DIR="$ROOT"
set +u
bind_telegram >/dev/null
set -u

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
if grep -q 'getUpdates' "$CURL_LOG"; then fail "fixed install binding must not call getUpdates"; fi
grep -q 'sendMessage' "$CURL_LOG" || fail "installer must send a test message"
grep -q 'chat_id=424242' "$CURL_LOG" || fail "installer must use fixed EGUARD_CHAT_ID"
[ ! -e "$EGUARD_DIR/chat_id" ] || fail "fixed install binding must not create chat cache"
printf 'PASS: installer fixed Telegram binding\n'
