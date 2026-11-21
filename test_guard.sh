#!/bin/bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -r -- "$work"' EXIT

mkdir "$work"/{clean,warn,block,memory}
printf '%s\n' 'Ordinary document.' > "$work/clean/plain.md"
printf '%s\n' 'WARNING' > "$work/warn/warning.md"
printf '%s\n' 'display:none' > "$work/block/hidden text.md"
printf '%s\n' 'WARNING' > "$work/block/warning.md"
printf '%s\n' 'NEW DIRECTIVE' > "$work/memory/directive.md"

expect_status() {
  local want="$1" got=0
  shift
  "$@" > "$work/result.log" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'Expected %s, got %s: %s\n' "$want" "$got" "$*" >&2
    cat "$work/result.log" >&2
    exit 1
  fi
}

guard() {
  bash "$here/ether-guard.sh" "$@"
}

expect_status 0 guard scan "$work/clean/plain.md"
expect_status 1 guard scan "$work/warn/warning.md"
expect_status 2 guard scan "$work/block/hidden text.md"
expect_status 2 guard scan 1 "$work/warn/warning.md"
expect_status 1 guard scan 3 "$work/block/hidden text.md"
expect_status 0 guard all "$work/clean"
expect_status 1 guard all "$work/warn"
expect_status 2 guard all "$work/block"
expect_status 2 bash "$here/memory-guard.sh" "$work/memory"
expect_status 2 guard all "$work/memory"
if grep -Fq 'All layers passed' "$work/result.log"; then
  echo 'Blocked directory scan reported success' >&2
  exit 1
fi

echo 'Guard regression tests passed'
