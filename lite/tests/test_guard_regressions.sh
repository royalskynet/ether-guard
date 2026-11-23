#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export EGUARD_DIR="$TMP/eguard"
mkdir -p "$EGUARD_DIR"
cat > "$EGUARD_DIR/config.sh" <<'CFG'
TRUSTED_MAC="AA:BB:CC:DD:EE:FF"
RSSI_PRESENT_THRESH="-60"
RSSI_AWAY_THRESH="-75"
WIFI_IF=""
WIFI_CHECK_INTERVAL="15"
WIFI_FAIL_STREAK="3"
NOTIFY_MIN_INTERVAL="300"
CFG

la_log() { :; }
la_log_to() { :; }
source "$ROOT/guard.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got=$1 want=$2)"; }
rc_of() { set +e; "$@" >/dev/null 2>&1; local r=$?; set -e; printf '%s' "$r"; }
run_rc() { set +e; "$@" >/dev/null 2>&1; LAST_RC=$?; set -e; }
set -e

# Wi-Fi interface: explicit config first, otherwise hardware-port discovery.
WIFI_IF="en7"
assert_eq "$(g_wifi_if)" "en7" "explicit WIFI_IF must win"
WIFI_IF=""
networksetup() {
  printf '%s\n' 'Hardware Port: Wi-Fi' 'Device: en9' 'Ethernet Address: 00:00:00:00:00:00'
}
assert_eq "$(g_wifi_if)" "en9" "Wi-Fi interface must auto-detect"

# Link status is tri-state: active=0, inactive=1, no interface=2.
WIFI_IF="en9"
ifconfig() { printf '%s\n' 'en9: flags=1<UP>' ' status: active'; }
assert_eq "$(rc_of g_wifi_up)" "0" "active Wi-Fi must be up"
ifconfig() { printf '%s\n' 'en9: flags=1<UP>' ' status: inactive'; }
assert_eq "$(rc_of g_wifi_up)" "1" "inactive Wi-Fi must be down"
ifconfig() { return 1; }
assert_eq "$(rc_of g_wifi_up)" "2" "ifconfig failure must be unknown"
ifconfig() { printf '%s\n' 'en9: flags=1<UP>'; }
assert_eq "$(rc_of g_wifi_up)" "2" "missing link status must be unknown"
WIFI_IF=""
rm -f "$EGUARD_DIR/wifi_if"
networksetup() { :; }
assert_eq "$(rc_of g_wifi_up)" "2" "missing Wi-Fi interface must be unknown"

# Missing RSSI must be unknown, not away.
g_bt_rssi_of() { printf '%s\n' '-999'; }
assert_eq "$(rc_of g_bt_present)" "2" "RSSI -999 must be unknown"
g_bt_rssi_of() { printf '%s\n' '-50'; }
assert_eq "$(rc_of g_bt_present)" "0" "strong RSSI must be present"
g_bt_rssi_of() { printf '%s\n' '-70'; }
assert_eq "$(rc_of g_bt_present)" "2" "RSSI hysteresis midband must hold as unknown"
g_bt_rssi_of() { printf '%s\n' '-80'; }
assert_eq "$(rc_of g_bt_present)" "1" "RSSI below away threshold must be away"

# Lock detection: binary -> Quartz fallback -> unknown.
BI_BIN="$TMP/no-lockcheck"
python3() { return 1; }
assert_eq "$(rc_of g_locked)" "2" "unavailable lock checks must be unknown"
python3() { printf '1\n'; return 0; }
assert_eq "$(rc_of g_locked)" "0" "Quartz locked=1 must be locked"
python3() { printf '0\n'; return 0; }
assert_eq "$(rc_of g_locked)" "1" "Quartz locked=0 must be unlocked"

# Unlock is explicit: locked or unknown must never satisfy the disarm condition.
g_locked() { return 0; }
assert_eq "$(rc_of g_unlocked)" "1" "locked screen must not be treated as unlocked"
assert_eq "$(rc_of g_should_disarm 0)" "1" "locked screen alone must not disarm"
assert_eq "$(rc_of g_should_disarm 1)" "0" "Bluetooth return must disarm even while locked"
g_locked() { return 1; }
assert_eq "$(rc_of g_unlocked)" "0" "unlocked screen must satisfy disarm condition"
assert_eq "$(rc_of g_should_disarm 0)" "0" "explicit unlock must disarm"
set +e
ERREXIT_OUT="$( (set -e; g_unlocked; printf 'ok') 2>/dev/null )"; ERREXIT_RC=$?
set -e
assert_eq "$ERREXIT_RC" "0" "g_unlocked must work for callers using set -e"
assert_eq "$ERREXIT_OUT" "ok" "g_unlocked must reach its predicate under set -e"
g_locked() { return 2; }
assert_eq "$(rc_of g_unlocked)" "1" "unknown lock state must not disarm"
assert_eq "$(rc_of g_should_disarm 0)" "1" "unknown lock state alone must not disarm"

# Values named as seconds must use elapsed timestamps, not poll-loop counts.
assert_eq "$(rc_of g_duration_reached 100 12 111)" "1" "duration must not complete before 12 seconds"
assert_eq "$(rc_of g_duration_reached 100 12 112)" "0" "duration must complete at exactly 12 seconds"

# Wi-Fi debounce: only due checks count; third consecutive down triggers.
WIFI_IF="en9"
wifi_last_check=0
wifi_fail_count=0
wifi_down_since=0
g_wifi_up() { return 1; }
run_rc g_wifi_poll 100
assert_eq "$LAST_RC" "1" "first Wi-Fi failure must not trigger"
assert_eq "$wifi_fail_count" "1" "first due failure increments streak"
run_rc g_wifi_poll 105
assert_eq "$LAST_RC" "1" "check inside interval must skip"
assert_eq "$wifi_fail_count" "1" "skipped check must not increment streak"
run_rc g_wifi_poll 115
assert_eq "$LAST_RC" "1" "second failure must not trigger"
run_rc g_wifi_poll 130
assert_eq "$LAST_RC" "1" "three observations before 45 seconds must not trigger"
run_rc g_wifi_poll 145
assert_eq "$LAST_RC" "0" "failure sustained for interval times streak must trigger"
g_wifi_up() { return 0; }
g_wifi_poll 160 >/dev/null 2>&1 || true
assert_eq "$wifi_fail_count" "0" "Wi-Fi recovery must reset streak"
assert_eq "$wifi_down_since" "0" "Wi-Fi recovery must reset down timer"

# Same reason is throttled during cooldown; a new reason may notify.
last_notify_reason=""
last_notify_at=0
run_rc g_notify_allowed 'Wi-Fi斷' 1000
assert_eq "$LAST_RC" "0" "first reason must notify"
run_rc g_notify_allowed 'Wi-Fi斷' 1100
assert_eq "$LAST_RC" "1" "same reason inside cooldown must throttle"
run_rc g_notify_allowed '拔電' 1100
assert_eq "$LAST_RC" "0" "different reason may notify"
run_rc g_notify_allowed '拔電' 1401
assert_eq "$LAST_RC" "0" "same reason after cooldown must notify"
run_rc g_notify_allowed 'Wi-Fi斷' 1250
assert_eq "$LAST_RC" "1" "interleaved reason must not reset Wi-Fi cooldown"

# Bot mismatch disables Telegram only; guard startup remains successful.
NOTIFY_TELEGRAM=1
notify_selftest() { return 3; }
g_locked() { return 1; }
run_rc g_startup_checks
assert_eq "$LAST_RC" "0" "startup checks must not stop guard"
assert_eq "$NOTIFY_TELEGRAM" "0" "bot mismatch must disable Telegram"

printf 'PASS: guard primitives and throttling\n'
