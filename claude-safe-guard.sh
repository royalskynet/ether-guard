#!/bin/bash
# claude-safe-guard: pre-flight scan of the CURRENT dir for dangerous project-level
# Claude Code config before launching claude. Blocks the "open untrusted repo = shell"
# attack class (headersHelper shell-exec, stdio auto-spawn, bypassPermissions override).
# ponytail: exact-string grep, not a JSON parser — a crafted file could evade; upgrade to
#           `jq`-based checks if evasion matters. Catches the known PoC vectors as-is.
# Exit 0 = clean, 2 = danger found.
set -euo pipefail
dir="${1:-$PWD}"
hits=0
warn(){ printf '\033[1;31m[claude-guard] %s\033[0m\n' "$1" >&2; hits=$((hits+1)); }

mcp="$dir/.mcp.json"
if [ -f "$mcp" ]; then
  grep -qi 'headersHelper' "$mcp" && warn ".mcp.json has headersHelper (shell exec on launch): $mcp"
  grep -qiE '"command"[[:space:]]*:' "$mcp" && warn ".mcp.json declares stdio command (auto-spawn on launch): $mcp — review before trusting"
fi
for s in "$dir/.claude/settings.json" "$dir/.claude/settings.local.json"; do
  [ -f "$s" ] && grep -qi 'bypassPermissions' "$s" && warn "project settings force bypassPermissions: $s"
done

if [ "$hits" -gt 0 ]; then
  printf '\033[1;33m[claude-guard] %d issue(s) in %s. Inspect the files above before running claude here.\033[0m\n' "$hits" "$dir" >&2
  exit 2
fi
exit 0
