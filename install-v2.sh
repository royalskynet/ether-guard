#!/bin/bash
# Updated installer for ether-guard v2
# Installs all guard layers and optional Claude Code hooks
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dst="$HOME/.claude/scripts"
mkdir -p "$dst"

echo "[install] Copying guard scripts..."

# Copy all guard scripts
for script in claude-safe-guard.sh content-guard.sh memory-guard.sh tool-use-guard.sh ether-guard.sh; do
  if [ -f "$here/$script" ]; then
    cp "$here/$script" "$dst/$script"
    chmod +x "$dst/$script"
    echo "  ✓ $script"
  fi
done

# Update shell wrapper if exists
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -q 'ether-guard' "$rc"; then
    echo "[install] ether-guard wrapper already in $rc, skipping"
  else
    cat >> "$rc" <<'WRAPPER'

# --- ether-guard: multi-layer AI agent defense ---
ether-guard() {
  local guard="$HOME/.claude/scripts/ether-guard.sh"
  if [ -x "$guard" ]; then
    "$guard" "$@"
  else
    echo "[ether-guard] Script not found at $guard" >&2
    return 1
  fi
}
WRAPPER
    echo "[install] Wrapper added to $rc"
  fi
done

echo ""
echo "✅ Installation complete!"
echo ""
echo "Usage:"
echo "  ether-guard scan <file>     # Scan for content traps"
echo "  ether-guard check <tool> <args>  # Validate tool invocation"
echo "  ether-guard all <dir>       # Full directory scan"
echo ""
echo "Source your shell: source ~/.zshrc  # or ~/.bashrc"
